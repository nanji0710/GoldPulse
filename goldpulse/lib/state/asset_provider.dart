// lib/state/asset_provider.dart
// 资产汇总：AssetSummary 聚合模型 + 汇总 FutureProvider。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/holding.dart';
import '../services/calculator.dart';
import 'holding_provider.dart';
import 'price_provider.dart';

class AssetSummary {
  final Holding holding;
  final double currentPrice;
  final double currentValue;
  final double floatingProfit;
  final double profitRate;
  final double avgCost;
  const AssetSummary({
    required this.holding,
    required this.currentPrice,
    required this.currentValue,
    required this.floatingProfit,
    required this.profitRate,
    required this.avgCost,
  });

  factory AssetSummary.compute({
    required double currentPrice,
    required double amount,
    required double totalCost,
    Holding? holding,
  }) {
    final value = Calculator.currentValue(currentPrice, amount);
    final profit = Calculator.floatingProfit(currentPrice, amount, totalCost);
    return AssetSummary(
      holding: holding ?? Holding(name: '', kind: '', amount: amount, totalCost: totalCost, createdAt: 0),
      currentPrice: currentPrice,
      currentValue: value,
      floatingProfit: profit,
      profitRate: Calculator.profitRate(profit, totalCost),
      avgCost: Calculator.avgCost(totalCost, amount),
    );
  }
}

final assetSummaryProvider = FutureProvider<AssetSummary?>((ref) async {
  final holdings = await ref.watch(holdingsProvider.future);
  if (holdings.isEmpty) return null;
  final h = holdings.first; // MVP：单持仓；多持仓为 V2
  // watch 行情流：价格更新时重新计算汇总（同时启动价格轮询）
  final price = ref.watch(priceProvider).value;
  if (price == null) return null; // 无行情时不展示汇总
  return AssetSummary.compute(
      currentPrice: price.price, amount: h.amount, totalCost: h.totalCost, holding: h);
});
