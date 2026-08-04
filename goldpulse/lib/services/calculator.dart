// lib/services/calculator.dart
import '../models/trade_record.dart';

const double sellFeeRate = 0.004; // 浙商积存金卖出手续费 0.4%

class Calculator {
  Calculator._();

  static double currentValue(double price, double amount) => price * amount;

  static double floatingProfit(double price, double amount, double totalCost) =>
      price * amount - totalCost;

  static double profitRate(double profit, double totalCost) =>
      totalCost == 0 ? 0 : profit / totalCost;

  static double avgCost(double totalCost, double amount) =>
      amount == 0 ? 0 : totalCost / amount;

  static double sellFee(double sellAmount, double sellPrice) =>
      sellAmount * sellPrice * sellFeeRate;

  static double sellNetProfit(
    double sellAmount,
    double sellPrice,
    double avgCostPrice,
  ) {
    final gross = sellAmount * (sellPrice - avgCostPrice);
    return gross - sellFee(sellAmount, sellPrice);
  }

  /// 今日盈亏 = (现价 − 昨收) × 持仓克重。
  /// 昨收（preClose）由行情接口提供，作为当日基准价。
  static double todayProfit(double price, double preClose, double amount) =>
      (price - preClose) * amount;

  /// 历史卖出净收入 = Σ(卖出克重×卖出价 − 手续费)。
  static double sellNetProceeds(Iterable<TradeRecord> sellTrades) =>
      sellTrades.fold(0.0, (sum, t) => sum + t.amount * t.price - t.fee);

  /// 累计收益（已实现 + 未实现）：
  /// 累计 = Σ卖出净得 + 当前持仓市值 − 累计投入总成本。
  /// 该恒等式对任意买卖/生息序列成立：
  ///   无交易时退化为持仓收益；全部卖出后退化为纯已实现收益。
  static double cumulativeProfit({
    required double currentPrice,
    required double amount,
    required double totalCost,
    required Iterable<TradeRecord> sellTrades,
  }) => sellNetProceeds(sellTrades) + currentPrice * amount - totalCost;

  /// 应用一笔交易到持仓状态，返回新的克重与总成本。
  /// [amount] 当前克重，[totalCost] 累计买入总成本。
  /// 买入：克重、成本都增；生息：仅克重增（摊薄成本）；卖出：仅克重减、成本保留。
  static ({double amount, double totalCost}) applyTrade({
    required double amount,
    required double totalCost,
    required TradeRecord record,
  }) {
    switch (record.type) {
      case 'buy':
        return (
          amount: amount + record.amount,
          totalCost: totalCost + record.amount * record.price,
        );
      case 'interest':
        return (amount: amount + record.amount, totalCost: totalCost);
      case 'sell':
        if (record.amount > amount) {
          throw ArgumentError('卖出克重不能大于当前持仓');
        }
        return (amount: amount - record.amount, totalCost: totalCost);
      default:
        throw ArgumentError('未知交易类型: ${record.type}');
    }
  }

  /// 反向应用一笔交易（删除交易时回滚持仓状态）。
  /// buy → 减克重减成本；sell → 加克重；interest → 减克重。
  /// 回滚后克重/成本为负时返回 null（禁止删除）。
  static ({double amount, double totalCost})? reverseTrade({
    required double amount,
    required double totalCost,
    required TradeRecord record,
  }) {
    switch (record.type) {
      case 'buy':
        if (amount < record.amount ||
            totalCost < record.amount * record.price) {
          return null;
        }
        return (
          amount: amount - record.amount,
          totalCost: totalCost - record.amount * record.price,
        );
      case 'interest':
        if (amount < record.amount) {
          return null;
        }
        return (amount: amount - record.amount, totalCost: totalCost);
      case 'sell':
        return (amount: amount + record.amount, totalCost: totalCost);
      default:
        return (amount: amount, totalCost: totalCost);
    }
  }
}
