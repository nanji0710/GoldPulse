// test/price_api_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/price_api.dart';

/// 模拟网络失败（DNS 解析失败 / 连接错误）的适配器，
/// 使网络用例确定性、快速、不依赖真实网络。
class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'Failed host lookup: invalid.example',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 返回固定文本响应（非 JSON，如网关 502 页）的适配器。
class _TextBodyAdapter implements HttpClientAdapter {
  final String body;
  _TextBodyAdapter(this.body);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(body, 200,
        headers: const {'content-type': ['text/html']});
  }

  @override
  void close({bool force = false}) {}
}

/// 按调用顺序依次返回预设响应体的适配器（用于测试降级链逐源切换）。
class _SequentialAdapter implements HttpClientAdapter {
  final List<ResponseBody> bodies;
  int _index = 0;
  _SequentialAdapter(this.bodies);
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return bodies[_index++];
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // 实测结构（2026-08-04）：Au9999 接口返回 resultData.data.{lastPrice, preClose, ...}
  final sample = {
    'resultData': {
      'code': '0000',
      'data': {
        'lastPrice': 883.12,
        'preClose': 882.85,
        'raise': 1.29,
        'raisePercent': 0.0014629,
        'uniqueCode': 'SGE-Au(T+D)',
      },
    }
  };

  test('解析京东黄金接口响应（实测结构 resultData.data）', () {
    final gp = PriceApi.parseJdGoldPrice(sample);
    expect(gp, isNotNull);
    expect(gp!.price, closeTo(883.12, 0.001));
    expect(gp.preClose, closeTo(882.85, 0.001));
    expect(gp.change, closeTo(0.27, 0.001));
    expect(gp.code, 'SGE-Au(T+D)');
  });

  test('积存金接口结构（resultData.datas.price/yesterdayPrice）也容错解析', () {
    final gp = PriceApi.parseJdGoldPrice({
      'resultData': {
        'datas': {'price': '883.09', 'yesterdayPrice': '879.46'},
      },
    });
    expect(gp, isNotNull);
    expect(gp!.price, closeTo(883.09, 0.001));
    expect(gp.preClose, closeTo(879.46, 0.001));
  });

  test('响应缺少 data 时返回 null（降级信号）', () {
    expect(PriceApi.parseJdGoldPrice({'resultData': {}}), isNull);
  });

  test('I3：字符串数字（免费接口返回 "883.12"）也容错解析', () {
    final gp = PriceApi.parseJdGoldPrice({
      'resultData': {'data': {'lastPrice': '883.12', 'preClose': '882.85'}},
    });
    expect(gp, isNotNull);
    expect(gp!.price, closeTo(883.12, 0.001));
    expect(gp.preClose, closeTo(882.85, 0.001));
  });

  test('I3：价格字段为非法数字时返回 null（主源失效，走降级）', () {
    expect(PriceApi.parseJdGoldPrice({
      'resultData': {'data': {'lastPrice': 'abc', 'preClose': 882.85}},
    }), isNull);
    expect(PriceApi.parseJdGoldPrice({
      'resultData': {'data': {'lastPrice': 883.12, 'preClose': '--'}},
    }), isNull);
  });

  test('I3：非 JSON 响应抛 ApiException 且降级链返回 null 而非冒泡 FormatException', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://invalid.example'));
    dio.httpClientAdapter = _TextBodyAdapter('<html>Bad Gateway</html>');
    final api = PriceApi(dio: dio);
    await expectLater(api.fetchGoldPrice('SGE-Au(T+D)'), throwsA(isA<ApiException>()));
    // 降级链：主源抛 ApiException → 备用源（同样返回坏文本）→ 返回 null。
    expect(await api.fetchGoldPriceWithFallback('SGE-Au(T+D)'), isNull);
  });

  test('请求失败抛出 ApiException', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://invalid.example'));
    dio.httpClientAdapter = _FailingAdapter();
    final api = PriceApi(dio: dio);
    await expectLater(
      api.fetchGoldPrice('SGE-Au(T+D)'),
      throwsA(isA<ApiException>()),
    );
  });

  test('东方财富备用源解析（实测结构 data.f43/f60，价格×100 缩放）', () {
    final gp = PriceApi.parseEastmoneyGoldPrice({
      'data': {'f43': 88380, 'f60': 88304, 'f57': 'AU9999'},
    });
    expect(gp, isNotNull);
    expect(gp!.price, closeTo(883.80, 0.001));
    expect(gp.preClose, closeTo(883.04, 0.001));
    expect(gp.change, closeTo(0.76, 0.001));
    expect(gp.code, 'AU9999');
  });

  test('东方财富缺少 data 时返回 null（继续降级）', () {
    expect(PriceApi.parseEastmoneyGoldPrice({'rc': 100}), isNull);
  });

  test('新浪接口解析（字段为 s2/h 格式字符串）', () {
    // 新浪 gold T+D 行情格式：var hq_str="1,沪金T+D,开,昨收,最新,..."
    // （字段序号随品种可能变化，本映射需上线时对真实行情实测校准）
    final gp = PriceApi.parseSinaGoldPrice(
        'var hq_str=gold="1,沪金T+D,780.20,779.00,776.70"',
        code: 'SGE-Au(T+D)');
    expect(gp, isNotNull);
    expect(gp!.price, closeTo(776.70, 0.001));   // 最新价 = 索引 4
    expect(gp.preClose, closeTo(779.00, 0.001)); // 昨收 = 索引 3
  });

  test('解析出的价格带数据源标签', () {
    final gp = PriceApi.parseJdGoldPrice(sample);
    expect(gp!.source, '京东');
    final em = PriceApi.parseEastmoneyGoldPrice(
        {'data': {'f43': 88380, 'f60': 88304}});
    expect(em!.source, '东方财富');
    final sina = PriceApi.parseSinaGoldPrice('var x="1,金,1,2,3"');
    expect(sina!.source, '新浪');
  });

  test('京东返回合法 JSON 但缺价 → 继续降级到东方财富（不再提前返回 null）', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://invalid.example'));
    dio.httpClientAdapter = _SequentialAdapter([
      // 京东：合法 JSON 但 data 无价格字段 → 解析为 null。
      ResponseBody.fromString(
          jsonEncode({'resultData': {'data': {}}}), 200,
          headers: {'content-type': ['application/json']}),
      // 东方财富：正常数据。
      ResponseBody.fromString(
          jsonEncode({'data': {'f43': 88380, 'f60': 88304, 'f57': 'AU9999'}}),
          200,
          headers: {'content-type': ['application/json']}),
    ]);
    final api = PriceApi(dio: dio);
    final gp = await api.fetchGoldPriceWithFallback('SGE-Au(T+D)');
    expect(gp, isNotNull);
    expect(gp!.price, closeTo(883.80, 0.001));
    expect(gp.source, '东方财富');
  });

  test('积存金：京东网络失败 → 降级到东方财富 Au9999 参考价', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://invalid.example'));
    dio.httpClientAdapter = _SequentialAdapter([
      ResponseBody.fromString('<html>Bad Gateway</html>', 502,
          headers: {'content-type': ['text/html']}),
      ResponseBody.fromString(
          jsonEncode({'data': {'f43': 88380, 'f60': 88304}}), 200,
          headers: {'content-type': ['application/json']}),
    ]);
    final api = PriceApi(dio: dio);
    final gp = await api.fetchAccumulationPriceWithFallback();
    expect(gp, isNotNull);
    expect(gp!.price, closeTo(883.80, 0.001));
    expect(gp.code, 'CZB-JCJ');
    expect(gp.source, 'Au9999 参考');
  });

  test('积存金：京东返回缺价 JSON → 继续降级而非返回 null', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://invalid.example'));
    dio.httpClientAdapter = _SequentialAdapter([
      ResponseBody.fromString(
          jsonEncode({'resultData': {'datas': {}}}), 200,
          headers: {'content-type': ['application/json']}),
      ResponseBody.fromString(
          jsonEncode({'data': {'f43': 88380, 'f60': 88304}}), 200,
          headers: {'content-type': ['application/json']}),
    ]);
    final api = PriceApi(dio: dio);
    final gp = await api.fetchAccumulationPriceWithFallback();
    expect(gp, isNotNull);
    expect(gp!.source, 'Au9999 参考');
  });

  test('全部源都失败 → 返回 null（调用方回落本地缓存）', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://invalid.example'));
    dio.httpClientAdapter = _FailingAdapter();
    final api = PriceApi(dio: dio);
    expect(await api.fetchAccumulationPriceWithFallback(), isNull);
  });
}
