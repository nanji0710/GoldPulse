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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 头部：图标 + 标题
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
        const Text('智能建议',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      // 每个持仓品种一个完整建议块（品种 + 趋势 + 置信度 + 信号 + 理由）
      for (var i = 0; i < list.length; i++) ...[
        if (i > 0) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: AppTheme.divider.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
        ],
        _kindBlock(list[i]),
      ],
      const SizedBox(height: 8),
      // 底部：更新时间戳 + 免责（无冷却，随行情刷新实时更新）
      Text('更新于 ${_fmtHHmm(list.first.updatedAt)} · 仅供参考，非投资建议',
          style: TextStyle(fontSize: 10, color: AppTheme.offline)),
    ]);
  }

  /// 单个品种的完整建议块。
  Widget _kindBlock(TradeSuggestion s) {
    final (arrow, trendColor) = _trendArrow(s.trend);
    final c = signalColor(s.signal);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(s.label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(arrow, style: TextStyle(fontSize: 14, color: trendColor)),
        const Spacer(),
        Text('置信 ${s.score.round()}',
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.gold)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(signalLabel(s.signal),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ),
      ]),
      const SizedBox(height: 6),
      // 理由列表
      for (final r in s.reasons)
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
    ]);
  }
}
