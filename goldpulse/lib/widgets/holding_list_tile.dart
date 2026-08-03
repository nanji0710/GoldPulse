// lib/widgets/holding_list_tile.dart
// 持仓列表项：长按弹出编辑菜单（修改克重 / 加记生息 / 记一笔卖出 / 删除持仓）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/utils/formatters.dart';
import '../services/calculator.dart';

class HoldingListTile extends ConsumerWidget {
  final Holding holding;
  const HoldingListTile({super.key, required this.holding});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: AppTheme.card,
      child: ListTile(
        title: Text(holding.name),
        subtitle: Text('${fmtGrams(holding.amount)}g · 成本 ${fmtPrice(Calculator.avgCost(holding.totalCost, holding.amount))} 元/g',
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
        trailing: const Icon(Icons.chevron_right),
        onLongPress: () => _showActions(context, ref),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(holding.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${fmtGrams(holding.amount)}g'),
          ),
          const Divider(height: 1),
          ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改克重'),
              onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
              leading: const Icon(Icons.add_chart),
              title: const Text('加记生息'),
              onTap: () => Navigator.pop(ctx, 'interest')),
          ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('记一笔卖出'),
              onTap: () => Navigator.pop(ctx, 'sell')),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除持仓'),
              onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'edit':
        await _editAmount(context, ref);
      case 'interest':
        await _addInterest(context, ref);
      case 'sell':
        await _sell(context, ref);
      case 'delete':
        await _delete(context, ref);
    }
  }

  /// 修改克重：直接覆盖持仓克重（用于修正录入误差）。
  Future<void> _editAmount(BuildContext context, WidgetRef ref) async {
    final value = await _promptNumber(context, '修改克重',
        hint: '当前 ${fmtGrams(holding.amount)}g',
        initial: holding.amount.toString()); // 纯数字预填，避免千分位分隔符
    if (value == null || !context.mounted) return;
    await ref.read(holdingDaoProvider).updateAmount(holding.id, value);
    ref.invalidate(holdingsProvider);
  }

  /// 加记生息：type=interest，price=0，只增克重摊薄成本。
  Future<void> _addInterest(BuildContext context, WidgetRef ref) async {
    final value = await _promptNumber(context, '加记生息', hint: '克重（如 0.08）');
    if (value == null || !context.mounted) return;
    try {
      await ref.read(recordTradeProvider(TradeRecord(
        holdingId: holding.id,
        type: 'interest',
        amount: value,
        price: 0,
        fee: 0,
        time: DateTime.now().millisecondsSinceEpoch,
      )).future);
    } catch (e) {
      if (!context.mounted) return;
      _showSnack(context, '生息录入失败：$e');
    }
  }

  /// 记一笔卖出：type=sell，默认价取当前行情；手续费按 0.4% 计算。
  /// 超卖（克重 > 当前持仓）在对话框内联拦截，不产生交易记录。
  Future<void> _sell(BuildContext context, WidgetRef ref) async {
    final current = ref.read(priceProvider).value?.price;
    final result = await _promptSell(context,
        defaultPrice: current?.toString(),
        maxAmount: holding.amount);
    if (result == null || !context.mounted) return;
    try {
      await ref.read(recordTradeProvider(TradeRecord(
        holdingId: holding.id,
        type: 'sell',
        amount: result.amount,
        price: result.price,
        fee: Calculator.sellFee(result.amount, result.price),
        time: DateTime.now().millisecondsSinceEpoch,
      )).future);
    } catch (e) {
      if (!context.mounted) return;
      _showSnack(context, '卖出失败：$e');
    }
  }

  /// 删除持仓：连同其交易记录一并删除。
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除持仓'),
        content: Text('确定删除「${holding.name}」及其全部交易记录？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(holdingDaoProvider).delete(holding.id);
    ref.invalidate(holdingsProvider);
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 解析数字输入：容忍千分位分隔符与首尾空白（如 "1,000.50"）。
double? _parseNum(String s) => double.tryParse(s.replaceAll(',', '').trim());

/// 单数字输入对话框；返回 null 表示取消。
Future<double?> _promptNumber(BuildContext context, String title,
    {String hint = '', String? initial}) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final v = _parseNum(controller.text);
            if (v != null && v > 0) Navigator.pop(ctx, v);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 卖出对话框：克重 + 价格（默认当前行情价）。
/// [maxAmount] 当前持仓克重；超卖时内联报错且不关闭对话框。
Future<({double amount, double price})?> _promptSell(BuildContext context,
    {String? defaultPrice, required double maxAmount}) {
  final amountC = TextEditingController();
  final priceC = TextEditingController(text: defaultPrice);
  return showDialog<({double amount, double price})>(
    context: context,
    builder: (ctx) {
      String? errorText;
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          void revalidate() {
            final amount = _parseNum(amountC.text);
            setDialogState(() {
              errorText =
                  amount != null && amount > maxAmount ? '超过当前持仓 ${fmtGrams(maxAmount)}g' : null;
            });
          }

          return AlertDialog(
            title: const Text('记一笔卖出'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amountC,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '卖出克重',
                  hintText: '例如 50',
                  errorText: errorText,
                ),
                onChanged: (_) => revalidate(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceC,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: '卖出价格（元/g）'),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final amount = _parseNum(amountC.text);
                  final price = _parseNum(priceC.text);
                  if (amount != null &&
                      amount > 0 &&
                      amount <= maxAmount &&
                      price != null &&
                      price > 0) {
                    Navigator.pop(ctx, (amount: amount, price: price));
                  }
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    },
  );
}
