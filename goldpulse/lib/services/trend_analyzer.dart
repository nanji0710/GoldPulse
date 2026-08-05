// lib/services/trend_analyzer.dart
// 智能建议-趋势判断：基于近期价格序列（按时间升序，最新在末尾）判断涨跌方向。
// 纯函数、无外部依赖，供 SignalEngine 与 suggestionsProvider 复用。
enum TradeTrend { up, down, flat, insufficient }

/// [prices] 按时间升序的价格列表。点数 < 5 或数据非法返回 [TradeTrend.insufficient]。
/// [thresholdPercent] 判定为涨/跌的最小变化率（%），默认 0.5%。
TradeTrend trendOf(List<double> prices, {double thresholdPercent = 0.5}) {
  if (prices.length < 5) return TradeTrend.insufficient;
  final first = prices.first;
  final last = prices.last;
  if (first <= 0 || last <= 0) return TradeTrend.insufficient;
  final change = (last - first) / first * 100;
  if (change > thresholdPercent) return TradeTrend.up;
  if (change < -thresholdPercent) return TradeTrend.down;
  return TradeTrend.flat;
}
