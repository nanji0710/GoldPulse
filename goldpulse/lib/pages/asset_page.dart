// lib/pages/asset_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/state/asset_provider.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/utils/formatters.dart';
import 'package:goldpulse/widgets/empty_state.dart';
import 'package:goldpulse/widgets/holding_list_tile.dart';
import 'holding_detail_page.dart';

class AssetPage extends ConsumerWidget {
  const AssetPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(holdingsProvider).value ?? [];
    // 全部持仓汇总：无持仓时 totalAssetSummaryProvider 为 null（走空态）。
    final total = ref.watch(totalAssetSummaryProvider).value;
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
          ? EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: '还没有持仓记录',
              description: '点击下方按钮添加你的第一笔黄金持仓，立即查看三口径收益',
              actionLabel: '添加第一笔持仓',
              onAction: () => _showAddHoldingSheet(context, ref),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              children: [
                if (total != null) ...[
                  _SummaryCard(total: total),
                  const SizedBox(height: 12),
                ],
                for (final h in holdings)
                  HoldingListTile(
                    holding: h,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HoldingDetailPage(holdingId: h.id),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  void _showAddHoldingSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddHoldingSheet(ref: ref),
    );
  }
}

/// 持仓汇总卡：标题 + 品种数 pill + 三口径收益等宽三列（红涨绿跌）。
/// 紧凑布局，整体高度 ~85px，置于持仓列表顶部。
class _SummaryCard extends StatelessWidget {
  final TypeAssetSummary total;
  const _SummaryCard({required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：持仓汇总 + 品种数 pill
          Row(
            children: [
              Expanded(
                child: Text(
                  '持仓汇总',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${total.holdingCount} 个品种',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 三口径等宽三列：持仓收益 / 今日盈亏 / 累计收益
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: '持仓收益',
                  value: total.floatingProfit,
                ),
              ),
              Expanded(
                child: _SummaryMetric(label: '今日盈亏', value: total.todayProfit),
              ),
              Expanded(
                child: _SummaryMetric(
                  label: '累计收益',
                  value: total.cumulativeProfit,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 汇总三列指标：小标签 + 带符号金额（红涨绿跌，tabular 数字）。
class _SummaryMetric extends StatelessWidget {
  final String label;
  final double value;
  const _SummaryMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final color = value >= 0 ? AppTheme.up : AppTheme.down;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text(
          '${arrow(value)} ${fmtAmount(value.abs())} 元',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
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
      boughtCost: amount * cost, // 初始买入即累计投入
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      await widget.ref.read(addHoldingProvider(holding).future);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Text('添加资产', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：浙商积存金',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: '类型'),
              items: const [
                DropdownMenuItem(value: 'accumulation', child: Text('浙商积存金')),
                DropdownMenuItem(value: 'icbc', child: Text('工商积存金')),
                DropdownMenuItem(value: 'minsheng', child: Text('民生积存金')),
                DropdownMenuItem(value: 'au9999', child: Text('Au9999')),
              ],
              onChanged: (v) => setState(() => _kind = v ?? 'accumulation'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
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
