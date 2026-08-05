// lib/state/suggestion_provider.dart
// 智能建议-数据组合：汇总各品种持仓 + DB 行情序列 → 实时生成建议列表（按紧急度排序，主建议在首位）。
// 无冷却：随行情流刷新（typeSummariesProvider 依赖价格流）每次重算，建议内容与时间戳都实时更新。
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/signal_engine.dart';
import '../services/trend_analyzer.dart';
import 'asset_provider.dart';
import 'price_provider.dart';

final suggestionsProvider = FutureProvider<List<TradeSuggestion>>((ref) async {
  final summaries = await ref.watch(typeSummariesProvider.future);
  if (summaries.isEmpty) return const [];
  final dao = ref.watch(priceDaoProvider);
  final now = DateTime.now();
  final result = <TradeSuggestion>[];

  for (final t in summaries) {
    if (t.currentPrice == null) continue; // 无行情 → 不生成建议
    final code = switch (t.kind) {
      'au9999' => 'SGE-Au(T+D)',
      'icbc' => 'ICBC-JCJ',
      _ => 'CZB-JCJ',
    };
    final recent = await dao.recent(code, limit: 60); // DESC
    final prices = <double>[
      for (final gp in recent.reversed) gp.price,
      t.currentPrice!,
    ];

    final trend = trendOf(prices);
    final todayPercent = t.preClose == null || t.preClose! <= 0
        ? 0.0
        : (t.currentPrice! - t.preClose!) / t.preClose! * 100;
    final profitRate =
        t.totalCost <= 0 ? 0.0 : t.floatingProfit / t.totalCost * 100;
    final windowPercent = trend == TradeTrend.insufficient || prices.first <= 0
        ? 0.0
        : (prices.last - prices.first) / prices.first * 100;

    final score = scoreOf(
        todayPercent: todayPercent,
        windowPercent: windowPercent,
        profitRate: profitRate);
    final signal = signalOf(
        profitRate: profitRate, trend: trend, todayPercent: todayPercent);
    final current = TradeSuggestion(
      kind: t.kind, label: t.label, trend: trend, signal: signal,
      score: score, reasons: const [], profitRate: profitRate,
      updatedAt: now,
    );
    result.add(TradeSuggestion(
      kind: current.kind, label: current.label,
      trend: current.trend, signal: current.signal,
      score: current.score, reasons: reasonsFor(current),
      profitRate: current.profitRate, updatedAt: current.updatedAt,
    ));
  }

  // 紧急度排序：riskAlert 最高，insufficient 最低（枚举声明顺序即紧急度顺序）。
  result.sort((a, b) => a.signal.index.compareTo(b.signal.index));
  // 诊断日志（release 同样输出到 logcat）：确认建议随行情刷新实时重算。
  debugPrint('[金脉建议] 实时计算: '
      '${result.map((s) => '${s.label}=${s.signal.name}(${s.score.round()}分)').join(', ')}'
      ' @ ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');
  return result;
});
