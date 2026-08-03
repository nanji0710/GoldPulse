// test/widget_smoke_test.dart（本任务只含引导部分，后续任务追加）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/pages/onboarding_page.dart';

void main() {
  testWidgets('引导页渲染四步 + 跳过入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
    expect(find.text('金脉 GoldPulse'), findsWidgets);
    expect(find.text('跳过'), findsOneWidget);
  });
}
