// lib/state/price_provider.dart
// 行情全局状态：价格轮询 StreamProvider + 依赖注入入口。
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

/// 下次刷新时刻 + 本次实际调度间隔 + 是否处于快速重试（无缓存且拉取失败）。
/// 两个轮询器每次调度后写入，供首页秒级倒计时与文案展示。
class NextRefreshNotifier
    extends Notifier<({DateTime at, Duration delay, bool retrying})?> {
  @override
  ({DateTime at, Duration delay, bool retrying})? build() => null;
  void set(DateTime at, Duration delay, {bool retrying = false}) =>
      state = (at: at, delay: delay, retrying: retrying);
}

final nextRefreshProvider = NotifierProvider<NextRefreshNotifier,
    ({DateTime at, Duration delay, bool retrying})?>(NextRefreshNotifier.new);

/// 底部刷新频率文案：仅真实进入快速重试（无缓存且拉取失败，30 秒一轮）
/// 时提示"获取失败"，正常模式一律显示用户配置的刷新间隔。
/// 抽出为纯函数便于单元测试。
String nextRefreshFreqText(
    {required bool retrying, required Duration configured}) {
  if (retrying) return '行情获取失败，每 30 秒自动重试';
  if (configured.inMinutes > 0) return '每 ${configured.inMinutes} 分钟刷新';
  return '每 ${configured.inSeconds} 秒刷新';
}

/// 行情刷新间隔偏好（秒），由设置页写入，默认 120 秒（2 分钟）。
const refreshIntervalPrefKey = 'refreshIntervalSeconds';

final refreshIntervalProvider = FutureProvider<Duration>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final seconds = prefs.getInt(refreshIntervalPrefKey);
  return Duration(seconds: seconds ?? 120);
});

/// 行情轮询：按设定间隔 [refreshIntervalProvider] 持续拉取并入库（含收盘时段——
/// 银行积存金等品种收盘后价格仍会变动，手动刷新有价、自动刷新必须同样有价）。
/// 失败自动降级：主源（京东） → 东方财富参考 → 新浪 → 缓存。
/// 间隔偏好变化时（设置页修改后 invalidate）本流自动重启。
final priceProvider = StreamProvider<GoldPrice?>((ref) async* {
  final api = ref.watch(priceApiProvider);
  final dao = ref.watch(priceDaoProvider);
  final interval = ref.watch(refreshIntervalProvider).valueOrNull ?? const Duration(minutes: 2);
  // 依赖在进入长驻循环前一次性捕获：不能在 async* 循环体内 read Provider ref，
  // 否则流因 refreshIntervalProvider 解析而重建后，残留协程会崩溃在已销毁的元素上。
  final holdingDao = ref.watch(holdingDaoProvider);
  final alertDao = ref.watch(alertDaoProvider);
  final notifications = ref.watch(notificationsPluginProvider);
  final nextRefresh = ref.watch(nextRefreshProvider.notifier);
  GoldPrice? last = await dao.latest('SGE-Au(T+D)');
  debugPrint('[金脉行情] Au9999 轮询启动，DB缓存: ${last?.price ?? "无"} @ ${last?.time ?? "-"}');
  yield last;
  while (true) {
    // 每次调度都拉取：不再用交易时段门控暂停自动刷新（状态胶囊仍提示市场时段）。
    try {
      final fresh = await api.fetchGoldPriceWithFallback('SGE-Au(T+D)');
      if (fresh != null) {
        debugPrint('[金脉行情] Au9999 入库: ${fresh.source} ${fresh.price} @${fresh.time}');
        await dao.insert(fresh);
        last = fresh;
        // 前台告警判定：行情轮询收到新价即触发提醒判定，
        // 价格（price_up/price_down）与收益（profit_target，资产-成本）命中即本地通知。
        // 后台 isolate 抓取判定仍为未来细化（见 main.dart callbackDispatcher 注释）。
        try {
          // 收益目标按本品种持仓利润判定：只统计同品种持仓（kind 过滤）。
          var assetValue = 0.0;
          var totalCost = 0.0;
          for (final h in await holdingDao.list()) {
            if (h.kind != 'au9999') continue;
            assetValue += fresh.price * h.amount;
            totalCost += h.totalCost;
          }
          await runAlertChecks(
              dao: alertDao,
              plugin: notifications,
              price: fresh.price,
              assetValue: assetValue,
              totalCost: totalCost,
              kind: 'au9999');
        } catch (_) {
          // 告警判定失败（如通知/DB 异常）不影响行情轮询。
        }
      }
    } catch (_) {
      // 防御性兜底：任何意外错误（含解析异常）都保留缓存继续轮询，
      // 避免畸形响应把 StreamProvider 打成 AsyncError 而永久停止。
    }
    yield last;
    // 尚无任何数据时（新装/清库/首拉失败）用 30s 快速重试，直到首次成功；
    // 已有缓存后按用户配置间隔持续刷新。
    final delay = last == null ? const Duration(seconds: 30) : interval;
    debugPrint('[金脉行情] Au9999 下次调度 ${delay.inSeconds}s'
        ' (${last == null ? "快速重试" : "正常间隔"})');
    nextRefresh.set(DateTime.now().add(delay), delay, retrying: last == null);
    await Future.delayed(delay);
  }
});

/// 浙商积存金行情轮询（统一 getGoldPrice 接口，code='CZB-JCJ'）。
/// 用户实际持仓品种：首页价格卡与盈亏计算均以其为准。
/// 按设定间隔持续轮询（含收盘时段）；失败降级到本地缓存。
final accumulationPriceProvider = StreamProvider<GoldPrice?>((ref) async* {
  final api = ref.watch(priceApiProvider);
  final dao = ref.watch(priceDaoProvider);
  final interval = ref.watch(refreshIntervalProvider).valueOrNull ?? const Duration(minutes: 2);
  final nextRefresh = ref.watch(nextRefreshProvider.notifier);
  final holdingDao = ref.watch(holdingDaoProvider);
  final alertDao = ref.watch(alertDaoProvider);
  final notifications = ref.watch(notificationsPluginProvider);
  GoldPrice? last = await dao.latest('CZB-JCJ');
  debugPrint('[金脉行情] 积存金 轮询启动，DB缓存: ${last?.price ?? "无"} @ ${last?.time ?? "-"}');
  yield last;
  while (true) {
    try {
      // 降级链：京东积存金 → 东方财富 Au9999 参考价 → 新浪。
      final fresh = await api.fetchAccumulationPriceWithFallback();
      if (fresh != null) {
        debugPrint('[金脉行情] 积存金 入库: ${fresh.source} ${fresh.price} @${fresh.time}');
        await dao.insert(fresh);
        last = fresh;
        // 前台告警判定：仅判定 'accumulation' 品种的价格提醒；
        // 各品种轮询只判定同品种提醒（含收益目标，按本品种持仓利润）。
        try {
          var assetValue = 0.0;
          var totalCost = 0.0;
          for (final h in await holdingDao.list()) {
            if (h.kind != 'accumulation') continue;
            assetValue += fresh.price * h.amount;
            totalCost += h.totalCost;
          }
          await runAlertChecks(
              dao: alertDao,
              plugin: notifications,
              price: fresh.price,
              assetValue: assetValue,
              totalCost: totalCost,
              kind: 'accumulation');
        } catch (_) {
          // 告警判定失败不影响行情轮询。
        }
      }
    } catch (_) {
      // 拉取失败保留缓存继续轮询。
    }
    yield last;
    final delay = last == null ? const Duration(seconds: 30) : interval;
    debugPrint('[金脉行情] 积存金 下次调度 ${delay.inSeconds}s'
        ' (${last == null ? "快速重试" : "正常间隔"})');
    nextRefresh.set(DateTime.now().add(delay), delay, retrying: last == null);
    await Future.delayed(delay);
  }
});

/// 工商积存金行情轮询（统一 getGoldPrice 接口，code='ICBC-JCJ'）。
/// 模式与 [accumulationPriceProvider] 完全一致：按设定间隔持续轮询；
/// 失败降级到本地缓存；无数据时 30s 快速重试。
final icbcPriceProvider = StreamProvider<GoldPrice?>((ref) async* {
  final api = ref.watch(priceApiProvider);
  final dao = ref.watch(priceDaoProvider);
  final interval = ref.watch(refreshIntervalProvider).valueOrNull ?? const Duration(minutes: 2);
  final nextRefresh = ref.watch(nextRefreshProvider.notifier);
  final holdingDao = ref.watch(holdingDaoProvider);
  final alertDao = ref.watch(alertDaoProvider);
  final notifications = ref.watch(notificationsPluginProvider);
  GoldPrice? last = await dao.latest('ICBC-JCJ');
  debugPrint('[金脉行情] 工商积存金 轮询启动，DB缓存: ${last?.price ?? "无"} @ ${last?.time ?? "-"}');
  yield last;
  while (true) {
    try {
      // 降级链：getGoldPrice(ICBC-JCJ) → 东方财富 Au9999 参考价 → 新浪。
      final fresh = await api.fetchIcbcPriceWithFallback();
      if (fresh != null) {
        debugPrint('[金脉行情] 工商积存金 入库: ${fresh.source} ${fresh.price} @${fresh.time}');
        await dao.insert(fresh);
        last = fresh;
        // 前台告警判定：仅判定 'icbc' 品种的价格提醒；
        // 各品种轮询只判定同品种提醒（含收益目标，按本品种持仓利润）。
        try {
          var assetValue = 0.0;
          var totalCost = 0.0;
          for (final h in await holdingDao.list()) {
            if (h.kind != 'icbc') continue;
            assetValue += fresh.price * h.amount;
            totalCost += h.totalCost;
          }
          await runAlertChecks(
              dao: alertDao,
              plugin: notifications,
              price: fresh.price,
              assetValue: assetValue,
              totalCost: totalCost,
              kind: 'icbc');
        } catch (_) {
          // 告警判定失败不影响行情轮询。
        }
      }
    } catch (_) {
      // 拉取失败保留缓存继续轮询。
    }
    yield last;
    final delay = last == null ? const Duration(seconds: 30) : interval;
    debugPrint('[金脉行情] 工商积存金 下次调度 ${delay.inSeconds}s'
        ' (${last == null ? "快速重试" : "正常间隔"})');
    nextRefresh.set(DateTime.now().add(delay), delay, retrying: last == null);
    await Future.delayed(delay);
  }
});
