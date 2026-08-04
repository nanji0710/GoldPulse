// test/gold_card_test.dart
// I2 回归测试：GoldCard 涨跌幅前缀正负号必须正确，
// 下跌日不得出现 (+-1.23%) 的双重负号。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/widgets/gold_card.dart';

void main() {
  testWidgets('下跌日显示单个负号（无 (+-) 双重符号）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GoldCard(code: 'Au9999', price: 780.20, change: -1.23, percent: -0.16, time: 1000)),
    ));
    final text = tester.widget<Text>(find.textContaining('%')).data!;
    expect(text.contains('(-0.16%)'), isTrue);
    expect(text.contains('+-'), isFalse);
    expect(text.contains('(+'), isFalse);
  });

  testWidgets('上涨日正确显示正号', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GoldCard(code: 'Au9999', price: 780.20, change: 1.23, percent: 0.16, time: 1000)),
    ));
    final text = tester.widget<Text>(find.textContaining('%')).data!;
    expect(text.contains('(+0.16%)'), isTrue);
  });

  testWidgets('平盘显示正号（+0.00%）', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GoldCard(code: 'Au9999', price: 780.20, change: 0, percent: 0, time: 1000)),
    ));
    final text = tester.widget<Text>(find.textContaining('%')).data!;
    expect(text.contains('(+0.00%)'), isTrue);
  });

  testWidgets('显示数据源标签', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GoldCard(code: 'Au9999', price: 780.20, change: 1.23, percent: 0.16, time: 1000, source: '东方财富')),
    ));
    expect(find.textContaining('数据源：东方财富'), findsOneWidget);
  });

  testWidgets('未传数据源时不显示标签', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: GoldCard(code: 'Au9999', price: 780.20, change: 1.23, percent: 0.16, time: 1000)),
    ));
    expect(find.textContaining('数据源'), findsNothing);
  });
}
