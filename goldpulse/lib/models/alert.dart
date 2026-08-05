// lib/models/alert.dart
class Alert {
  final int id;
  final String type;     // 'price_up' | 'price_down' | 'profit_target'
  final String kind;     // 目标品种 'au9999' | 'accumulation' | 'icbc' | 'minsheng'（profit_target 不区分品种）
  final double target;   // 目标价（元/g）或目标金额（元）
  final bool enable;
  final int triggerCount;
  final int lastTriggered;
  const Alert({
    this.id = 0,
    required this.type,
    this.kind = 'au9999',
    required this.target,
    required this.enable,
    this.triggerCount = 0,
    this.lastTriggered = 0,
  });

  Map<String, Object?> toMap() => {
        'id': id, 'type': type, 'kind': kind, 'target': target, 'enable': enable ? 1 : 0,
        'trigger_count': triggerCount, 'last_triggered': lastTriggered,
      };
  factory Alert.fromMap(Map<String, Object?> m) => Alert(
        id: m['id'] as int? ?? 0,
        type: m['type'] as String,
        kind: m['kind'] as String? ?? 'au9999',
        target: (m['target'] as num).toDouble(),
        enable: (m['enable'] as int) == 1,
        triggerCount: m['trigger_count'] as int? ?? 0,
        lastTriggered: m['last_triggered'] as int? ?? 0,
      );
}
