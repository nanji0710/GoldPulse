// lib/services/price_api.dart
// 行情接口适配层：主源（京东黄金） + 备用源（新浪行情 hq.sinajs.cn）降级链。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/gold_price.dart';

/// 行情诊断日志（release 构建同样输出到 logcat，tag=flutter），
/// 排查"行情加载中/降级切换"问题不再依赖截图，直接读日志。
void _log(String msg) => debugPrint('[金脉行情] $msg');

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => 'ApiException: $message';
}

class PriceApi {
  final Dio dio;
  PriceApi({required this.dio});

  static const jdGoldUrl =
      'https://api.jdjygold.com/gw2/generic/produTools/h5/m/getGoldPrice';

  /// 浙商积存金最新价接口（京东黄金）。
  /// 实测（2026-08-04）：resultData.datas.{price, yesterdayPrice, upAndDownAmt, upAndDownRate}
  static const _jdStdUrl =
      'https://api.jdjygold.com/gw2/generic/jrm/h5/m/stdLatestPrice';
  static const _zheShangSku = '1961543816'; // 浙商积存金 productSku

  /// 拉取浙商积存金最新价。失败抛 [ApiException]，由调用方降级到缓存。
  Future<GoldPrice?> fetchAccumulationPrice() async {
    try {
      final res = await dio.get(_jdStdUrl,
          queryParameters: {'productSku': _zheShangSku},
          options: Options(receiveTimeout: const Duration(seconds: 8), sendTimeout: const Duration(seconds: 8)));
      var data = res.data;
      if (data is String) {
        try {
          data = jsonDecode(data); // dio 某些情况返回字符串
        } on FormatException {
          throw ApiException('响应非合法 JSON');
        }
      }
      if (data is! Map<String, dynamic>) throw ApiException('响应结构非法');
      return parseJdGoldPrice(data, fallbackCode: 'CZB-JCJ');
    } on DioException catch (e) {
      throw ApiException('网络请求失败: ${e.message}');
    }
  }

  /// 拉取某行情代码的最新价。失败时抛 [ApiException]，由调用方降级。
  /// 畸形响应（非 JSON / 结构非法）也转为 [ApiException]，使降级链能切换备用源，
  /// 而不是让 FormatException/TypeError 直接冒泡打断轮询流。
  Future<GoldPrice?> fetchGoldPrice(String code) async {
    try {
      final res = await dio.get(jdGoldUrl, queryParameters: {'goldCode': code},
          options: Options(receiveTimeout: const Duration(seconds: 8), sendTimeout: const Duration(seconds: 8)));
      var data = res.data;
      if (data is String) {
        try {
          data = jsonDecode(data); // dio 某些情况返回字符串
        } on FormatException {
          throw ApiException('响应非合法 JSON');
        }
      }
      if (data is! Map<String, dynamic>) throw ApiException('响应结构非法');
      return parseJdGoldPrice(data, fallbackCode: code);
    } on DioException catch (e) {
      throw ApiException('网络请求失败: ${e.message}');
    }
  }

  /// 新浪行情解析（备用源）。
  /// 新浪 gold T+D 行情格式：var hq_str="1,沪金T+D,开,昨收,最新,..."
  /// 索引：0=市场 1=名称 2=开盘 3=昨收 4=最新（字段序号随品种可能变化，上线时需实测校准）
  static GoldPrice? parseSinaGoldPrice(String raw,
      {String code = 'SGE-Au(T+D)', String source = '新浪'}) {
    final m = RegExp(r'"([^"]*)"').firstMatch(raw);
    if (m == null) return null;
    final parts = m.group(1)!.split(',');
    if (parts.length < 5) return null;
    final price = double.tryParse(parts[4]);     // 最新价
    final preClose = double.tryParse(parts[3]);  // 昨收
    if (price == null || preClose == null) return null;
    return GoldPrice(
        code: code, price: price, change: price - preClose,
        percent: preClose == 0 ? 0 : (price - preClose) / preClose * 100,
        preClose: preClose, time: DateTime.now().millisecondsSinceEpoch,
        source: source);
  }

  static const _eastmoneyUrl = 'https://push2.eastmoney.com/api/qt/stock/get';

  /// 东方财富 Au9999（上金所）备用源请求（积存金降级时也复用它，作为参考价）。
  Future<GoldPrice?> _eastmoneyPrice(
      {required String code, String source = '东方财富'}) async {
    final res = await dio.get(_eastmoneyUrl,
        queryParameters: {
          'secid': '118.AU9999',
          'fields': 'f43,f44,f45,f46,f57,f58,f60,f170',
        },
        options: Options(receiveTimeout: const Duration(seconds: 8)));
    if (res.data is! Map<String, dynamic>) return null;
    return parseEastmoneyGoldPrice(res.data as Map<String, dynamic>,
        code: code, source: source);
  }

  /// 新浪 Au9999 备用源请求。
  Future<GoldPrice?> _sinaPrice(
      {required String code, String source = '新浪'}) async {
    final res = await dio.get('https://hq.sinajs.cn/list=shau9999',
        options: Options(
          // dio 5.x 的 Options 无 connectTimeout，沿用主源的 receiveTimeout。
          receiveTimeout: const Duration(seconds: 8),
          // 新浪接口校验 Referer，缺失时可能返回空响应。
          headers: {'Referer': 'https://finance.sina.com.cn/'},
        ));
    return parseSinaGoldPrice(res.data.toString(), code: code, source: source);
  }

  /// Au9999 降级链：京东 → 东方财富 → 新浪 → null（调用方回落本地缓存）。
  /// 注意：京东返回合法 JSON 但解析不出价格（返回 null）同样继续降级，
  /// 不能提前返回 —— 否则京东一次异常响应就切断整条降级链。
  Future<GoldPrice?> fetchGoldPriceWithFallback(String code) async {
    try {
      final gp = await fetchGoldPrice(code);
      if (gp != null) {
        _log('Au9999 主源京东成功: ${gp.price} 元/g @${gp.time}');
        return gp;
      }
      _log('Au9999 京东返回空数据（无价格字段），继续降级');
    } on ApiException catch (e) {
      _log('Au9999 京东失败: ${e.message}');
    }
    try {
      final gp = await _eastmoneyPrice(code: code);
      if (gp != null) {
        _log('Au9999 备用东方财富成功: ${gp.price} 元/g');
        return gp;
      }
      _log('Au9999 东方财富返回空数据，继续降级');
    } on DioException catch (e) {
      _log('Au9999 东方财富失败: ${e.message}');
    }
    try {
      final gp = await _sinaPrice(code: code);
      if (gp != null) {
        _log('Au9999 兜底新浪成功: ${gp.price} 元/g');
        return gp;
      }
      _log('Au9999 新浪返回空数据');
    } on DioException catch (e) {
      _log('Au9999 新浪失败: ${e.message}');
    }
    _log('Au9999 全部行情源失败');
    return null;
  }

  /// 浙商积存金降级链：京东积存金 → 东方财富 Au9999（参考价）→ 新浪 → null。
  /// 京东免费接口不稳定，若不给积存金配备用源，京东一挂该卡片就永远"加载中"。
  Future<GoldPrice?> fetchAccumulationPriceWithFallback() async {
    try {
      final gp = await fetchAccumulationPrice();
      if (gp != null) {
        _log('积存金 主源京东成功: ${gp.price} 元/g @${gp.time}');
        return gp;
      }
      _log('积存金 京东返回空数据（无价格字段），继续降级');
    } on ApiException catch (e) {
      _log('积存金 京东失败: ${e.message}');
    }
    try {
      final gp = await _eastmoneyPrice(code: 'CZB-JCJ', source: 'Au9999 参考');
      if (gp != null) {
        _log('积存金 备用东方财富(Au9999 参考)成功: ${gp.price} 元/g');
        return gp;
      }
      _log('积存金 东方财富返回空数据，继续降级');
    } on DioException catch (e) {
      _log('积存金 东方财富失败: ${e.message}');
    }
    try {
      final gp = await _sinaPrice(code: 'CZB-JCJ', source: '新浪');
      if (gp != null) {
        _log('积存金 兜底新浪成功: ${gp.price} 元/g');
        return gp;
      }
      _log('积存金 新浪返回空数据');
    } on DioException catch (e) {
      _log('积存金 新浪失败: ${e.message}');
    }
    _log('积存金 全部行情源失败');
    return null;
  }

  /// 东方财富 Au9999（上金所）解析。实测（2026-08-04）：
  ///   data.f43=最新价（×100 缩放，88380→883.80），f60=昨收（×100），
  ///   f57=代码，f58=名称，f170=涨跌幅（×100）。
  static GoldPrice? parseEastmoneyGoldPrice(Map<String, dynamic> json,
      {String code = 'SGE-Au(T+D)', String source = '东方财富'}) {
    final data = json['data'];
    if (data is! Map) return null;
    final price = _toDouble(data['f43']);
    final preClose = _toDouble(data['f60']);
    if (price == null || preClose == null) return null;
    const scale = 100.0; // 东财价格按 100 缩放
    final p = price / scale;
    final pre = preClose / scale;
    return GoldPrice(
      code: (data['f57'] as String?) ?? code,
      price: p,
      change: p - pre,
      percent: pre == 0 ? 0 : (p - pre) / pre * 100,
      preClose: pre,
      time: DateTime.now().millisecondsSinceEpoch,
      source: source,
    );
  }

  /// 容错解析：遍历可能的字段路径。字段变动时只需改本方法。
  /// 实测结构（2026-08-04）：
  ///   Au9999:  resultData.data.{lastPrice, preClose, raise, raisePercent, uniqueCode}
  ///   积存金:  resultData.datas.{price, yesterdayPrice, upAndDownAmt, upAndDownRate}
  /// 旧参考项目假设 resultData.quote.{...}，与实测不符，已按实测修正。
  static GoldPrice? parseJdGoldPrice(Map<String, dynamic> json,
      {String fallbackCode = 'SGE-Au(T+D)', String source = '京东'}) {
    final rd = json['resultData'];
    if (rd is! Map) return null;
    final data = rd['data'] ?? rd['datas'] ?? rd['quote'] ?? rd;
    if (data is! Map) return null;
    final price = data['lastPrice'] ?? data['price'] ?? data['current'] ?? data['latest'];
    final preClose = data['preClose'] ?? data['yesterdayPrice'] ?? data['preClosePrice'] ?? data['yclose'];
    final p = _toDouble(price);
    final pre = _toDouble(preClose);
    // 数值非法（null / 非数字字符串）→ 视为主源失效，返回 null 走降级。
    if (p == null || pre == null) return null;
    return GoldPrice(
      code: (data['uniqueCode'] as String?) ?? (data['code'] as String?) ?? fallbackCode,
      price: p,
      change: p - pre,
      percent: pre == 0 ? 0 : (p - pre) / pre * 100,
      preClose: pre,
      time: DateTime.now().millisecondsSinceEpoch,
      source: source,
    );
  }

  /// 容错数值转换：接受 num 或纯数字字符串（如免费接口返回 "780.20"）；
  /// 其余情况（null / 非数字）返回 null，由调用方按"主源失效"处理。
  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
