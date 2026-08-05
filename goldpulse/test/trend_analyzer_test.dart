// test/trend_analyzer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/trend_analyzer.dart';

void main() {
  group('trendOf', () {
    test('点数少于 5 → insufficient', () {
      expect(trendOf(const []), TradeTrend.insufficient);
      expect(trendOf(const [800, 801, 802, 803]), TradeTrend.insufficient);
    });

    test('近期上涨超过阈值 → up', () {
      // 100 点到 103 点：+3%
      expect(trendOf([for (var i = 0; i < 100; i++) 100 + i * 0.03]),
          TradeTrend.up);
    });

    test('近期下跌超过阈值 → down', () {
      expect(trendOf([for (var i = 0; i < 100; i++) 100 - i * 0.03]),
          TradeTrend.down);
    });

    test('波动小于阈值 → flat', () {
      // 800 到 801：+0.125%，低于 0.5% 阈值
      expect(trendOf([800, 800.2, 800.5, 800.8, 801]), TradeTrend.flat);
    });

    test('自定义阈值生效', () {
      // +0.3% 用 0.2% 阈值判定为 up
      expect(trendOf([800, 800.5, 801, 801.5, 802.4],
          thresholdPercent: 0.2), TradeTrend.up);
    });

    test('首价非正数 → insufficient（防御）', () {
      expect(trendOf([0, 800, 801, 802, 803]), TradeTrend.insufficient);
    });
  });
}
