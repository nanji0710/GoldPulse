// lib/state/alert_provider.dart
// 价格提醒全局状态：列表 FutureProvider + 通知插件 + 保存/轮询判定。
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/alert_dao.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';

final alertDaoProvider = Provider((ref) => AlertDao());

final alertsProvider = FutureProvider<List<Alert>>((ref) => ref.watch(alertDaoProvider).list());

final notificationsPluginProvider = Provider((ref) => FlutterLocalNotificationsPlugin());

final saveAlertProvider = FutureProvider.family<void, Alert>((ref, alert) async {
  await ref.read(alertDaoProvider).insert(alert);
  ref.invalidate(alertsProvider);
});

/// 删除提醒：删除后 invalidate 列表，页面立即刷新。
final deleteAlertProvider = FutureProvider.family<void, int>((ref, id) async {
  await ref.read(alertDaoProvider).delete(id);
  ref.invalidate(alertsProvider);
});

/// 轮询判定：由行情刷新/WorkManager 触发。
final checkAlertsProvider = FutureProvider.family<void, ({double price, double assetValue, double totalCost})>(
    (ref, ctx) => runAlertChecks(
        dao: ref.read(alertDaoProvider),
        plugin: ref.read(notificationsPluginProvider),
        price: ctx.price,
        assetValue: ctx.assetValue,
        totalCost: ctx.totalCost));

/// 告警判定核心逻辑：遍历启用提醒，命中即通知并 recordTrigger。
/// 抽成独立函数以便行情轮询在 async* 长驻循环中直接调用——
/// 长驻循环内不能 read Provider ref（流因依赖解析而重建后，残留协程会崩在已销毁元素上）。
Future<void> runAlertChecks({
  required AlertDao dao,
  required FlutterLocalNotificationsPlugin plugin,
  required double price,
  required double assetValue,
  required double totalCost,
}) async {
  for (final a in await dao.list()) {
    if (AlertService.matches(a, price: price, assetValue: assetValue, totalCost: totalCost)) {
      await AlertService.showNotification(plugin, '金脉提醒', AlertService.describe(a));
      await dao.recordTrigger(a.id);
    }
  }
}
