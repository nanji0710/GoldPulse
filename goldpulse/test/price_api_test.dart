// test/price_api_test.dart
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
}
