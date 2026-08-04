// lib/services/price_api.dart
// 行情接口适配层：主源（京东黄金） + 备用源（新浪行情 hq.sinajs.cn）降级链。
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/gold_price.dart';

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
  static GoldPrice? parseSinaGoldPrice(String raw, {String code = 'SGE-Au(T+D)'}) {
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
        preClose: preClose, time: DateTime.now().millisecondsSinceEpoch);
  }

  /// 降级链：主源 → 备用源 → null（调用方回落本地缓存）。
  Future<GoldPrice?> fetchGoldPriceWithFallback(String code) async {
    try { return await fetchGoldPrice(code); } on ApiException { /* fall */ }
    try {
      final res = await dio.get('https://hq.sinajs.cn/list=shau9999',
          options: Options(
            // dio 5.x 的 Options 无 connectTimeout，沿用主源的 receiveTimeout。
            receiveTimeout: const Duration(seconds: 8),
            // 新浪接口校验 Referer，缺失时可能返回空响应。
            headers: {'Referer': 'https://finance.sina.com.cn/'},
          ));
      return parseSinaGoldPrice(res.data.toString(), code: code);
    } on DioException { return null; }
  }

  /// 容错解析：遍历可能的字段路径。字段变动时只需改本方法。
  /// 实测结构（2026-08-04）：
  ///   Au9999:  resultData.data.{lastPrice, preClose, raise, raisePercent, uniqueCode}
  ///   积存金:  resultData.datas.{price, yesterdayPrice, upAndDownAmt, upAndDownRate}
  /// 旧参考项目假设 resultData.quote.{...}，与实测不符，已按实测修正。
  static GoldPrice? parseJdGoldPrice(Map<String, dynamic> json, {String fallbackCode = 'SGE-Au(T+D)'}) {
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
