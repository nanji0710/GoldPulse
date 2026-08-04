// test/state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/state/asset_provider.dart';

void main() {
  test('AssetSummary 由计算模块聚合', () {
    final s = AssetSummary.compute(
        currentPrice: 781.5, preClose: 780.0, amount: 501.2, totalCost: 310000);
    expect(s.currentValue, closeTo(391687.80, 0.01));
    expect(s.floatingProfit, closeTo(81687.80, 0.01));
    expect(s.avgCost, closeTo(618.515, 0.001));
    // 今日盈亏 = (现价 − 昨收) × 克重 = 1.5 × 501.2
    expect(s.todayProfit, closeTo(751.80, 0.01));
    // 无卖出交易时，累计收益退化为持仓收益
    expect(s.cumulativeProfit, closeTo(s.floatingProfit, 0.001));
  });
}
