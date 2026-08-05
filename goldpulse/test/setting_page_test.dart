// test/setting_page_test.dart
// 设置页「常驻通知栏」区块：进入页面时从 SharedPreferences 恢复已存配置。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/pages/setting_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('进入设置页恢复已存常驻通知栏配置', (tester) async {
    SharedPreferences.setMockInitialValues({
      'notificationBarEnabled': true,
      'notificationBarKind': 'icbc',
      'notificationBarIntervalSeconds': 30,
      'notificationBarMetrics':
          '["avgCost","todayProfit","cumulativeProfit","floatingProfit"]',
    });
    await tester.pumpWidget(ProviderScope(
      child: const MaterialApp(home: SettingPage()),
    ));
    // initState 触发 loadFromPrefs（异步）：等恢复完成后的重建
    await tester.pump();
    await tester.pump();

    // 开关恢复为开
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue);
    // 品种/频率 dropdown 随配置重建（ValueKey 绑定 provider 状态）
    expect(find.byKey(const ValueKey('bar-kind-icbc')), findsOneWidget);
    expect(find.byKey(const ValueKey('bar-interval-30')), findsOneWidget);
    // 指标 chip 选中态与恢复的 metrics 一致
    ChoiceChip chip(String label) => tester.widget<ChoiceChip>(
        find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip)));
    expect(chip('累计收益').selected, isTrue);
    expect(chip('收益率').selected, isFalse);
  });
}
