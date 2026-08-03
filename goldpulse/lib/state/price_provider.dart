// lib/state/price_provider.dart
// 行情全局状态：价格轮询 StreamProvider + 依赖注入入口。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/price_dao.dart';
import '../models/gold_price.dart';
import '../services/market_hours.dart';
import '../services/price_api.dart';

/// 由 main.dart 在应用启动时 override（注入真实 Dio）。
/// 测试中通过 override 注入假 Dio，避免真实网络请求。
final dioProvider = Provider<Dio>((ref) => throw UnimplementedError('dioProvider 在 main.dart override'));

final priceApiProvider = Provider((ref) => PriceApi(dio: ref.watch(dioProvider)));
final priceDaoProvider = Provider((ref) => PriceDao());

/// 行情刷新间隔偏好（秒），由设置页写入，默认 120 秒（2 分钟）。
const refreshIntervalPrefKey = 'refreshIntervalSeconds';

final refreshIntervalProvider = FutureProvider<Duration>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final seconds = prefs.getInt(refreshIntervalPrefKey);
  return Duration(seconds: seconds ?? 120);
});

/// 行情轮询：交易时段每隔 [refreshIntervalProvider] 拉取并入库；休市保持缓存（省电）。
/// 失败降级为缓存。间隔偏好变化时（设置页修改后 invalidate）本流自动重启。
final priceProvider = StreamProvider<GoldPrice?>((ref) async* {
  final api = ref.watch(priceApiProvider);
  final dao = ref.watch(priceDaoProvider);
  final interval = ref.watch(refreshIntervalProvider).valueOrNull ?? const Duration(minutes: 2);
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
    await Future.delayed(interval);
  }
});
