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
    final h = Calculator.applyTrade(amount: 0, totalCost: 0,
        record: TradeRecord(holdingId: 1, type: 'buy', amount: 100, price: 600, fee: 0, time: 1));
    expect(h.amount, 100);
    expect(h.totalCost, 60000);
  });
  test('applyTrade: 生息只增克重、摊薄成本', () {
    final h = Calculator.applyTrade(amount: 500, totalCost: 310000,
        record: TradeRecord(holdingId: 1, type: 'interest', amount: 1.2, price: 0, fee: 0, time: 1));
    expect(h.amount, 501.2);
    expect(h.totalCost, 310000);
  });
  test('applyTrade: 卖出只减克重、保留成本', () {
    final h = Calculator.applyTrade(amount: 500, totalCost: 310000,
        record: TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 720, fee: 144, time: 1));
    expect(h.amount, 450);
    expect(h.totalCost, 310000);
  });
  test('卖出后禁止负克重', () {
    expect(() => Calculator.applyTrade(amount: 10, totalCost: 1000,
        record: TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 720, fee: 0, time: 1)),
        throwsArgumentError);
  });
}
