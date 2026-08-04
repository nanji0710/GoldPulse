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
import 'number_dialogs.dart';

class HoldingListTile extends ConsumerWidget {
  final Holding holding;

  /// 点击进入持仓详情（Task 4 接线 HoldingDetailPage；本任务仅加参数不接线）。
  final VoidCallback? onTap;
  const HoldingListTile({super.key, required this.holding, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 按持仓类型选对应行情流：工商积存金 → icbc、浙商积存金 → accumulation、
    // 其余（Au9999）→ Au9999 主行情。valueOrNull 保证 AsyncError 安全回落 null。
    final price = ref
        .watch(
          holding.kind == 'icbc'
              ? icbcPriceProvider
              : holding.kind == 'accumulation'
              ? accumulationPriceProvider
              : priceProvider,
        )
        .valueOrNull;
    final sells =
        ref.watch(holdingTradesProvider(holding.id)).valueOrNull ??
        const <TradeRecord>[];
    final avgCost = Calculator.avgCost(holding.totalCost, holding.amount);

    // 三口径收益：行情缺失（null）时全部显示 '--'，不配色。
    double? floating;
    double? today;
    double? cumulative;
    if (price != null) {
      floating = Calculator.floatingProfit(
        price.price,
        holding.amount,
        holding.totalCost,
      );
      today = Calculator.todayProfit(
        price.price,
        price.preClose,
        holding.amount,
      );
      cumulative = Calculator.cumulativeProfit(
        currentPrice: price.price,
        amount: holding.amount,
        boughtCost: holding.boughtCost,
        sellTrades: sells,
      );
    }

    return Card(
      color: AppTheme.card,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showActions(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行：名称 + 浮动盈亏胶囊 + 箭头
              Row(
                children: [
                  Expanded(
                    child: Text(
                      holding.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ProfitPill(value: floating),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${fmtGrams(holding.amount)}g · 成本 ${fmtPrice(avgCost)} 元/g',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              const Divider(color: AppTheme.divider, height: 1),
              // 底部三口径：持仓收益 / 今日盈亏 / 累计收益（等宽三列）
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _MetricColumn(label: '持仓收益', value: floating),
                    ),
                    Expanded(
                      child: _MetricColumn(label: '今日盈亏', value: today),
                    ),
                    Expanded(
                      child: _MetricColumn(label: '累计收益', value: cumulative),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        // 追加买入后动作项增多，超过底部弹层最大高度（屏幕 9/16），
        // 包一层滚动避免 RenderFlex 溢出。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(
                  holding.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${fmtGrams(holding.amount)}g'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('修改克重'),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: const Text('追加买入'),
                onTap: () => Navigator.pop(ctx, 'buy'),
              ),
              ListTile(
                leading: const Icon(Icons.add_chart),
                title: const Text('加记生息'),
                onTap: () => Navigator.pop(ctx, 'interest'),
              ),
              ListTile(
                leading: const Icon(Icons.sell_outlined),
                title: const Text('记一笔卖出'),
                onTap: () => Navigator.pop(ctx, 'sell'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除持仓'),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'edit':
        await _editAmount(context, ref);
      case 'buy':
        await _buy(context, ref);
      case 'interest':
        await _addInterest(context, ref);
      case 'sell':
        await _sell(context, ref);
      case 'delete':
        await _delete(context, ref);
    }
  }

  /// 追加买入：type=buy，克重 + 成交价（默认取该持仓品种现价），手续费 0。
  Future<void> _buy(BuildContext context, WidgetRef ref) async {
    final provider = holding.kind == 'icbc'
        ? icbcPriceProvider
        : holding.kind == 'accumulation'
        ? accumulationPriceProvider
        : priceProvider;
    final current = ref.read(provider).value?.price;
    final amount = await promptNumber(context, '追加买入', hint: '克重（如 50）');
    if (amount == null || !context.mounted) return;
    final price = await promptNumber(
      context,
      '买入价格',
      hint: '成交价（元/g）',
      initial: current?.toString(),
    );
    if (price == null || !context.mounted) return;
    try {
      await ref.read(
        recordTradeProvider(
          TradeRecord(
            holdingId: holding.id,
            type: 'buy',
            amount: amount,
            price: price,
            fee: 0,
            time: DateTime.now().millisecondsSinceEpoch,
          ),
        ).future,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showSnack(context, '追加买入失败：$e');
    }
  }

  /// 修改克重：直接覆盖持仓克重（用于修正录入误差）。
  Future<void> _editAmount(BuildContext context, WidgetRef ref) async {
    final value = await promptNumber(
      context,
      '修改克重',
      hint: '当前 ${fmtGrams(holding.amount)}g',
      initial: holding.amount.toString(),
    ); // 纯数字预填，避免千分位分隔符
    if (value == null || !context.mounted) return;
    await ref.read(holdingDaoProvider).updateAmount(holding.id, value);
    ref.invalidate(holdingsProvider);
  }

  /// 加记生息：type=interest，price=0，只增克重摊薄成本。
  Future<void> _addInterest(BuildContext context, WidgetRef ref) async {
    final value = await promptNumber(context, '加记生息', hint: '克重（如 0.08）');
    if (value == null || !context.mounted) return;
    try {
      await ref.read(
        recordTradeProvider(
          TradeRecord(
            holdingId: holding.id,
            type: 'interest',
            amount: value,
            price: 0,
            fee: 0,
            time: DateTime.now().millisecondsSinceEpoch,
          ),
        ).future,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showSnack(context, '生息录入失败：$e');
    }
  }

  /// 记一笔卖出：type=sell，默认价取当前行情；手续费按 0.4% 计算。
  /// 超卖（克重 > 当前持仓）在对话框内联拦截，不产生交易记录。
  Future<void> _sell(BuildContext context, WidgetRef ref) async {
    final current = ref.read(priceProvider).value?.price;
    final result = await promptSell(
      context,
      defaultPrice: current?.toString(),
      maxAmount: holding.amount,
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(
        recordTradeProvider(
          TradeRecord(
            holdingId: holding.id,
            type: 'sell',
            amount: result.amount,
            price: result.price,
            fee: Calculator.sellFee(result.amount, result.price),
            time: DateTime.now().millisecondsSinceEpoch,
          ),
        ).future,
      );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(holdingDaoProvider).delete(holding.id);
    ref.invalidate(holdingsProvider);
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 浮动盈亏胶囊：▲/▼ + 带符号金额（红涨绿跌；行情缺失显示 '--'）。
class _ProfitPill extends StatelessWidget {
  final double? value;
  const _ProfitPill({this.value});
  @override
  Widget build(BuildContext context) {
    final v = value;
    final color = v == null ? AppTheme.textSecondary : arrowColor(v);
    final text = v == null
        ? '--'
        : '${arrow(v)} ${v >= 0 ? '+' : '-'}${fmtAmount(v.abs())}';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 132),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// 三口径收益列：标签 + 带符号金额（红涨绿跌；行情缺失显示 '--'）。
class _MetricColumn extends StatelessWidget {
  final String label;
  final double? value;
  const _MetricColumn({required this.label, this.value});
  @override
  Widget build(BuildContext context) {
    final v = value;
    final color = v == null ? AppTheme.textSecondary : arrowColor(v);
    final text = v == null
        ? '--'
        : '${v >= 0 ? '+' : '-'}${fmtAmount(v.abs())} 元';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text(
          text,
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
