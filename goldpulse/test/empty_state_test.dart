// test/empty_state_test.dart
// EmptyState 渲染与 action 回调单测。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/widgets/empty_state.dart';

void main() {
  testWidgets('渲染 icon/title/description/actionLabel', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.show_chart,
            title: '暂无历史数据',
            description: '行情轮询启动后自动积累数据',
            actionLabel: '去录入',
            onAction: () {},
          ),
        ),
      ),
    ));
    expect(find.byIcon(Icons.show_chart), findsOneWidget);
    expect(find.text('暂无历史数据'), findsOneWidget);
    expect(find.text('行情轮询启动后自动积累数据'), findsOneWidget);
    expect(find.text('去录入'), findsOneWidget);
  });

  testWidgets('点击 action 触发 onAction 回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.show_chart,
            title: '暂无数据',
            actionLabel: '重试',
            onAction: () => tapped++,
          ),
        ),
      ),
    ));
    await tester.tap(find.text('重试'));
    expect(tapped, 1);
  });

  testWidgets('未传 onAction 时不渲染按钮', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: EmptyState(icon: Icons.show_chart, title: '暂无数据'),
        ),
      ),
    ));
    expect(find.byType(FilledButton), findsNothing);
  });
}
