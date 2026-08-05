// lib/state/persistent_notification_provider.dart
// 常驻通知栏配置：开关/品种/频率/指标 读写 SharedPreferences。
// 服务启停由设置页驱动（见 setting_page.dart）：
//   - 开关 on  → startPersistentNotification + syncNotificationPosition（两步都要做，
//     规避 Task3 评审遗留的启动竞态：后台 isolate 的 onReceiveData 可能未就绪，首包丢失
//     会导致服务以错误品种运行）；
//   - 配置变更 → 写 prefs + 重启服务（若 enabled）+ 重新同步快照。
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_metrics.dart';
import '../services/persistent_notification_service.dart';
import 'holding_provider.dart';

/// 默认自选指标（与资产页常用指标一致）。
const defaultNotificationMetrics = [
  'avgCost', 'floatingProfit', 'profitRate', 'todayProfit',
];

/// 品种中文名（与 asset_provider._kindLabel 同口径；其为私有，此处内联映射不重复定义函数）。
const notificationKindLabels = {
  'accumulation': '浙商积存金',
  'icbc': '工商积存金',
  'minsheng': '民生积存金',
  'au9999': 'Au9999',
};

/// 品种固定展示顺序（与资产页一致）。
const notificationKinds = ['accumulation', 'icbc', 'minsheng', 'au9999'];

/// 刷新频率选项（秒）。
const notificationIntervalOptions = [5, 10, 30, 60];

/// 配置快照：SharedPreferences 已存值的运行时镜像。
class PersistentNotificationConfig {
  final bool enabled;
  final String kind;
  final int intervalSeconds;
  final List<String> metrics;
  const PersistentNotificationConfig({
    this.enabled = false,
    this.kind = 'accumulation',
    this.intervalSeconds = 10,
    this.metrics = defaultNotificationMetrics,
  });

  PersistentNotificationConfig copyWith({
    bool? enabled,
    String? kind,
    int? intervalSeconds,
    List<String>? metrics,
  }) =>
      PersistentNotificationConfig(
        enabled: enabled ?? this.enabled,
        kind: kind ?? this.kind,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
        metrics: metrics ?? this.metrics,
      );
}

const _kEnabled = 'notificationBarEnabled';
const _kKind = 'notificationBarKind';
const _kInterval = 'notificationBarIntervalSeconds';
const _kMetrics = 'notificationBarMetrics';

class PersistentNotificationConfigNotifier
    extends Notifier<PersistentNotificationConfig> {
  @override
  PersistentNotificationConfig build() => const PersistentNotificationConfig();

  /// 从 SharedPreferences 恢复已存配置（app 启动/设置页 initState 调用）。
  /// build() 为同步，无法直接 await getInstance，故返回默认值 + 显式恢复。
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? false;
    final kind = prefs.getString(_kKind) ?? 'accumulation';
    final interval = prefs.getInt(_kInterval) ?? 10;
    var metrics = defaultNotificationMetrics;
    final raw = prefs.getString(_kMetrics);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final list = decoded.whereType<String>().toList();
          if (list.isNotEmpty) metrics = list;
        }
      } catch (_) {
        // 损坏的指标数据回退默认。
      }
    }
    state = PersistentNotificationConfig(
        enabled: enabled, kind: kind, intervalSeconds: interval, metrics: metrics);
  }

  Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, v);
    state = state.copyWith(enabled: v);
  }

  Future<void> setKind(String kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKind, kind);
    state = state.copyWith(kind: kind);
  }

  Future<void> setIntervalSeconds(int s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kInterval, s);
    state = state.copyWith(intervalSeconds: s);
  }

  /// 切换指标：已选则移除；未选且未满 4 个则加入。
  /// 返回 false 表示被拒绝（8 选 4 已满），列表不变。
  Future<bool> toggleMetric(String id) async {
    final cur = state.metrics;
    final List<String> next;
    if (cur.contains(id)) {
      next = [...cur]..remove(id);
    } else if (cur.length >= 4) {
      return false;
    } else {
      next = [...cur, id];
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMetrics, jsonEncode(next));
    state = state.copyWith(metrics: next);
    return true;
  }
}

final persistentNotificationConfigProvider =
    NotifierProvider<PersistentNotificationConfigNotifier,
        PersistentNotificationConfig>(PersistentNotificationConfigNotifier.new);

/// 构造所选品种的持仓快照并同步给后台 isolate。
/// 必须在 startPersistentNotification 之后主动调用：后台 isolate 的 onReceiveData
/// 可能未就绪，首包丢失会导致服务以错误品种/默认指标运行（启动 → 同步两步都做）。
/// 口径与资产页 typeSummariesProvider 一致（克重求和、剩余成本求和、累计投入求和、
/// 卖出净得 = Σ(卖出克重×成交价 − 手续费)）；该品种无持仓 → 快照为 null（服务不更新）。
Future<void> syncNotificationPosition(WidgetRef ref) async {
  final cfg = ref.read(persistentNotificationConfigProvider);
  final holdings = await ref.read(holdingsProvider.future);
  final trades = await ref.read(tradeDaoProvider).all();
  final hs = holdings.where((h) => h.kind == cfg.kind).toList();
  PositionSnapshot? snapshot;
  if (hs.isNotEmpty) {
    final ids = hs.map((h) => h.id).toSet();
    final sells =
        trades.where((t) => ids.contains(t.holdingId) && t.type == 'sell');
    snapshot = PositionSnapshot(
      kind: cfg.kind,
      grams: hs.fold(0.0, (s, h) => s + h.amount),
      totalCost: hs.fold(0.0, (s, h) => s + h.totalCost),
      boughtCost: hs.fold(0.0, (s, h) => s + h.boughtCost),
      soldNet: sells.fold(0.0, (sum, t) => sum + t.amount * t.price - t.fee),
    );
  }
  await syncPersistentNotificationData(
    kind: cfg.kind,
    selectedMetrics: cfg.metrics,
    snapshot: snapshot,
  );
}
