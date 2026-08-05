// test/persistent_notification_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/notification_metrics.dart';
import 'package:goldpulse/services/persistent_notification_service.dart';

void main() {
  group('buildNotificationText', () {
    const pos = PositionSnapshot(
        kind: 'accumulation', grams: 50, totalCost: 44800,
        boughtCost: 44800, soldNet: 0);
    final metrics = computeNotificationMetrics(price: 900, preClose: 895, pos: pos);

    test('第一行固定现价+涨跌，下方自选指标', () {
      final t = buildNotificationText(
          metrics: metrics,
          selectedMetrics: ['avgCost', 'floatingProfit', 'profitRate', 'todayProfit']);
      expect(t, contains('900.00'));       // 现价固定行
      expect(t, contains('浙商积存金'));     // 品种名
      expect(t, contains('均价(成本)'));     // 自选指标
      expect(t, contains('持仓收益'));
      expect(t, contains('收益率'));
      expect(t, contains('今日盈亏'));
      expect(t, contains('896.00'));       // 均价值
      expect(t, contains('+200.00'));      // 持仓收益值
      expect(t, contains('+0.45%'));       // 收益率值
    });

    test('自定义 4 指标组合', () {
      final t = buildNotificationText(
          metrics: metrics,
          selectedMetrics: ['change', 'changePct', 'cumulativeProfit', 'avgCost']);
      expect(t, contains('涨跌额'));
      expect(t, contains('涨跌幅'));
      expect(t, contains('累计收益'));
      expect(t, contains('均价(成本)'));
      expect(t, isNot(contains('持仓收益'))); // 未选则不显示
    });

    test('自选指标每行两个（2 列网格），奇数个最后一行单个', () {
      final t = buildNotificationText(
          metrics: metrics,
          selectedMetrics: ['avgCost', 'floatingProfit', 'profitRate']);
      final lines = t.split('\n');
      // 第一行是固定行（品种+涨跌+现价），其后为指标行。
      final metricLines = lines.skip(1).toList();
      expect(metricLines, hasLength(2));
      expect(metricLines[0], contains('均价(成本)'));
      expect(metricLines[0], contains('持仓收益'));
      expect(metricLines[1], contains('收益率'));
      expect(metricLines[1], isNot(contains('今日盈亏')));
    });
  });
}
