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
  /// 注意：这是简化口径，**不区分今日新买入的克重**——刚买入的克重会按昨收基准
  /// 虚增（买入前该克重不存在）。精确口径见 [todayProfitPrecise]。
  static double todayProfit(double price, double preClose, double amount) =>
      (price - preClose) * amount;

  /// 今日盈亏（精确口径）：
  /// - 隔夜持仓（昨日收盘时已有、且今日仍持有）按昨收基准：(现价 − 昨收) × 隔夜持有克重
  /// - 今日买入的克重按买入价基准：(现价 − 买入价) × 买入克重
  /// - 今日卖出的克重按卖出价基准：(卖出价 − 昨收) × 卖出克重（卖出时刻即锁定）
  /// - 生息克重今日新增、无成本基准，今日盈亏计 0
  /// 隔夜总克重 = 当前克重 − 今日买入 + 今日卖出 + 今日生息；
  /// 其中今日已卖出的部分按卖出价而非现价，故隔夜持有克重 = 隔夜总克重 − 今日卖出。
  /// [tradesToday] 为当日交易记录（time >= 当日 0 点）。
  static double todayProfitPrecise({
    required double price,
    required double preClose,
    required double amountNow,
    required Iterable<TradeRecord> tradesToday,
  }) {
    var overnight = amountNow;
    var buyProfit = 0.0;
    var sellProfit = 0.0;
    var soldToday = 0.0;
    for (final t in tradesToday) {
      switch (t.type) {
        case 'buy':
          overnight -= t.amount; // 今日买入克重不算隔夜
          buyProfit += (price - t.price) * t.amount;
          break;
        case 'sell':
          overnight += t.amount; // 当前克重不含已卖出部分，还原回隔夜
          soldToday += t.amount;
          sellProfit += (t.price - preClose) * t.amount;
          break;
        case 'interest':
          overnight -= t.amount; // 生息克重今日才有，不算隔夜
          break;
      }
    }
    final overnightHeld = overnight - soldToday;
    return (price - preClose) * overnightHeld + buyProfit + sellProfit;
  }

  /// 筛选当日（time >= 当日 0 点）交易记录，供精确今日盈亏口径使用。
  static List<TradeRecord> tradesTodayOf(Iterable<TradeRecord> trades) {
    final now = DateTime.now();
    final todayStart =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return trades.where((t) => t.time >= todayStart).toList();
  }

  /// 历史卖出净收入 = Σ(卖出克重×卖出价 − 手续费)。
  static double sellNetProceeds(Iterable<TradeRecord> sellTrades) =>
      sellTrades.fold(0.0, (sum, t) => sum + t.amount * t.price - t.fee);

  /// 累计收益（已实现 + 未实现）：
  /// 累计 = Σ卖出净得 + 当前持仓市值 − 累计买入总成本（boughtCost）。
  /// 卖出按均价扣减 totalCost 后，若仍用 totalCost 计算会虚增已实现部分，
  /// 故用独立累计投入 boughtCost 保持恒等式对任意买卖/生息序列成立。
  static double cumulativeProfit({
    required double currentPrice,
    required double amount,
    required double boughtCost,
    required Iterable<TradeRecord> sellTrades,
  }) => sellNetProceeds(sellTrades) + currentPrice * amount - boughtCost;

  /// 加权平均成本法应用一笔交易到持仓状态。
  /// [amount] 当前克重，[totalCost] 剩余总成本，[boughtCost] 累计买入总成本。
  /// 买入：克重、剩余成本与累计投入都增（均价改变 = 新总成本 ÷ 新数量）；
  /// 生息：仅克重增（摊薄均价）；卖出：克重减、剩余成本扣 均价×卖出克重（均价不变），
  ///       累计投入不变。
  static ({double amount, double totalCost, double boughtCost}) applyTrade({
    required double amount,
    required double totalCost,
    required double boughtCost,
    required TradeRecord record,
  }) {
    switch (record.type) {
      case 'buy':
        return (
          amount: amount + record.amount,
          totalCost: totalCost + record.amount * record.price,
          boughtCost: boughtCost + record.amount * record.price,
        );
      case 'interest':
        return (
          amount: amount + record.amount,
          totalCost: totalCost,
          boughtCost: boughtCost,
        );
      case 'sell':
        if (record.amount > amount) {
          throw ArgumentError('卖出克重不能大于当前持仓');
        }
        final avg = avgCost(totalCost, amount);
        return (
          amount: amount - record.amount,
          totalCost: totalCost - avg * record.amount,
          boughtCost: boughtCost,
        );
      default:
        throw ArgumentError('未知交易类型: ${record.type}');
    }
  }

  /// 反向应用一笔交易（删除交易时回滚持仓状态）。
  /// buy → 减克重、剩余成本与累计投入；sell → 加克重、加回 均价×卖出克重；
  /// interest → 减克重。回滚后克重/成本/累计投入为负时返回 null（禁止删除）。
  /// 卖出后均价不变，故回滚加回的均价用当前 avgCost 即可精确还原。
  static ({double amount, double totalCost, double boughtCost})? reverseTrade({
    required double amount,
    required double totalCost,
    required double boughtCost,
    required TradeRecord record,
  }) {
    switch (record.type) {
      case 'buy':
        if (amount < record.amount ||
            totalCost < record.amount * record.price ||
            boughtCost < record.amount * record.price) {
          return null;
        }
        return (
          amount: amount - record.amount,
          totalCost: totalCost - record.amount * record.price,
          boughtCost: boughtCost - record.amount * record.price,
        );
      case 'interest':
        if (amount < record.amount) {
          return null;
        }
        return (
          amount: amount - record.amount,
          totalCost: totalCost,
          boughtCost: boughtCost,
        );
      case 'sell':
        final avg = avgCost(totalCost, amount);
        return (
          amount: amount + record.amount,
          totalCost: totalCost + avg * record.amount,
          boughtCost: boughtCost,
        );
      default:
        return (
          amount: amount,
          totalCost: totalCost,
          boughtCost: boughtCost,
        );
    }
  }
}
