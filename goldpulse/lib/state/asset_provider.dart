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
    Holding? holding,
    Iterable<TradeRecord> sellTrades = const [],
  }) {
    final value = Calculator.currentValue(currentPrice, amount);
    final profit = Calculator.floatingProfit(currentPrice, amount, totalCost);
    return AssetSummary(
      holding: holding ?? Holding(name: '', kind: '', amount: amount, totalCost: totalCost, createdAt: 0),
      currentPrice: currentPrice,
      preClose: preClose,
      currentValue: value,
      floatingProfit: profit,
      todayProfit: Calculator.todayProfit(currentPrice, preClose, amount),
      cumulativeProfit: Calculator.cumulativeProfit(
          currentPrice: currentPrice, amount: amount, totalCost: totalCost, sellTrades: sellTrades),
      profitRate: Calculator.profitRate(profit, totalCost),
      avgCost: Calculator.avgCost(totalCost, amount),
    );
  }
}

final assetSummaryProvider = FutureProvider<AssetSummary?>((ref) async {
  final holdings = await ref.watch(holdingsProvider.future);
  if (holdings.isEmpty) return null;
  final h = holdings.first; // MVP：单持仓；多持仓为 V2
  // 按持仓类型选对应行情：积存金 → 浙商积存金价（银行价与 Au9999 有价差）；
  // Au9999 持仓 → Au9999 价。价格更新时重新计算汇总（同时启动对应价格轮询）。
  final price = h.kind == 'accumulation'
      ? ref.watch(accumulationPriceProvider).value
      : ref.watch(priceProvider).value;
  if (price == null) return null; // 无行情时不展示汇总
  final trades = await ref.read(tradeDaoProvider).all();
  final sells = trades.where((t) => t.holdingId == h.id && t.type == 'sell');
  return AssetSummary.compute(
      currentPrice: price.price,
      preClose: price.preClose,
      amount: h.amount,
      totalCost: h.totalCost,
      holding: h,
      sellTrades: sells);
});
