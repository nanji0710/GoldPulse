// test/signal_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/signal_engine.dart';
import 'package:goldpulse/services/trend_analyzer.dart';

void main() {
  group('scoreOf', () {
    test('权重 0.3/0.4/0.3：全部中性（0%）→ 50 分', () {
      expect(scoreOf(todayPercent: 0, windowPercent: 0, profitRate: 0), 50);
    });
    test('上涨加成：今日+1%、窗口+2%、盈利+10% → 高于 50', () {
      final s = scoreOf(todayPercent: 1, windowPercent: 2, profitRate: 10);
      expect(s, greaterThan(50));
    });
    test('下跌压制：今日-1%、窗口-2%、亏损-10% → 低于 50', () {
      final s = scoreOf(todayPercent: -1, windowPercent: -2, profitRate: -10);
      expect(s, lessThan(50));
    });
    test('极端值被 clamp 到 [0,100]', () {
      expect(scoreOf(todayPercent: 999, windowPercent: 999, profitRate: 999), 100);
      expect(scoreOf(todayPercent: -999, windowPercent: -999, profitRate: -999), 0);
    });
  });

  group('signalOf', () {
    test('数据不足 → insufficient', () {
      expect(signalOf(profitRate: 0, trend: TradeTrend.insufficient, todayPercent: 0),
          TradeSignal.insufficient);
    });
    test('深度亏损 ≤ -15% → riskAlert', () {
      expect(signalOf(profitRate: -16, trend: TradeTrend.down, todayPercent: -1),
          TradeSignal.riskAlert);
    });
    test('中亏 -15~-5%：趋势向上 → buy', () {
      expect(signalOf(profitRate: -10, trend: TradeTrend.up, todayPercent: 1),
          TradeSignal.buy);
    });
    test('中亏 -15~-5%：趋势向下 → watch', () {
      expect(signalOf(profitRate: -10, trend: TradeTrend.down, todayPercent: -1),
          TradeSignal.watch);
    });
    test('小幅盈亏 -5~5% → hold', () {
      expect(signalOf(profitRate: 3, trend: TradeTrend.up, todayPercent: 0.5),
          TradeSignal.hold);
      expect(signalOf(profitRate: -3, trend: TradeTrend.down, todayPercent: -0.5),
          TradeSignal.hold);
    });
    test('盈利 5~20%：趋势向上 → hold', () {
      expect(signalOf(profitRate: 12, trend: TradeTrend.up, todayPercent: 2),
          TradeSignal.hold);
    });
    test('盈利 5~20%：趋势向下 → reduce', () {
      expect(signalOf(profitRate: 12, trend: TradeTrend.down, todayPercent: -2),
          TradeSignal.reduce);
    });
    test('盈利 >20% 且短期涨幅 ≥10% → takeProfit', () {
      expect(signalOf(profitRate: 25, trend: TradeTrend.up, todayPercent: 11),
          TradeSignal.takeProfit);
    });
    test('盈利 >20% 但短期涨幅小 → hold', () {
      expect(signalOf(profitRate: 25, trend: TradeTrend.up, todayPercent: 2),
          TradeSignal.hold);
    });
  });

  group('reasonsFor', () {
    test('riskAlert 给出亏损重新评估文案', () {
      final s = TradeSuggestion(
          kind: 'accumulation', label: '浙商积存金',
          trend: TradeTrend.down, signal: TradeSignal.riskAlert,
          score: 30, reasons: const [], profitRate: -16,
          updatedAt: DateTime(2026, 8, 5));
      final r = reasonsFor(s);
      expect(r.join(), contains('亏损'));
      expect(r.join(), contains('重新评估'));
    });
    test('buy 给出分批补仓文案', () {
      final s = TradeSuggestion(
          kind: 'accumulation', label: '浙商积存金',
          trend: TradeTrend.up, signal: TradeSignal.buy,
          score: 60, reasons: const [], profitRate: -10,
          updatedAt: DateTime(2026, 8, 5));
      final r = reasonsFor(s);
      expect(r.join(), contains('补仓'));
    });
  });

  group('applyCooling', () {
    final current = TradeSuggestion(
        kind: 'a', label: '浙商积存金', trend: TradeTrend.up, signal: TradeSignal.hold,
        score: 70, reasons: const [], profitRate: 8,
        updatedAt: DateTime(2026, 8, 5, 10));
    final last = TradeSuggestion(
        kind: 'a', label: '浙商积存金', trend: TradeTrend.up, signal: TradeSignal.hold,
        score: 68, reasons: const [], profitRate: 8,
        updatedAt: DateTime(2026, 8, 5, 9));

    test('无上次建议 → 直接返回 current', () {
      expect(applyCooling(current: current, last: null,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 0), same(current));
    });
    test('距上次 <24h 且信号一致且未突破阈值 → 沿用 last', () {
      expect(applyCooling(current: current, last: last,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 1), same(last));
    });
    test('超过 24h → 返回 current', () {
      expect(applyCooling(current: current, last: last,
          now: DateTime(2026, 8, 6, 10), priceMovePercent: 0), same(current));
    });
    test('价格波动 >5% → 返回 current（打破冷却）', () {
      expect(applyCooling(current: current, last: last,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 6), same(current));
    });
    test('评分变化 >20 → 返回 current（打破冷却）', () {
      final bigMove = TradeSuggestion(
          kind: 'a', label: '浙商积存金', trend: TradeTrend.up, signal: TradeSignal.hold,
          score: 92, reasons: const [], profitRate: 8,
          updatedAt: DateTime(2026, 8, 5, 11));
      expect(applyCooling(current: bigMove, last: last,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 1), same(bigMove));
    });
    test('信号改变 → 返回 current', () {
      final changed = TradeSuggestion(
          kind: 'a', label: '浙商积存金', trend: TradeTrend.down, signal: TradeSignal.reduce,
          score: 40, reasons: const [], profitRate: 8,
          updatedAt: DateTime(2026, 8, 5, 11));
      expect(applyCooling(current: changed, last: last,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 1), same(changed));
    });
  });
}
