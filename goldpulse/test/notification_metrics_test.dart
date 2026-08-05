// test/notification_metrics_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/notification_metrics.dart';

void main() {
  group('computeNotificationMetrics', () {
    const pos = PositionSnapshot(
        kind: 'accumulation', grams: 50, totalCost: 44800,
        boughtCost: 44800, soldNet: 0);

    test('8 个指标齐全且口径正确', () {
      final m = computeNotificationMetrics(price: 900, preClose: 895, pos: pos);
      expect(m, hasLength(8));
      expect(m['price'], '900.00');
      expect(m['avgCost'], '896.00'); // 44800/50
      expect(m['floatingProfit'], '+200.00'); // 900*50-44800
      expect(m['profitRate'], '+0.45%'); // 200/44800*100
      expect(m['todayProfit'], '+250.00'); // (900-895)*50
      expect(m['cumulativeProfit'], '+200.00'); // 0+900*50-44800
    });

    test('亏损为负号', () {
      final m = computeNotificationMetrics(price: 850, preClose: 855, pos: pos);
      expect(m['floatingProfit'], '-2,300.00'); // 850*50-44800（fmtPrice 带千分位）
      expect(m['profitRate'], startsWith('-'));
      expect(m['todayProfit'], '-250.00');
    });

    test('克重为 0 → 均价/收益显示 --', () {
      const empty = PositionSnapshot(
          kind: 'accumulation', grams: 0, totalCost: 0, boughtCost: 0, soldNet: 0);
      final m = computeNotificationMetrics(price: 900, preClose: 895, pos: empty);
      expect(m['avgCost'], '--');
      expect(m['floatingProfit'], '--');
      expect(m['profitRate'], '--');
    });

    test('指标 id 与 label 映射完整', () {
      expect(metricIds, hasLength(8));
      for (final id in metricIds) {
        expect(metricLabels[id], isNotNull, reason: '指标 $id 缺中文名');
      }
    });
  });
}
