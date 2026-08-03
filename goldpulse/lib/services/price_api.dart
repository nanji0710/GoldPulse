// lib/services/price_api.dart
// 行情接口适配层：主源（京东黄金） + 降级信号。
// 备用源（新浪行情 hq.sinajs.cn）将在 Task 15 接入，解析逻辑收敛在本文件。
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
  Future<GoldPrice?> fetchGoldPrice(String code) async {
    try {
      final res = await dio.get(jdGoldUrl, queryParameters: {'goldCode': code},
          options: Options(receiveTimeout: const Duration(seconds: 8), sendTimeout: const Duration(seconds: 8)));
      var data = res.data;
      if (data is String) data = jsonDecode(data); // dio 某些情况返回字符串
      return parseJdGoldPrice(data, fallbackCode: code);
    } on DioException catch (e) {
      throw ApiException('网络请求失败: ${e.message}');
    }
  }

  /// 容错解析：遍历可能的字段路径。字段变动时只需改本方法。
  static GoldPrice? parseJdGoldPrice(Map<String, dynamic> json, {String fallbackCode = 'SGE-Au(T+D)'}) {
    final rd = json['resultData'];
    if (rd is! Map) return null;
    final quote = rd['quote'] ?? rd;
    if (quote is! Map) return null;
    final price = (quote['price'] ?? quote['current'] ?? quote['last']);
    final preClose = (quote['preClose'] ?? quote['preClosePrice'] ?? quote['yclose']);
    if (price == null || preClose == null) return null;
    final p = (price as num).toDouble();
    final pre = (preClose as num).toDouble();
    return GoldPrice(
      code: (quote['code'] as String?) ?? fallbackCode,
      price: p,
      change: p - pre,
      percent: pre == 0 ? 0 : (p - pre) / pre * 100,
      preClose: pre,
      time: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
