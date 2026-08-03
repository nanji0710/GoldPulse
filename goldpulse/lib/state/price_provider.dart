// lib/state/price_provider.dart
// 行情全局状态：价格轮询 StreamProvider + 依赖注入入口。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/price_dao.dart';
import '../models/gold_price.dart';
import '../services/market_hours.dart';
import '../services/price_api.dart';

/// 由 main.dart 在应用启动时 override（注入真实 Dio）。
/// 测试中通过 override 注入假 Dio，避免真实网络请求。
final dioProvider = Provider<Dio>((ref) => throw UnimplementedError('dioProvider 在 main.dart override'));

final priceApiProvider = Provider((ref) => PriceApi(dio: ref.watch(dioProvider)));
final priceDaoProvider = Provider((ref) => PriceDao());

/// 行情轮询：交易时段每 2 分钟拉取并入库；休市保持缓存（省电）。失败降级为缓存。
final priceProvider = StreamProvider<GoldPrice?>((ref) async* {
  final api = ref.watch(priceApiProvider);
  final dao = ref.watch(priceDaoProvider);
  GoldPrice? last = await dao.latest('SGE-Au(T+D)');
  yield last;
  while (true) {
    if (MarketHours.isTrading(DateTime.now())) {
      try {
        final fresh = await api.fetchGoldPrice('SGE-Au(T+D)');
        if (fresh != null) {
          await dao.insert(fresh);
          last = fresh;
        }
      } on ApiException {
        // 主源失败：保留缓存
      }
    }
    yield last;
    await Future.delayed(const Duration(minutes: 2));
  }
});
