// lib/state/asset_provider.dart
// 资产汇总：AssetSummary 聚合模型 + 汇总 FutureProvider。
// 收益三口径：
//   持仓收益 = 现价×克重 − 总成本（未实现浮动）
//   今日盈亏 = (现价 − 昨收) × 克重
//   累计收益 = Σ卖出净得 + 持仓市值 − 总成本（已实现 + 未实现）
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/holding.dart';
import '../models/trade_record.dart';
import '../services/calculator.dart';
import 'holding_provider.dart';
import 'price_provider.dart';

class AssetSummary {
  final Holding holding;
  final double currentPrice;
  final double preClose; // 昨收（今日盈亏基准）
  final double currentValue;
  final double floatingProfit; // 持仓收益
  final double todayProfit;    // 今日盈亏
  final double cumulativeProfit; // 累计收益
  final double profitRate;
  final double avgCost;
  const AssetSummary({
    required this.holding,
    required this.currentPrice,
    required this.preClose,
    required this.currentValue,
    required this.floatingProfit,
    required this.todayProfit,
    required this.cumulativeProfit,
    required this.profitRate,
    required this.avgCost,
  });

  factory AssetSummary.compute({
    required double currentPrice,
    required double preClose,
    required double amount,
    required double totalCost,
    double? boughtCost,
    Holding? holding,
    Iterable<TradeRecord> sellTrades = const [],
    Iterable<TradeRecord> tradesToday = const [],
  }) {
    // 累计投入：未显式给出时回退为总成本（无卖出场景两者相等，保持既有口径）。
    final bc = boughtCost ?? totalCost;
    final value = Calculator.currentValue(currentPrice, amount);
    final profit = Calculator.floatingProfit(currentPrice, amount, totalCost);
    return AssetSummary(
      holding: holding ?? Holding(name: '', kind: '', amount: amount, totalCost: totalCost, createdAt: 0),
      currentPrice: currentPrice,
      preClose: preClose,
      currentValue: value,
      floatingProfit: profit,
      // 精确今日盈亏：今日买入按买入价、卖出按卖出价，隔夜按昨收。
      todayProfit: Calculator.todayProfitPrecise(
          price: currentPrice, preClose: preClose, amountNow: amount,
          tradesToday: tradesToday),
      cumulativeProfit: Calculator.cumulativeProfit(
          currentPrice: currentPrice, amount: amount, boughtCost: bc, sellTrades: sellTrades),
      profitRate: Calculator.profitRate(profit, totalCost),
      avgCost: Calculator.avgCost(totalCost, amount),
    );
  }
}

/// 按品种聚合的持仓收益汇总。
/// kind: 'accumulation'(浙商) | 'icbc'(工商) | 'minsheng'(民生) | 'au9999'；label 为中文品种名。
class TypeAssetSummary {
  final String kind;
  final String label;
  final double totalGrams;
  final double totalCost;
  final double avgCost;
  final double? currentPrice; // 无行情时为 null
  final double? preClose;
  final double floatingProfit;   // 持仓收益
  final double todayProfit;      // 今日盈亏
  final double cumulativeProfit; // 累计收益
  final int holdingCount;
  const TypeAssetSummary({
    required this.kind, required this.label,
    required this.totalGrams, required this.totalCost, required this.avgCost,
    this.currentPrice, this.preClose,
    required this.floatingProfit, required this.todayProfit, required this.cumulativeProfit,
    required this.holdingCount,
  });
}

String _kindLabel(String kind) => switch (kind) {
      'accumulation' => '浙商积存金',
      'icbc' => '工商积存金',
      'minsheng' => '民生积存金',
      _ => 'Au9999',
    };

/// 按品种聚合全部持仓的收益汇总（同品种多笔合并：克重求和、均价=总成本÷总克重）。
/// 每个品种用其自身行情价计算三口径；无行情 → currentPrice=null（收益记 0，UI 显示 '--'）。
final typeSummariesProvider = FutureProvider<List<TypeAssetSummary>>((ref) async {
  final holdings = await ref.watch(holdingsProvider.future);
  if (holdings.isEmpty) return const [];
  final trades = await ref.read(tradeDaoProvider).all();
  // 固定品种顺序：浙商 → 工商 → 民生 → Au9999
  const order = ['accumulation', 'icbc', 'minsheng', 'au9999'];
  final byKind = <String, List<Holding>>{};
  for (final h in holdings) {
    byKind.putIfAbsent(h.kind, () => []).add(h);
  }
  final results = <TypeAssetSummary>[];
  for (final kind in order) {
    final hs = byKind[kind];
    if (hs == null || hs.isEmpty) continue;
    final totalGrams = hs.fold(0.0, (s, h) => s + h.amount);
    final totalCost = hs.fold(0.0, (s, h) => s + h.totalCost);
    // 累计投入 = Σ 各持仓 boughtCost（只随买入增加），用于累计收益口径；
    // 持仓收益/均价仍基于 Σ totalCost（卖出扣成本后的剩余成本）。
    final boughtCost = hs.fold(0.0, (s, h) => s + h.boughtCost);
    final ids = hs.map((h) => h.id).toSet();
    final sells = trades.where((t) => ids.contains(t.holdingId) && t.type == 'sell');
    final price = kind == 'icbc'
        ? ref.watch(icbcPriceProvider).valueOrNull
        : kind == 'accumulation'
            ? ref.watch(accumulationPriceProvider).valueOrNull
            : kind == 'minsheng'
                ? ref.watch(minshengPriceProvider).valueOrNull
                : ref.watch(priceProvider).valueOrNull;
    // 精确今日盈亏：隔夜持仓按昨收、今日买入按买入价、今日卖出按卖出价。
    final todayStart = DateTime(DateTime.now().year, DateTime.now().month,
            DateTime.now().day)
        .millisecondsSinceEpoch;
    final tradesToday =
        trades.where((t) => ids.contains(t.holdingId) && t.time >= todayStart);
    results.add(TypeAssetSummary(
      kind: kind,
      label: _kindLabel(kind),
      totalGrams: totalGrams,
      totalCost: totalCost,
      avgCost: Calculator.avgCost(totalCost, totalGrams),
      currentPrice: price?.price,
      preClose: price?.preClose,
      floatingProfit: price == null
          ? 0
          : Calculator.floatingProfit(price.price, totalGrams, totalCost),
      todayProfit: price == null
          ? 0
          : Calculator.todayProfitPrecise(
              price: price.price, preClose: price.preClose,
              amountNow: totalGrams, tradesToday: tradesToday),
      cumulativeProfit: price == null
          ? 0
          : Calculator.cumulativeProfit(
              currentPrice: price.price, amount: totalGrams,
              boughtCost: boughtCost, sellTrades: sells),
      holdingCount: hs.length,
    ));
  }
  return results;
});

/// 全部持仓合计（跨品种线性相加）。
final totalAssetSummaryProvider = FutureProvider<TypeAssetSummary?>((ref) async {
  final list = await ref.watch(typeSummariesProvider.future);
  if (list.isEmpty) return null;
  final grams = list.fold(0.0, (s, t) => s + t.totalGrams);
  final cost = list.fold(0.0, (s, t) => s + t.totalCost);
  return TypeAssetSummary(
    kind: 'all',
    label: '全部持仓',
    totalGrams: grams,
    totalCost: cost,
    avgCost: Calculator.avgCost(cost, grams),
    currentPrice: null,
    preClose: null,
    floatingProfit: list.fold(0.0, (s, t) => s + t.floatingProfit),
    todayProfit: list.fold(0.0, (s, t) => s + t.todayProfit),
    cumulativeProfit: list.fold(0.0, (s, t) => s + t.cumulativeProfit),
    holdingCount: list.fold(0, (s, t) => s + t.holdingCount),
  );
});
