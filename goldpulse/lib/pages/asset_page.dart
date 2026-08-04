// lib/pages/asset_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/widgets/holding_list_tile.dart';

class AssetPage extends ConsumerWidget {
  const AssetPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(holdingsProvider).value ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('资产'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加资产',
            onPressed: () => _showAddHoldingSheet(context, ref),
          ),
        ],
      ),
      body: holdings.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 56, color: AppTheme.textSecondary),
                  const SizedBox(height: 12),
                  const Text('还没有持仓记录'),
                  const SizedBox(height: 4),
                  Text('点击右上角 + 添加你的第一笔黄金持仓',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            )
          : ListView.builder(
              itemCount: holdings.length,
              itemBuilder: (_, i) => HoldingListTile(holding: holdings[i]),
            ),
    );
  }

  void _showAddHoldingSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddHoldingSheet(ref: ref),
    );
  }
}

/// 添加资产表单：名称 + 类型 + 克重 + 买入单价（总成本 = 克重 × 单价）。
class _AddHoldingSheet extends StatefulWidget {
  final WidgetRef ref;
  const _AddHoldingSheet({required this.ref});
  @override
  State<_AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends State<_AddHoldingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController(text: '浙商积存金');
  final _amountCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  String _kind = 'accumulation';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final amount = double.parse(_amountCtrl.text.trim());
    final cost = double.parse(_costCtrl.text.trim());
    final holding = Holding(
      name: _nameCtrl.text.trim().isEmpty ? '黄金持仓' : _nameCtrl.text.trim(),
      kind: _kind,
      amount: amount,
      totalCost: amount * cost,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await widget.ref.read(addHoldingProvider(holding).future);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('添加资产', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: '名称', hintText: '如：浙商积存金'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: '类型'),
              items: const [
                DropdownMenuItem(value: 'accumulation', child: Text('积存金')),
                DropdownMenuItem(value: 'au9999', child: Text('Au9999')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'accumulation'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: '克重 (g)'),
              validator: (v) {
                final d = double.tryParse(v?.trim() ?? '');
                if (d == null || d <= 0) return '请输入有效的克重';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _costCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: '买入单价 (元/g)'),
              validator: (v) {
                final d = double.tryParse(v?.trim() ?? '');
                if (d == null || d <= 0) return '请输入有效的单价';
                return null;
              },
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.gold),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
