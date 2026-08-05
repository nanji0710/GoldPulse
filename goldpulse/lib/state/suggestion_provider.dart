// lib/state/suggestion_provider.dart
// 智能建议-数据组合：汇总各品种持仓 + DB 行情序列 → 生成建议列表（按紧急度排序，主建议在首位）。
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/signal_engine.dart';
import '../services/trend_analyzer.dart';
import 'asset_provider.dart';
import 'price_provider.dart';

/// 冷却存储前缀：`suggestion_last_<kind>` → JSON {signal, score, at(毫秒)}。
final suggestionsProvider = FutureProvider<List<TradeSuggestion>>((ref) async {
  final summaries = await ref.watch(typeSummariesProvider.future);
  if (summaries.isEmpty) return const [];
  final dao = ref.watch(priceDaoProvider);
  final prefs = await SharedPreferences.getInstance();
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
    final priceMovePercent =
        math.max(todayPercent.abs(), windowPercent.abs());

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

    // 冷却：读上次建议，applyCooling 决定本次是否沿用。
    final key = 'suggestion_last_${t.kind}';
    TradeSuggestion? last;
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        last = TradeSuggestion(
          kind: t.kind, label: t.label,
          trend: TradeTrend.values.byName(m['trend'] as String),
          signal: TradeSignal.values.byName(m['signal'] as String),
          score: (m['score'] as num).toDouble(),
          reasons: const [],
          profitRate: profitRate,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        );
      } catch (_) {
        last = null; // 旧数据损坏则忽略
      }
    }
    final applied = applyCooling(
        current: current, last: last, now: now,
        priceMovePercent: priceMovePercent);
    if (identical(applied, current)) {
      await prefs.setString(key, jsonEncode({
        'trend': current.trend.name,
        'signal': current.signal.name,
        'score': current.score,
        'at': current.updatedAt.millisecondsSinceEpoch,
      }));
    }
    result.add(TradeSuggestion(
      kind: applied.kind, label: applied.label,
      trend: applied.trend, signal: applied.signal,
      score: applied.score, reasons: reasonsFor(applied),
      profitRate: applied.profitRate, updatedAt: applied.updatedAt,
    ));
  }

  // 紧急度排序：riskAlert 最高，insufficient 最低（枚举声明顺序即紧急度顺序）。
  result.sort((a, b) => a.signal.index.compareTo(b.signal.index));
  return result;
});
