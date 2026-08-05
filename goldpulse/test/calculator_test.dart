// test/calculator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/calculator.dart';
import 'package:goldpulse/models/trade_record.dart';

void main() {
  test('当前价值 = 价格 × 克重', () {
    expect(Calculator.currentValue(781.5, 501.2), closeTo(391687.80, 0.01));
  });
  test('浮动收益 = 价值 − 总成本', () {
    expect(Calculator.floatingProfit(781.5, 501.2, 310000), closeTo(81687.80, 0.01));
  });
  test('收益率', () {
    expect(Calculator.profitRate(81687.80, 310000), closeTo(0.2635, 0.0001));
  });
  test('平均成本 = 总成本 ÷ 克重（生息摊薄）', () {
    expect(Calculator.avgCost(310000, 501.2), closeTo(618.515, 0.001));
  });
  test('卖出手续费 = 金额 × 0.4%', () {
    expect(Calculator.sellFee(100, 780.20), closeTo(312.08, 0.01));
  });
  test('卖出净收益含手续费', () {
    // 100g @780.20，平均成本 620，手续费 100*780.20*0.004=312.08
    expect(Calculator.sellNetProfit(100, 780.20, 620), closeTo(100*(780.20-620)-312.08, 0.01));
  });
  test('applyTrade: 买入累加克重与成本', () {
    final h = Calculator.applyTrade(amount: 0, totalCost: 0, boughtCost: 0,
        record: TradeRecord(holdingId: 1, type: 'buy', amount: 100, price: 600, fee: 0, time: 1));
    expect(h.amount, 100);
    expect(h.totalCost, 60000);
    expect(h.boughtCost, 60000);
  });
  test('applyTrade: 生息只增克重、摊薄成本', () {
    final h = Calculator.applyTrade(amount: 500, totalCost: 310000, boughtCost: 310000,
        record: TradeRecord(holdingId: 1, type: 'interest', amount: 1.2, price: 0, fee: 0, time: 1));
    expect(h.amount, 501.2);
    expect(h.totalCost, 310000);
    expect(h.boughtCost, 310000);
  });
  test('applyTrade: 卖出扣成本、均价不变', () {
    // 500g@均价 620，卖 50g → 扣 620×50=31000，剩 450g、成本 279000，均价仍 620
    final h = Calculator.applyTrade(amount: 500, totalCost: 310000, boughtCost: 310000,
        record: TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 720, fee: 144, time: 1));
    expect(h.amount, 450);
    expect(h.totalCost, closeTo(279000, 0.01));
    expect(h.boughtCost, 310000);
    expect(Calculator.avgCost(h.totalCost, h.amount), closeTo(620, 0.001));
  });
  test('卖出后禁止负克重', () {
    expect(() => Calculator.applyTrade(amount: 10, totalCost: 1000, boughtCost: 1000,
        record: TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 720, fee: 0, time: 1)),
        throwsArgumentError);
  });
  test('todayProfit: 上涨为正', () {
    expect(Calculator.todayProfit(781.5, 780.0, 501.2), closeTo(751.80, 0.01));
  });
  test('todayProfit: 下跌为负', () {
    expect(Calculator.todayProfit(778.5, 780.0, 100), closeTo(-150.0, 0.01));
  });
  test('todayProfit: 平盘为零', () {
    expect(Calculator.todayProfit(780.0, 780.0, 501.2), closeTo(0, 0.0001));
  });
  test('todayProfitPrecise: 无今日交易 = 隔夜持仓按昨收', () {
    expect(Calculator.todayProfitPrecise(
        price: 895.8, preClose: 880, amountNow: 10, tradesToday: const []),
        closeTo((895.8 - 880) * 10, 1e-9)); // 158
  });
  test('todayProfitPrecise: 今日买入按买入价（不虚增昨收到买入价区间）', () {
    // 用户场景：昨收 880、今日买入 10g@883.1、现价 895.8。
    final trades = [
      TradeRecord(holdingId: 1, type: 'buy', amount: 10, price: 883.1, fee: 0, time: 100),
    ];
    // 隔夜克重 = 10 − 10 = 0；今日盈亏 = (895.8 − 883.1) × 10 = 127
    expect(Calculator.todayProfitPrecise(
        price: 895.8, preClose: 880, amountNow: 10, tradesToday: trades),
        closeTo((895.8 - 883.1) * 10, 1e-9));
  });
  test('todayProfitPrecise: 今日卖出按卖出价锁定', () {
    // 隔夜持 10g，今日卖出 4g@890，昨收 880，现价 895.8。
    final trades = [
      TradeRecord(holdingId: 1, type: 'sell', amount: 4, price: 890, fee: 0, time: 100),
    ];
    // 隔夜克重 = 10 + 4 = 14？不：当前克重 6，隔夜 = 6 + 4 = 10。
    // 今日盈亏 = (895.8 − 880) × 6（剩余隔夜6g） + (890 − 880) × 4（已卖出4g）
    expect(Calculator.todayProfitPrecise(
        price: 895.8, preClose: 880, amountNow: 6, tradesToday: trades),
        closeTo((895.8 - 880) * 6 + (890 - 880) * 4, 1e-9));
  });
  test('todayProfitPrecise: 生息克重不计今日盈亏（无成本基准）', () {
    final trades = [
      TradeRecord(holdingId: 1, type: 'interest', amount: 0.08, price: 0, fee: 0, time: 100),
    ];
    // 当前克重 10.08（含今日生息 0.08），生息克重从隔夜扣除。
    // 隔夜 = 10.08 − 0.08 = 10；今日盈亏 = (895.8 − 880) × 10。
    expect(Calculator.todayProfitPrecise(
        price: 895.8, preClose: 880, amountNow: 10.08, tradesToday: trades),
        closeTo((895.8 - 880) * 10, 1e-9));
  });
  test('sellNetProceeds: 多卖单净收入 = Σ(克重×价 − 手续费)', () {
    final sells = [
      TradeRecord(holdingId: 1, type: 'sell', amount: 100, price: 780.20, fee: 312.08, time: 1),
      TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 800, fee: 160, time: 2),
    ];
    // (100×780.20−312.08) + (50×800−160) = 77707.92 + 39840
    expect(Calculator.sellNetProceeds(sells), closeTo(117547.92, 0.01));
  });
  test('cumulativeProfit: 无卖出时等于浮动收益', () {
    expect(Calculator.cumulativeProfit(
        currentPrice: 781.5, amount: 501.2, boughtCost: 310000, sellTrades: const []),
        closeTo(Calculator.floatingProfit(781.5, 501.2, 310000), 0.001));
  });
  test('cumulativeProfit: 全部卖出为纯已实现 = 卖出净得 − 累计投入', () {
    final sells = [TradeRecord(holdingId: 1, type: 'sell', amount: 500, price: 780.20, fee: 312.08, time: 1)];
    // 卖出净得 500×780.20−312.08 = 389787.92；− 累计投入 310000 = 79787.92
    expect(Calculator.cumulativeProfit(
        currentPrice: 780.2, amount: 0, boughtCost: 310000, sellTrades: sells),
        closeTo(79787.92, 0.01));
  });
  test('cumulativeProfit: 部分卖出 = 已实现 + 未实现', () {
    // 原持仓 501.2g、累计投入 310000，卖出 50g@720（手续费 144），剩 451.2g。
    final sells = [TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 720, fee: 144, time: 1)];
    // 卖出净得 35856 + 剩余市值 781.5×451.2 = 352612.8 − 累计投入 310000 = 78468.8
    expect(Calculator.cumulativeProfit(
        currentPrice: 781.5, amount: 451.2, boughtCost: 310000, sellTrades: sells),
        closeTo(78468.8, 0.01));
  });
  test('加权平均成本法：买卖成本变化（用户示例）', () {
    // 买 100g@780 → (100, 78000, bought 78000, avg 780)
    final b1 = Calculator.applyTrade(amount: 0, totalCost: 0, boughtCost: 0,
        record: TradeRecord(holdingId: 1, type: 'buy', amount: 100, price: 780, fee: 0, time: 1));
    expect(b1.amount, 100);
    expect(b1.totalCost, 78000);
    expect(b1.boughtCost, 78000);
    // 再买 50g@800 → (150, 118000, bought 118000, avg 786.67)
    final b2 = Calculator.applyTrade(amount: b1.amount, totalCost: b1.totalCost, boughtCost: b1.boughtCost,
        record: TradeRecord(holdingId: 1, type: 'buy', amount: 50, price: 800, fee: 0, time: 2));
    expect(b2.amount, 150);
    expect(b2.totalCost, 118000);
    expect(b2.boughtCost, 118000);
    expect(Calculator.avgCost(b2.totalCost, b2.amount), closeTo(786.67, 0.01));
    // 卖 50g@900 fee36 → (100, 78666.67, bought 118000, avg 786.67 不变)。
    // 注：扣成本用精确均价 786.666…（未先舍入），故总成本 78666.67 而非 78666.5。
    final s = Calculator.applyTrade(amount: b2.amount, totalCost: b2.totalCost, boughtCost: b2.boughtCost,
        record: TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 900, fee: 36, time: 3));
    expect(s.amount, 100);
    expect(s.totalCost, closeTo(78666.67, 0.01));
    expect(s.boughtCost, 118000);
    expect(Calculator.avgCost(s.totalCost, s.amount), closeTo(786.67, 0.01));
    // 累计收益不虚增：Σ卖出净得(45000−36) + 现价×100 − 累计投入 118000
    expect(Calculator.cumulativeProfit(currentPrice: 900, amount: 100, boughtCost: 118000,
        sellTrades: [TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 900, fee: 36, time: 3)]),
        closeTo(44964 + 90000 - 118000, 0.01));
  });
}
