// test/notification_metrics_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/models/trade_record.dart';
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

    test('今日买入：今日盈亏按买入价基准（不虚增昨收到买入价区间）', () {
      // 用户场景：隔夜无持仓、今日买入 10g@883.1，昨收 880，现价 895.8。
      final todayPos = PositionSnapshot(
        kind: 'accumulation', grams: 10, totalCost: 8831,
        boughtCost: 8831, soldNet: 0,
        todayTrades: [
          TradeRecord(id: 1, holdingId: 1, type: 'buy', amount: 10,
              price: 883.1, fee: 0, time: 100),
        ],
      );
      final m = computeNotificationMetrics(price: 895.8, preClose: 880, pos: todayPos);
      // 持仓收益 = (895.8 − 883.1) × 10 = 127
      expect(m['floatingProfit'], '+127.00');
      // 今日盈亏 = (895.8 − 883.1) × 10 = 127，而不是 (895.8 − 880) × 10 = 158
      expect(m['todayProfit'], '+127.00');
    });

    test('PositionSnapshot JSON round-trip 保留 todayTrades（后台 isolate 传参链路）', () {
      final pos = PositionSnapshot(
        kind: 'accumulation', grams: 10, totalCost: 8831,
        boughtCost: 8831, soldNet: 0,
        todayTrades: [
          TradeRecord(id: 1, holdingId: 1, type: 'buy', amount: 10,
              price: 883.1, fee: 0, time: 100),
        ],
      );
      // 模拟 sendDataToTask 的 JSON 序列化：encode → decode → fromJson。
      final json = jsonDecode(jsonEncode(pos.toJson())) as Map<String, dynamic>;
      final back = PositionSnapshot.fromJson(json);
      expect(back.todayTrades, hasLength(1));
      expect(back.todayTrades.single.type, 'buy');
      expect(back.todayTrades.single.price, closeTo(883.1, 1e-9));
    });
  });
}
