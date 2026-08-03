// test/candlestick_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/widgets/chart.dart';

void main() {
  test('K线聚合：由 price 序列生成 OHLC 分组', () {
    final bars = CandlestickChart.aggregateBars(
        prices: [100, 102, 101, 103, 99, 98, 100],
        groupSize: 2);
    expect(bars.length, 4); // 7 个点按 2 分组 → 4 组
    expect(bars.first.high, 102);
    expect(bars.first.low, 100);
  });
}
