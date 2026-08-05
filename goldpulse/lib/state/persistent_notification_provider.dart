// lib/state/persistent_notification_provider.dart
// 常驻通知栏配置：开关/品种/频率/指标 读写 SharedPreferences。
// 服务启停由设置页驱动（见 setting_page.dart）：
//   - 开关 on  → startPersistentNotification + syncNotificationPosition（两步都要做，
//     规避 Task3 评审遗留的启动竞态：后台 isolate 的 onReceiveData 可能未就绪，首包丢失
//     会导致服务以错误品种运行）；
//   - 配置变更 → 写 prefs + 重启服务（若 enabled）+ 重新同步快照。
// app 启动恢复也走同款两步（见 restorePersistentNotificationFromPrefs，main.dart 调用）。
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/holding_dao.dart';
import '../database/trade_dao.dart';
import '../models/holding.dart';
import '../models/trade_record.dart';
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

/// 从 prefs 原始值解析配置（含白名单校验：品种/频率/指标含非法值时回退默认，
/// 避免脏数据进入服务）。loadFromPrefs 与启动恢复共用，保证两份读取口径一致。
PersistentNotificationConfig _configFromPrefs(SharedPreferences prefs) {
  final enabled = prefs.getBool(_kEnabled) ?? false;
  var kind = prefs.getString(_kKind) ?? 'accumulation';
  if (!notificationKinds.contains(kind)) kind = 'accumulation';
  var interval = prefs.getInt(_kInterval) ?? 10;
  if (!notificationIntervalOptions.contains(interval)) interval = 10;
  var metrics = defaultNotificationMetrics;
  final raw = prefs.getString(_kMetrics);
  if (raw != null) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        // 只保留已知指标 id；空列表回退默认。take(4) 防御纵深：脏数据超 4 个时截断。
        final known = decoded
            .whereType<String>()
            .where(metricIds.contains)
            .take(4)
            .toList();
        if (known.isNotEmpty) metrics = known;
      }
    } catch (_) {
      // 损坏的指标数据回退默认。
    }
  }
  return PersistentNotificationConfig(
      enabled: enabled, kind: kind, intervalSeconds: interval, metrics: metrics);
}

class PersistentNotificationConfigNotifier
    extends Notifier<PersistentNotificationConfig> {
  @override
  PersistentNotificationConfig build() => const PersistentNotificationConfig();

  /// 从 SharedPreferences 恢复已存配置（app 启动/设置页 initState 调用）。
  /// build() 为同步，无法直接 await getInstance，故返回默认值 + 显式恢复。
  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    state = _configFromPrefs(prefs);
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

/// 从持仓与交易记录构造所选品种的持仓快照（纯函数，可单测）。
/// 口径与资产页 typeSummariesProvider 一致：克重求和、剩余成本求和、累计投入求和、
/// 卖出净得 = Σ(卖出克重×成交价 − 手续费)；该品种无持仓 → 返回 null（服务不更新，
/// 通知保持"无持仓"语义）。
PositionSnapshot? buildNotificationSnapshot({
  required String kind,
  required List<Holding> holdings,
  required List<TradeRecord> trades,
}) {
  final hs = holdings.where((h) => h.kind == kind).toList();
  if (hs.isEmpty) return null;
  final ids = hs.map((h) => h.id).toSet();
  final sells = trades.where((t) => ids.contains(t.holdingId) && t.type == 'sell');
  // 今日交易（time >= 当日 0 点），用于后台精确今日盈亏（今日买入按买入价）。
  final todayStart = DateTime(DateTime.now().year, DateTime.now().month,
          DateTime.now().day)
      .millisecondsSinceEpoch;
  final tradesToday = trades
      .where((t) => ids.contains(t.holdingId) && t.time >= todayStart)
      .toList();
  return PositionSnapshot(
    kind: kind,
    grams: hs.fold(0.0, (s, h) => s + h.amount),
    totalCost: hs.fold(0.0, (s, h) => s + h.totalCost),
    boughtCost: hs.fold(0.0, (s, h) => s + h.boughtCost),
    soldNet: sells.fold(0.0, (sum, t) => sum + t.amount * t.price - t.fee),
    todayTrades: tradesToday,
  );
}

/// 构造所选品种的持仓快照并同步给后台 isolate。
/// 必须在 startPersistentNotification 之后主动调用：后台 isolate 的 onReceiveData
/// 可能未就绪，首包丢失会导致服务以错误品种/默认指标运行（启动 → 同步两步都做）。
Future<void> syncNotificationPosition(WidgetRef ref) async {
  final cfg = ref.read(persistentNotificationConfigProvider);
  final holdings = await ref.read(holdingsProvider.future);
  final trades = await ref.read(tradeDaoProvider).all();
  await syncPersistentNotificationData(
    kind: cfg.kind,
    selectedMetrics: cfg.metrics,
    snapshot: buildNotificationSnapshot(
        kind: cfg.kind, holdings: holdings, trades: trades),
  );
}

/// 持仓变更后调用：**仅当常驻通知服务启用时**重读持仓构造快照并同步给后台 isolate。
/// 买入/卖出/生息/删除交易/新增持仓后由 holding_provider 调用，使通知随持仓实时变化
/// （服务启动时同步的快照会因持仓变化过期，若不重发通知停留在旧收益）。
/// 服务未启用直接返回；任何失败静默（不影响交易流程）。无 WidgetRef 依赖，
/// 配置经 prefs 读取（与启动恢复一致，setKind 等已写 prefs）。
Future<void> syncNotificationPositionIfEnabled() async {
  try {
    final cfg = await loadPersistentNotificationRestoreConfig();
    if (cfg == null) return; // 服务未启用，无需同步
    final holdings = await HoldingDao().list();
    final trades = await TradeDao().all();
    await syncPersistentNotificationData(
      kind: cfg.kind,
      selectedMetrics: cfg.metrics,
      snapshot: buildNotificationSnapshot(
          kind: cfg.kind, holdings: holdings, trades: trades),
    );
  } catch (_) {
    // 同步失败静默：通知保留旧快照，用户可重新开关服务。
  }
}

/// 启动恢复判定：读 prefs 得已存配置，未开启（enabled=false）返回 null（无需恢复）。
/// 与 loadFromPrefs 共用 _configFromPrefs 白名单校验，避免脏配置启动服务。
Future<PersistentNotificationConfig?> loadPersistentNotificationRestoreConfig() async {
  final prefs = await SharedPreferences.getInstance();
  final cfg = _configFromPrefs(prefs);
  return cfg.enabled ? cfg : null;
}

/// app 启动恢复常驻通知服务（main() 中 unawaited 调用，不阻塞启动）。
/// 若 prefs enabled=true：启动前台服务 → 主动同步一次配置+持仓快照
/// （与设置页开/重启同款两步走，规避后台 isolate onReceiveData 未就绪的首包竞态）；
/// 无持仓 → 快照为 null，通知保持"无持仓"。任何失败（prefs/数据库/插件未就绪）
/// 静默兜底：不影响启动，用户可在设置页重新开关服务。
/// [bootService] 为测试注入点（默认走 _bootPersistentNotification 真实实现）：
/// 插件 method channel 在测试环境不可用，注入 fake 可验证启动参数与失败兜底。
Future<void> restorePersistentNotificationFromPrefs({
  Future<void> Function(PersistentNotificationConfig cfg)? bootService,
}) async {
  try {
    final cfg = await loadPersistentNotificationRestoreConfig();
    if (cfg == null) return;
    await (bootService ?? _bootPersistentNotification)(cfg);
  } catch (_) {
    // 恢复失败静默：不得影响启动。
  }
}

/// 默认启动动作：启动前台服务 + 读持仓/交易构造快照 + 同步配置与快照。
Future<void> _bootPersistentNotification(PersistentNotificationConfig cfg) async {
  await startPersistentNotification(
      kind: cfg.kind, intervalSeconds: cfg.intervalSeconds);
  final holdings = await HoldingDao().list();
  final trades = await TradeDao().all();
  await syncPersistentNotificationData(
    kind: cfg.kind,
    selectedMetrics: cfg.metrics,
    snapshot: buildNotificationSnapshot(
        kind: cfg.kind, holdings: holdings, trades: trades),
  );
}
