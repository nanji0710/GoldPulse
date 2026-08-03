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

/// 轮询判定：由行情刷新/WorkManager 触发。
final checkAlertsProvider = FutureProvider.family<void, ({double price, double assetValue, double totalCost})>((ref, ctx) async {
  final dao = ref.read(alertDaoProvider);
  final plugin = ref.read(notificationsPluginProvider);
  for (final a in await dao.list()) {
    if (AlertService.matches(a, price: ctx.price, assetValue: ctx.assetValue, totalCost: ctx.totalCost)) {
      await AlertService.showNotification(plugin, '金脉提醒', AlertService.describe(a));
      await dao.recordTrigger(a.id);
    }
  }
});
