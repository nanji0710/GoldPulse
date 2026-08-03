// test/startup_gate_test.dart
// I6 回归测试：启动门控——无持仓进引导页，有持仓进主界面。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/app.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/state/price_provider.dart';

void main() {
  testWidgets('无持仓启动进入引导页', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        holdingsProvider.overrideWith((ref) => Future.value(const <Holding>[])),
        priceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: StartupGate()),
    ));
    await tester.pump();
    expect(find.text('跳过'), findsOneWidget); // OnboardingPage 特征
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets('有持仓启动进入主界面', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        holdingsProvider.overrideWith((ref) => Future.value([
          Holding(name: 'Au9999', kind: 'au9999', amount: 100, totalCost: 60000, createdAt: 1),
        ])),
        priceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: StartupGate()),
    ));
    await tester.pump();
    expect(find.byType(MainShell), findsOneWidget);
    expect(find.text('跳过'), findsNothing);
  });
}
