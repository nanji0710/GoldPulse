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

  static double sellNetProfit(double sellAmount, double sellPrice, double avgCostPrice) {
    final gross = sellAmount * (sellPrice - avgCostPrice);
    return gross - sellFee(sellAmount, sellPrice);
  }

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
        return (amount: amount + record.amount, totalCost: totalCost + record.amount * record.price);
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
}
