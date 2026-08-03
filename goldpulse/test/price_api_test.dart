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

void main() {
  // 参考项目返回样例（字段以实测为准，容错解析）
  final sample = {
    'resultData': {
      'quote': {'price': 780.20, 'preClose': 776.70},
    }
  };

  test('解析京东黄金接口响应', () {
    final gp = PriceApi.parseJdGoldPrice(sample);
    expect(gp, isNotNull);
    expect(gp!.price, closeTo(780.20, 0.001));
    expect(gp.preClose, closeTo(776.70, 0.001));
    expect(gp.code, 'SGE-Au(T+D)');
  });

  test('响应缺少 quote 时返回 null（降级信号）', () {
    expect(PriceApi.parseJdGoldPrice({'resultData': {}}), isNull);
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
}
