// lib/services/persistent_notification_service.dart
// 常驻通知栏：前台服务启停 + 后台 TaskHandler 周期拉行情并更新通知。
// TaskHandler 在独立后台 isolate：用 dio 拉行情（纯 Dart），持仓快照/配置经 sendDataToTask 传入缓存。
// 依赖 flutter_foreground_task 10.0.0（Task 1 已装）：
//   - init 为同步 void；sendDataToTask 为同步 void（不可 await）。
//   - 后台接收主 isolate 数据经 TaskHandler.onReceiveData（无 receiveDataFromTask）。
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'notification_metrics.dart';
import 'price_api.dart';

/// 默认自选指标：与资产页常用指标一致。
const _defaultMetrics = [
  'avgCost', 'floatingProfit', 'profitRate', 'todayProfit',
];

/// 服务端到 TaskHandler 的数据契约：JSON map（经 method channel 传输）。
class _TaskPayload {
  String kind = 'accumulation';
  List<String> selectedMetrics = _defaultMetrics;
  PositionSnapshot? snapshot;
}

/// 主 isolate：启动前台服务（通知栏初始化 + 周期回调）。
Future<void> startPersistentNotification({
  required String kind,
  required int intervalSeconds,
}) async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'persistent_notification',
      channelName: '常驻通知栏',
      channelDescription: '实时显示积存金行情与收益',
      channelImportance: NotificationChannelImportance.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(intervalSeconds * 1000),
    ),
  );
  await FlutterForegroundTask.startService(
    serviceId: 2001,
    notificationTitle: '金脉 · 行情与收益',
    notificationText: '正在启动…',
    callback: persistentNotificationCallback,
  );
  FlutterForegroundTask.sendDataToTask({
    'kind': kind,
    'selectedMetrics': _defaultMetrics,
    'snapshot': null,
  });
}

/// 主 isolate → TaskHandler：同步持仓快照与自选指标配置。
Future<void> syncPersistentNotificationData({
  required String kind,
  required List<String> selectedMetrics,
  required PositionSnapshot? snapshot,
}) async {
  FlutterForegroundTask.sendDataToTask({
    'kind': kind,
    'selectedMetrics': selectedMetrics,
    'snapshot': snapshot?.toJson(),
  });
}

/// 主 isolate：停止前台服务。
Future<void> stopPersistentNotification() async {
  await FlutterForegroundTask.stopService();
}

/// 后台 isolate 入口（顶层函数，供插件回调）。
@pragma('vm:entry-point')
void persistentNotificationCallback() {
  FlutterForegroundTask.setTaskHandler(_PersistentTaskHandler());
}

class _PersistentTaskHandler extends TaskHandler {
  final _TaskPayload _payload = _TaskPayload();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // v10：主 isolate 数据经 onReceiveData 到达，无需在此注册回调。
  }

  @override
  void onReceiveData(Object data) {
    final m = (data as Map).cast<String, dynamic>();
    _payload.kind = m['kind'] as String? ?? _payload.kind;
    _payload.selectedMetrics =
        (m['selectedMetrics'] as List?)?.cast<String>() ?? _payload.selectedMetrics;
    final snap = m['snapshot'];
    _payload.snapshot = snap == null
        ? null
        : PositionSnapshot.fromJson((snap as Map).cast<String, dynamic>());
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final snap = _payload.snapshot;
      if (snap == null) return; // 持仓快照未就绪，不更新
      final api = PriceApi(dio: Dio(BaseOptions(
          headers: {'User-Agent': 'goldpulse/1.0'},
          receiveTimeout: const Duration(seconds: 8))));
      final fresh = _payload.kind == 'minsheng'
          ? await api.fetchMinShengPriceWithFallback()
          : await api.fetchGoldPriceWithFallback(_kindCode(_payload.kind));
      if (fresh == null) return; // 行情拉取失败，保留上一条通知
      final metrics = computeNotificationMetrics(
          price: fresh.price, preClose: fresh.preClose, pos: snap);
      final text = buildNotificationText(
          metrics: metrics,
          selectedMetrics: _payload.selectedMetrics,
          kind: snap.kind);
      await FlutterForegroundTask.updateService(
        notificationTitle: '金脉 · ${_kindLabel(snap.kind)}',
        notificationText: text,
      );
    } catch (_) {
      // 后台刷新失败静默，保留上一条通知。
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationPressed() {}
}

/// 品种 → 行情代码（复用 suggestion_provider 的 switch）。
String _kindCode(String kind) => switch (kind) {
      'au9999' => 'SGE-Au(T+D)',
      'icbc' => 'ICBC-JCJ',
      'minsheng' => 'MSB-JCJ',
      _ => 'CZB-JCJ',
    };

/// 品种 → 展示名（通知标题/首行）。
String _kindLabel(String kind) => switch (kind) {
      'au9999' => 'Au9999',
      'icbc' => '工商积存金',
      'minsheng' => '民生积存金',
      _ => '浙商积存金',
    };

/// 拼通知文本：第一行「品种 涨跌额 现价」，下方自选指标「名 值」（每行一个）。
/// 纯函数，可单测。kind 缺省 'accumulation'（浙商积存金）。
String buildNotificationText({
  required Map<String, String> metrics,
  required List<String> selectedMetrics,
  String kind = 'accumulation',
}) {
  final buf = StringBuffer();
  buf.writeln(
      '${_kindLabel(kind)}  涨跌 ${metrics['change'] ?? '--'}    ${metrics['price'] ?? '--'} 元/g');
  for (final id in selectedMetrics) {
    final label = metricLabels[id] ?? id;
    final value = metrics[id] ?? '--';
    buf.writeln('$label  $value');
  }
  return buf.toString().trimRight();
}
