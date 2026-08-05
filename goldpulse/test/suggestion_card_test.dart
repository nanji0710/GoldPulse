// test/suggestion_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/widgets/suggestion_card.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/services/signal_engine.dart';
import 'package:goldpulse/services/trend_analyzer.dart';

void main() {
  Widget wrap(Widget w) => MaterialApp(
      theme: AppTheme.theme(), home: Scaffold(body: Center(child: w)));

  final risk = TradeSuggestion(
      kind: 'accumulation', label: '浙商积存金',
      trend: TradeTrend.down, signal: TradeSignal.riskAlert,
      score: 30, reasons: const ['近期趋势走低', '亏损较大，建议重新评估仓位'],
      profitRate: -16, updatedAt: DateTime(2026, 8, 5, 10, 30));
  final hold = TradeSuggestion(
      kind: 'icbc', label: '工商积存金',
      trend: TradeTrend.up, signal: TradeSignal.hold,
      score: 70, reasons: const ['趋势向好', '收益率为正，继续持有'],
      profitRate: 8, updatedAt: DateTime(2026, 8, 5, 10, 30));

  testWidgets('加载态显示转圈', (tester) async {
    await tester.pumpWidget(wrap(const TradeSuggestionCard(
        suggestions: [], loading: true)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('空态提示录入持仓', (tester) async {
    await tester.pumpWidget(wrap(const TradeSuggestionCard(
        suggestions: [], loading: false)));
    expect(find.textContaining('录入持仓'), findsOneWidget);
  });

  testWidgets('渲染主建议：标题/品种/信号标签/置信度/理由', (tester) async {
    await tester.pumpWidget(wrap(TradeSuggestionCard(
        suggestions: [risk, hold])));
    expect(find.text('智能建议'), findsOneWidget);
    expect(find.text('浙商积存金'), findsOneWidget);
    expect(find.text('风险提醒'), findsOneWidget);
    expect(find.text('置信 30'), findsOneWidget);
    expect(find.text('近期趋势走低'), findsOneWidget);
    expect(find.text('亏损较大，建议重新评估仓位'), findsOneWidget);
    // 免责小字
    expect(find.textContaining('非投资建议'), findsOneWidget);
  });

  testWidgets('多品种：其余品种渲染一行摘要（含动作词）', (tester) async {
    await tester.pumpWidget(wrap(TradeSuggestionCard(
        suggestions: [risk, hold])));
    expect(find.text('工商积存金'), findsOneWidget);
    expect(find.textContaining('持有'), findsWidgets);
  });
}
