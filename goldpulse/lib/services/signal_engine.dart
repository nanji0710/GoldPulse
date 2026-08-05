// lib/services/signal_engine.dart
// 智能建议-信号引擎：置信度评分 + 收益率×趋势信号规则 + 理由文案 + 防频繁提醒冷却。
// 全部为纯函数，供 suggestionsProvider 组合生成建议。
import 'trend_analyzer.dart';

/// 建议信号（紧急度由高到低：riskAlert > takeProfit > reduce > buy > watch > hold > insufficient）。
enum TradeSignal { riskAlert, takeProfit, reduce, buy, watch, hold, insufficient }

/// 单个品种的一条建议。
class TradeSuggestion {
  final String kind;
  final String label;
  final TradeTrend trend;
  final TradeSignal signal;
  final double score;       // 置信度 0-100
  final List<String> reasons;
  final double profitRate;  // 收益率 %（浮盈/成本）
  final DateTime updatedAt;
  const TradeSuggestion({
    required this.kind,
    required this.label,
    required this.trend,
    required this.signal,
    required this.score,
    required this.reasons,
    required this.profitRate,
    required this.updatedAt,
  });
}

/// 置信度评分 0-100：今日涨跌 30% + 近期窗口 40% + 持仓状态 30%。
double scoreOf({
  required double todayPercent,
  required double windowPercent,
  required double profitRate,
}) {
  final today = 50 + todayPercent * 6;
  final window = 50 + windowPercent * 6;
  final profit = 50 + profitRate * 1.2;
  final s = 0.3 * today + 0.4 * window + 0.3 * profit;
  return s.clamp(0, 100);
}

/// 信号规则：收益率分档 × 趋势（严格按方案口径）。
TradeSignal signalOf({
  required double profitRate,
  required TradeTrend trend,
  required double todayPercent,
}) {
  if (trend == TradeTrend.insufficient) return TradeSignal.insufficient;
  if (profitRate <= -15) return TradeSignal.riskAlert;
  if (profitRate <= -5) {
    return trend == TradeTrend.up ? TradeSignal.buy : TradeSignal.watch;
  }
  if (profitRate <= 5) return TradeSignal.hold;
  if (profitRate <= 20) {
    return trend == TradeTrend.up ? TradeSignal.hold : TradeSignal.reduce;
  }
  // 收益率 > 20%：短期涨幅 ≥10% 才提示止盈，否则持有。
  return todayPercent >= 10 ? TradeSignal.takeProfit : TradeSignal.hold;
}

String _pct(double v) => v.abs().toStringAsFixed(1);

/// 生成理由文案（insufficient 1 条，其余 2 条；第一条讲趋势/行情，第二条讲持仓收益）。
List<String> reasonsFor(TradeSuggestion s) {
  final pct = _pct(s.profitRate);
  final sign = s.profitRate >= 0 ? '+' : '-';
  switch (s.signal) {
    case TradeSignal.riskAlert:
      return [
        '今日及近期走势偏弱，趋势走低',
        '收益率 $sign$pct%，亏损较大，建议重新评估仓位',
      ];
    case TradeSignal.buy:
      return [
        '趋势回升，方向向好',
        '收益率 $sign$pct%，仍低于成本，可分批补仓摊薄',
      ];
    case TradeSignal.takeProfit:
      return [
        '短期涨幅较快，注意高位波动',
        '收益率 $sign$pct%，可分批止盈（卖出 20%-30% 锁定收益）',
      ];
    case TradeSignal.reduce:
      return [
        '近期趋势转弱',
        '收益率 $sign$pct%，可考虑减仓止盈部分',
      ];
    case TradeSignal.watch:
      return [
        '近期趋势走低',
        '收益率 $sign$pct%，谨慎观望，等待反弹确认',
      ];
    case TradeSignal.hold:
      return [
        '趋势平稳或向好，未出现明显破坏信号',
        '收益率 $sign$pct%，继续持有观望',
      ];
    case TradeSignal.insufficient:
      return ['行情数据积累中，打开 App 一段时间后自动生成建议'];
  }
}

/// 防频繁提醒：24h 内信号一致且未突破阈值（价格波动>5% 或 评分变化>20）则沿用上次建议。
TradeSuggestion applyCooling({
  required TradeSuggestion current,
  required TradeSuggestion? last,
  required DateTime now,
  required double priceMovePercent,
}) {
  if (last == null) return current;
  if (now.difference(last.updatedAt) > const Duration(hours: 24)) return current;
  if (priceMovePercent > 5) return current;
  if ((current.score - last.score).abs() > 20) return current;
  if (current.signal != last.signal) return current;
  return last;
}
