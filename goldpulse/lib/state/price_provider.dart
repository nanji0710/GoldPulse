// lib/state/price_provider.dart
// 行情全局状态：价格轮询 StreamProvider + 依赖注入入口。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/price_dao.dart';
import '../models/gold_price.dart';
import '../services/market_hours.dart';
import '../services/price_api.dart';
import 'alert_provider.dart';
import 'holding_provider.dart';

/// 由 main.dart 在应用启动时 override（注入真实 Dio）。
/// 测试中通过 override 注入假 Dio，避免真实网络请求。
final dioProvider = Provider<Dio>((ref) => throw UnimplementedError('dioProvider 在 main.dart override'));

final priceApiProvider = Provider((ref) => PriceApi(dio: ref.watch(dioProvider)));
final priceDaoProvider = Provider((ref) => PriceDao());

/// 交易时段判定（默认实时计算）。抽成 Provider 仅为让测试能注入确定性结果，
/// 从而在不依赖系统时钟的前提下驱动轮询测试。
final isTradingNowProvider = Provider<bool Function()>((ref) => () => MarketHours.isTrading(DateTime.now()));

/// 下次刷新时刻（秒级倒计时展示用）。两个轮询器每次调度后写入。
class NextRefreshNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;
  void set(DateTime t) => state = t;
}

final nextRefreshProvider =
    NotifierProvider<NextRefreshNotifier, DateTime?>(NextRefreshNotifier.new);

/// 行情刷新间隔偏好（秒），由设置页写入，默认 120 秒（2 分钟）。
const refreshIntervalPrefKey = 'refreshIntervalSeconds';

final refreshIntervalProvider = FutureProvider<Duration>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final seconds = prefs.getInt(refreshIntervalPrefKey);
  return Duration(seconds: seconds ?? 120);
});

/// 行情轮询：交易时段每隔 [refreshIntervalProvider] 拉取并入库；休市保持缓存（省电）。
/// 失败自动降级：主源（京东） → 备用源（新浪） → 缓存。
/// 间隔偏好变化时（设置页修改后 invalidate）本流自动重启。
final priceProvider = StreamProvider<GoldPrice?>((ref) async* {
  final api = ref.watch(priceApiProvider);
  final dao = ref.watch(priceDaoProvider);
  final interval = ref.watch(refreshIntervalProvider).valueOrNull ?? const Duration(minutes: 2);
  // 依赖在进入长驻循环前一次性捕获：不能在 async* 循环体内 read Provider ref，
  // 否则流因 refreshIntervalProvider 解析而重建后，残留协程会崩溃在已销毁的元素上。
  final isTradingNow = ref.watch(isTradingNowProvider);
  final holdingDao = ref.watch(holdingDaoProvider);
  final alertDao = ref.watch(alertDaoProvider);
  final notifications = ref.watch(notificationsPluginProvider);
  final nextRefresh = ref.watch(nextRefreshProvider.notifier);
  GoldPrice? last = await dao.latest('SGE-Au(T+D)');
  yield last;
  while (true) {
    // 交易中才轮询（省电）；但若无任何缓存数据（新装/清库），休市时段也拉取一次，
    // 避免新用户休市时段无限"行情加载中"。
    if (isTradingNow() || last == null) {
      try {
        final fresh = await api.fetchGoldPriceWithFallback('SGE-Au(T+D)');
        if (fresh != null) {
          await dao.insert(fresh);
          last = fresh;
          // 前台告警判定：行情轮询收到新价即触发提醒判定，
          // 价格（price_up/price_down）与资产（profit_target）命中即本地通知。
          // 后台 isolate 抓取判定仍为未来细化（见 main.dart callbackDispatcher 注释）。
          try {
            var assetValue = 0.0;
            var totalCost = 0.0;
            for (final h in await holdingDao.list()) {
              assetValue += fresh.price * h.amount;
              totalCost += h.totalCost;
            }
            await runAlertChecks(
                dao: alertDao,
                plugin: notifications,
                price: fresh.price,
                assetValue: assetValue,
                totalCost: totalCost);
          } catch (_) {
            // 告警判定失败（如通知/DB 异常）不影响行情轮询。
          }
        }
      } catch (_) {
        // 防御性兜底：任何意外错误（含解析异常）都保留缓存继续轮询，
        // 避免畸形响应把 StreamProvider 打成 AsyncError 而永久停止。
      }
    }
    yield last;
    // 尚无任何数据时（新装/清库/首拉失败）用 30s 快速重试，直到首次成功；
    // 已有缓存后恢复配置间隔（省电）。
    final delay = last == null ? const Duration(seconds: 30) : interval;
    nextRefresh.set(DateTime.now().add(delay));
    await Future.delayed(delay);
  }
});

/// 浙商积存金行情轮询（京东积存金接口，code='CZB-JCJ'）。
/// 用户实际持仓品种：首页价格卡与盈亏计算均以其为准。
/// 同样：交易中才轮询；无缓存时休市也拉取一次；失败降级到本地缓存。
final accumulationPriceProvider = StreamProvider<GoldPrice?>((ref) async* {
  final api = ref.watch(priceApiProvider);
  final dao = ref.watch(priceDaoProvider);
  final interval = ref.watch(refreshIntervalProvider).valueOrNull ?? const Duration(minutes: 2);
  final isTradingNow = ref.watch(isTradingNowProvider);
  final nextRefresh = ref.watch(nextRefreshProvider.notifier);
  GoldPrice? last = await dao.latest('CZB-JCJ');
  yield last;
  while (true) {
    if (isTradingNow() || last == null) {
      try {
        final fresh = await api.fetchAccumulationPrice();
        if (fresh != null) {
          await dao.insert(fresh);
          last = fresh;
        }
      } catch (_) {
        // 拉取失败保留缓存继续轮询。
      }
    }
    yield last;
    final delay = last == null ? const Duration(seconds: 30) : interval;
    nextRefresh.set(DateTime.now().add(delay));
    await Future.delayed(delay);
  }
});
