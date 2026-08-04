// lib/pages/holding_detail_page.dart
// 持仓详情页：单笔持仓 三口径收益（持仓收益大字 + 今日/累计迷你卡）+ 现价/涨跌胶囊
// + 操作行（追加买入 / 记卖出 / 加记生息）+ 交易流水（类型标签 + 克重×价格 + 手续费 + 时间，
// 每条可删除并回滚持仓状态）。行情缺失时收益统一显示 '--'。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/utils/formatters.dart';
import 'package:goldpulse/widgets/empty_state.dart';
import 'package:goldpulse/widgets/number_dialogs.dart';
import '../services/calculator.dart';

/// 按持仓类型选对应行情流（与资产页/持仓列表口径一致）：
/// 工商积存金 → icbc、浙商积存金 → accumulation、其余（Au9999）→ Au9999 主行情。
StreamProvider<GoldPrice?> _kindPriceProvider(String kind) => kind == 'icbc'
    ? icbcPriceProvider
    : kind == 'accumulation'
    ? accumulationPriceProvider
    : priceProvider;

/// 品种中文名（与资产页 typeSummariesProvider 口径一致）。
String _kindLabel(String kind) => switch (kind) {
  'accumulation' => '浙商积存金',
  'icbc' => '工商积存金',
  _ => 'Au9999',
};

String _typeLabel(String type) => switch (type) {
  'buy' => '买入',
  'sell' => '卖出',
  'interest' => '生息',
  _ => type,
};

/// 交易时间：MM-dd HH:mm。
String _fmtTime(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

class HoldingDetailPage extends ConsumerStatefulWidget {
  final int holdingId;
  const HoldingDetailPage({super.key, required this.holdingId});
  @override
  ConsumerState<HoldingDetailPage> createState() => _HoldingDetailPageState();
}

class _HoldingDetailPageState extends ConsumerState<HoldingDetailPage> {
  /// 防并发写：操作/删除提交期间禁用按钮。
  bool _busy = false;

  Holding? _findHolding(List<Holding> holdings) {
    for (final h in holdings) {
      if (h.id == widget.holdingId) return h;
    }
    return null;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 记录一笔交易并刷新本页交易流水（recordTradeProvider 只 invalidate 持仓列表）。
  Future<void> _record(TradeRecord record) async {
    setState(() => _busy = true);
    try {
      await ref.read(recordTradeProvider(record).future);
      ref.invalidate(holdingTradesProvider(widget.holdingId));
    } catch (e) {
      if (mounted) _showSnack('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 追加买入：克重 + 成交价（默认该品种现价），手续费 0。
  Future<void> _buy(Holding holding) async {
    final current = ref.read(_kindPriceProvider(holding.kind)).value?.price;
    final amount = await promptNumber(context, '追加买入', hint: '克重（如 50）');
    if (amount == null || !mounted) return;
    final price = await promptNumber(
      context,
      '买入价格',
      hint: '成交价（元/g）',
      initial: current?.toString(),
    );
    if (price == null || !mounted) return;
    await _record(
      TradeRecord(
        holdingId: holding.id,
        type: 'buy',
        amount: amount,
        price: price,
        fee: 0,
        time: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 记一笔卖出：默认价取当前行情；手续费按 0.4% 计算；超卖在对话框内联拦截。
  Future<void> _sell(Holding holding) async {
    final current = ref.read(_kindPriceProvider(holding.kind)).value?.price;
    final result = await promptSell(
      context,
      defaultPrice: current?.toString(),
      maxAmount: holding.amount,
    );
    if (result == null || !mounted) return;
    await _record(
      TradeRecord(
        holdingId: holding.id,
        type: 'sell',
        amount: result.amount,
        price: result.price,
        fee: Calculator.sellFee(result.amount, result.price),
        time: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 加记生息：type=interest，price=0，只增克重摊薄成本。
  Future<void> _addInterest(Holding holding) async {
    final value = await promptNumber(context, '加记生息', hint: '克重（如 0.08）');
    if (value == null || !mounted) return;
    await _record(
      TradeRecord(
        holdingId: holding.id,
        type: 'interest',
        amount: value,
        price: 0,
        fee: 0,
        time: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// 删除一笔交易：确认后回滚持仓克重/成本；非法删除（负克重/负成本）被拒并提示。
  Future<void> _deleteTrade(TradeRecord trade) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除交易'),
        content: Text(
          '确定删除这笔${_typeLabel(trade.type)}记录'
          '（${fmtGrams(trade.amount)}g）？删除后持仓克重与成本将同步回滚。',
        ),
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
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(
        deleteTradeProvider((
          holdingId: widget.holdingId,
          tradeId: trade.id,
        )).future,
      );
    } catch (e) {
      if (mounted) _showSnack('删除失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final holdings = ref.watch(holdingsProvider).value ?? const <Holding>[];
    final holding = _findHolding(holdings);
    if (holding == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: '持仓不存在',
          description: '该持仓可能已被删除',
        ),
      );
    }
    final trades =
        ref.watch(holdingTradesProvider(widget.holdingId)).value ??
        const <TradeRecord>[];
    final price = ref.watch(_kindPriceProvider(holding.kind)).valueOrNull;
    final sells = trades.where((t) => t.type == 'sell').toList();
    final avgCost = Calculator.avgCost(holding.totalCost, holding.amount);
    // 三口径收益：行情缺失（null）时全部显示 '--'，不配色。
    final double? floating = price == null
        ? null
        : Calculator.floatingProfit(
            price.price,
            holding.amount,
            holding.totalCost,
          );
    final double? today = price == null
        ? null
        : Calculator.todayProfit(price.price, price.preClose, holding.amount);
    final double? cumulative = price == null
        ? null
        : Calculator.cumulativeProfit(
            currentPrice: price.price,
            amount: holding.amount,
            totalCost: holding.totalCost,
            sellTrades: sells,
          );

    return Scaffold(
      appBar: AppBar(title: Text(holding.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _PriceHeader(holding: holding, price: price),
          const SizedBox(height: 12),
          _ProfitSection(
            name: holding.name,
            kindLabel: _kindLabel(holding.kind),
            grams: holding.amount,
            avgCost: avgCost,
            floatingProfit: floating,
            todayProfit: today,
            cumulativeProfit: cumulative,
          ),
          const SizedBox(height: 12),
          _ActionRow(
            busy: _busy,
            onBuy: () => _buy(holding),
            onSell: () => _sell(holding),
            onInterest: () => _addInterest(holding),
          ),
          const SizedBox(height: 16),
          Text(
            '交易流水',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 8),
          if (trades.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '暂无交易记录',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            )
          else
            ...trades.map(
              (t) => _TradeTile(
                trade: t,
                busy: _busy,
                onDelete: () => _deleteTrade(t),
              ),
            ),
        ],
      ),
    );
  }
}

/// 现价头卡：持仓名 + 品种 + 现价大数字 + 涨跌胶囊（行情缺失显示 '--'/'行情未接入'）。
class _PriceHeader extends StatelessWidget {
  final Holding holding;
  final GoldPrice? price;
  const _PriceHeader({required this.holding, this.price});

  @override
  Widget build(BuildContext context) {
    final p = price;
    final up = p == null ? null : p.change >= 0;
    final color = up == null
        ? AppTheme.textSecondary
        : (up ? AppTheme.up : AppTheme.down);
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.goldSoft.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    holding.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _kindLabel(holding.kind),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  p == null ? '--' : fmtPrice(p.price),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: AppTheme.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '元/g',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                p == null
                    ? '行情未接入'
                    : '${arrow(p.change)} ${fmtAmount(p.change.abs())}  '
                          '(${p.percent >= 0 ? '+' : ''}${p.percent.toStringAsFixed(2)}%)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 三口径收益卡：持仓收益大字 + 今日/累计迷你卡（红涨绿跌；行情缺失 '--'）。
class _ProfitSection extends StatelessWidget {
  final String name;
  final String kindLabel;
  final double grams;
  final double avgCost;
  final double? floatingProfit;
  final double? todayProfit;
  final double? cumulativeProfit;
  const _ProfitSection({
    required this.name,
    required this.kindLabel,
    required this.grams,
    required this.avgCost,
    this.floatingProfit,
    this.todayProfit,
    this.cumulativeProfit,
  });

  @override
  Widget build(BuildContext context) {
    final v = floatingProfit;
    final color = v == null ? AppTheme.textSecondary : arrowColor(v);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    kindLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.gold,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${fmtGrams(grams)}g · 均价 ${fmtPrice(avgCost)} 元/g',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 15,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 14),
            const Divider(color: AppTheme.divider, height: 1),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '持仓收益',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 13),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    v == null ? '--' : '${arrow(v)} ${fmtAmount(v.abs())} 元',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 26,
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MiniMetric(label: '今日盈亏', value: todayProfit),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _MiniMetric(label: '累计收益', value: cumulativeProfit),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 今日盈亏 / 累计收益 迷你指标（行情缺失显示 '--'）。
class _MiniMetric extends StatelessWidget {
  final String label;
  final double? value;
  const _MiniMetric({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final v = value;
    final color = v == null ? AppTheme.textSecondary : arrowColor(v);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Text(
            v == null ? '--' : '${arrow(v)} ${fmtAmount(v.abs())} 元',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 15,
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 操作行：追加买入（主操作，金色）+ 记卖出 + 加记生息。
class _ActionRow extends StatelessWidget {
  final bool busy;
  final VoidCallback onBuy;
  final VoidCallback onSell;
  final VoidCallback onInterest;
  const _ActionRow({
    required this.busy,
    required this.onBuy,
    required this.onSell,
    required this.onInterest,
  });

  @override
  Widget build(BuildContext context) {
    final compact = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: compact.copyWith(
              backgroundColor: const WidgetStatePropertyAll(AppTheme.gold),
            ),
            onPressed: busy ? null : onBuy,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('追加买入'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: compact,
            onPressed: busy ? null : onSell,
            icon: const Icon(Icons.sell_outlined, size: 18),
            label: const Text('记卖出'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            style: compact,
            onPressed: busy ? null : onInterest,
            icon: const Icon(Icons.add_chart, size: 18),
            label: const Text('加记生息'),
          ),
        ),
      ],
    );
  }
}

/// 交易流水条目：类型标签 + 克重×价格 + 手续费 + 时间 + 删除按钮。
class _TradeTile extends StatelessWidget {
  final TradeRecord trade;
  final bool busy;
  final VoidCallback onDelete;
  const _TradeTile({
    required this.trade,
    required this.busy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _TypeTag(type: trade.type),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fmtGrams(trade.amount)}g × ${fmtPrice(trade.price)} 元/g',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '手续费 ${fmtAmount(trade.fee)} 元 · ${_fmtTime(trade.time)}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: busy ? null : onDelete,
              tooltip: '删除这笔交易',
              icon: const Icon(
                Icons.delete_outline,
                size: 20,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 交易类型标签（买入金 / 卖出红 / 生息灰）。
class _TypeTag extends StatelessWidget {
  final String type;
  const _TypeTag({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      'buy' => AppTheme.gold,
      'sell' => AppTheme.up,
      _ => AppTheme.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _typeLabel(type),
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
