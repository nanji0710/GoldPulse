// lib/pages/alert_page.dart
// 提醒页：列表 + 新增表单（类型下拉 / 目标值）+ 开关切换。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:goldpulse/services/alert_service.dart';
import 'package:goldpulse/state/alert_provider.dart';

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
        // 顶部固定提示：后台轮询延迟说明
        Container(
          width: double.infinity,
          color: AppTheme.card,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Row(children: [
            Icon(Icons.hourglass_top, size: 16, color: AppTheme.textSecondary),
            SizedBox(width: 6),
            Expanded(
              child: Text('后台提醒存在 15 分钟级延迟，请保持应用在最近任务中',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ),
          ]),
        ),
        Expanded(
          child: alerts.isEmpty
              ? const Center(child: Text('暂无提醒，点击右上角 + 添加'))
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: AppTheme.card,
      child: SwitchListTile(
        title: Text(AlertService.describe(alert)),
        value: alert.enable,
        onChanged: (value) async {
          await ref.read(alertDaoProvider).toggle(alert.id, value);
          ref.invalidate(alertsProvider);
        },
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
  String _type = 'price_up';
  final _targetController = TextEditingController();

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final target = double.tryParse(_targetController.text);
    if (target == null || target <= 0) return;
    final alert = Alert(type: _type, target: target, enable: true);
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
          DropdownButton<String>(
            value: _type,
            isExpanded: true,
            items: _typeLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _targetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '目标值', hintText: '例如 800'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _save, child: const Text('保存')),
          ),
        ]),
      ),
    );
  }
}
