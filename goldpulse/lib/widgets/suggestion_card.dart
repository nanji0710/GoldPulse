// lib/widgets/suggestion_card.dart
// 首页顶部「智能建议」小卡片：主建议 + 其余品种摘要 + 免责。
// 数据来自 suggestionsProvider（已按紧急度排序，首位为主建议）。
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/services/signal_engine.dart';
import 'package:goldpulse/services/trend_analyzer.dart';

/// 信号 → 展示动作词。
String signalLabel(TradeSignal s) => switch (s) {
      TradeSignal.hold => '持有',
      TradeSignal.buy => '买入',
      TradeSignal.takeProfit => '止盈',
      TradeSignal.reduce => '减仓',
      TradeSignal.watch => '观望',
      TradeSignal.riskAlert => '风险提醒',
      TradeSignal.insufficient => '待积累',
    };

/// 信号 → 主色（买入偏多/持有金/止盈减仓风险红/观望灰）。
Color signalColor(TradeSignal s) => switch (s) {
      TradeSignal.buy => AppTheme.down,
      TradeSignal.hold => AppTheme.gold,
      TradeSignal.takeProfit ||
      TradeSignal.reduce ||
      TradeSignal.riskAlert => AppTheme.up,
      TradeSignal.watch || TradeSignal.insufficient => AppTheme.textSecondary,
    };

/// 趋势 → 箭头与颜色（红涨绿跌）。
(String, Color) _trendArrow(TradeTrend t) => switch (t) {
      TradeTrend.up => ('↗', AppTheme.up),
      TradeTrend.down => ('↘', AppTheme.down),
      TradeTrend.flat => ('→', AppTheme.textSecondary),
      TradeTrend.insufficient => ('·', AppTheme.textSecondary),
    };

/// HH:mm 时间格式化（与项目 market_page._fmtHHmm 风格一致）。
String _fmtHHmm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String _two(int v) => v.toString().padLeft(2, '0');

class TradeSuggestionCard extends StatelessWidget {
  final List<TradeSuggestion> suggestions;
  final bool loading;
  const TradeSuggestionCard({
    super.key,
    required this.suggestions,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF26354F), AppTheme.cardHighlight]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: loading
          ? const Row(children: [
              SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold)),
              SizedBox(width: 12),
              Text('正在分析行情…',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ])
          : suggestions.isEmpty
              ? _empty()
              : _content(suggestions),
    );
  }

  Widget _empty() {
    return const Row(children: [
      Icon(Icons.balance_outlined, size: 20, color: AppTheme.goldSoft),
      SizedBox(width: 10),
      Expanded(
        child: Text('录入持仓后，结合行情趋势动态生成买卖建议',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
      ),
    ]);
  }

  Widget _content(List<TradeSuggestion> list) {
    final main = list.first;
    final rest = list.skip(1).toList();
    final (arrow, trendColor) = _trendArrow(main.trend);
    final c = signalColor(main.signal);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 头部：图标 + 标题 + 置信度
      Row(children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: AppTheme.gold.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.insights, size: 15, color: AppTheme.gold),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('智能建议',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('置信 ${main.score.round()}',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.gold)),
        ),
      ]),
      const SizedBox(height: 10),
      // 主建议：品种 + 趋势 + 信号 chip
      Row(children: [
        Text(main.label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(arrow, style: TextStyle(fontSize: 14, color: trendColor)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(signalLabel(main.signal),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ),
      ]),
      const SizedBox(height: 8),
      // 理由列表
      for (final r in main.reasons)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(
                    color: AppTheme.goldSoft, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(r,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
            ),
          ]),
        ),
      // 其余品种摘要
      if (rest.isNotEmpty) ...[
        const SizedBox(height: 6),
        for (final s in rest)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              Text(s.label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              const Text('→', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              const SizedBox(width: 6),
              Text(signalLabel(s.signal),
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: signalColor(s.signal))),
            ]),
          ),
      ],
      const SizedBox(height: 8),
      // 底部：时间戳 + 免责 + 冷却
      Row(children: [
        Expanded(
          child: Text('更新于 ${_fmtHHmm(main.updatedAt)} · 仅供参考，非投资建议',
              style: TextStyle(fontSize: 10, color: AppTheme.offline)),
        ),
        Text('24h 内不重复提醒',
            style: TextStyle(fontSize: 10, color: AppTheme.offline)),
      ]),
    ]);
  }
}
