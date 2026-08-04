// lib/pages/alert_page.dart
// 提醒页：列表 + 新增表单（类型下拉 / 目标值）+ 开关切换。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:goldpulse/services/alert_service.dart';
import 'package:goldpulse/state/alert_provider.dart';
import 'package:goldpulse/widgets/empty_state.dart';

class AlertPage extends ConsumerWidget {
  const AlertPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider).value ?? [];
    return Scaffold(
      appBar: AppBar(
          title: const Text('提醒'),
          actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _showAddSheet(context, ref))]),
      body: Column(children: [
        // 顶部提示卡：后台轮询延迟说明（卡片化，替代整条色块）
        Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.card,
            border: Border.all(color: AppTheme.divider),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 16, color: AppTheme.textSecondary),
            SizedBox(width: 8),
            Expanded(
              child: Text('后台提醒存在 15 分钟级延迟，请保持应用在最近任务中',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ),
          ]),
        ),
        Expanded(
          child: alerts.isEmpty
              ? EmptyState(
                  icon: Icons.notifications_none,
                  title: '暂无提醒',
                  description: '黄金达到目标价时通知你',
                  actionLabel: '添加提醒',
                  onAction: () => _showAddSheet(context, ref),
                )
              : ListView.builder(itemCount: alerts.length, itemBuilder: (_, i) => _AlertTile(alert: alerts[i])),
        ),
      ]),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(context: context, builder: (_) => const _AddAlertSheet());
  }
}

class _AlertTile extends ConsumerWidget {
  final Alert alert;
  const _AlertTile({required this.alert});

  /// 类型 leading 图标：36×36 圆角盒 + 类型色 alpha 0.12 底。
  static Widget _typeIcon(String type) {
    final (icon, color) = switch (type) {
      'price_up' => (Icons.trending_up, AppTheme.gold),
      'price_down' => (Icons.trending_down, AppTheme.down),
      'profit_target' => (Icons.savings_outlined, AppTheme.down),
      _ => (Icons.notifications_outlined, AppTheme.gold),
    };
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  /// 删除确认：红色确认按钮，确认后走 deleteAlertProvider 并刷新列表。
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除提醒'),
        content: const Text('确定要删除这条提醒吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.up),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(deleteAlertProvider(alert.id).future);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> toggle(bool value) async {
      await ref.read(alertDaoProvider).toggle(alert.id, value);
      ref.invalidate(alertsProvider);
    }

    return Card(
      color: AppTheme.card,
      child: ListTile(
        leading: _typeIcon(alert.type),
        title: Text(AlertService.describe(alert)),
        // 副标题显示目标品种名（收益提醒不区分品种，不显示）。
        subtitle: alert.type == 'profit_target' ? null : Text(AlertService.kindLabel(alert.kind)),
        // 保留原 SwitchListTile 的点按整行切换开关的交互；trailing 增删删除入口。
        onTap: () => toggle(!alert.enable),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: alert.enable,
              onChanged: (v) => toggle(v),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: AppTheme.up,
              tooltip: '删除提醒',
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddAlertSheet extends ConsumerStatefulWidget {
  const _AddAlertSheet();
  @override
  ConsumerState<_AddAlertSheet> createState() => _AddAlertSheetState();
}

class _AddAlertSheetState extends ConsumerState<_AddAlertSheet> {
  static const _typeLabels = {
    'price_up': '价格上涨',
    'price_down': '价格下跌',
    'profit_target': '收益目标',
  };
  static const _kindLabels = {
    'au9999': 'Au9999',
    'accumulation': '浙商积存金',
    'icbc': '工商积存金',
  };
  String _type = 'price_up';
  String _kind = 'au9999';
  final _targetController = TextEditingController();
  String? _targetError;

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final target = double.tryParse(_targetController.text.trim());
    if (target == null || target <= 0) {
      setState(() => _targetError = '请输入有效的目标值');
      return;
    }
    final alert = Alert(type: _type, kind: _kind, target: target, enable: true);
    await ref.read(saveAlertProvider(alert).future);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 拖拽把手：36×4 圆条，居中，顶部 ~10px 间距
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 10),
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: '类型'),
            items: _typeLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          // 品种选择：所有类型（含收益目标）都可选择品种；
          // 收益目标按所选品种的持仓利润判定（见 runAlertChecks）。
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: '品种'),
            items: _kindLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _targetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              // profit_target 的目标是收益金额，标签文案澄清语义；数值仍为 target。
              labelText: _type == 'profit_target' ? '收益目标（元）' : '目标值',
              hintText: _type == 'profit_target' ? '例如 5000' : '例如 800',
              errorText: _targetError,
            ),
            onChanged: (_) {
              if (_targetError != null) setState(() => _targetError = null);
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.gold),
              onPressed: _save,
              child: const Text('保存'),
            ),
          ),
        ]),
      ),
    );
  }
}
