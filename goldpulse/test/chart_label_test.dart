// test/chart_label_test.dart
// 行情页折线图最高/最低点标签逻辑测试。
// 说明：fl_chart 通过 Canvas 绘制文本（TextPainter.paint），不生成 Text widget，
// 因此 find.text 无法匹配画布上的标签；改为对标签计算逻辑（minMaxPointsOf）做单测，
// 并做一次 pump 冒烟确保带标签的图表可正常渲染。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/widgets/chart.dart';

/// 构造 prices[i] 对应 FlSpot(i, prices[i])。
List<FlSpot> _spots(List<double> prices) =>
    [for (var i = 0; i < prices.length; i++) FlSpot(i.toDouble(), prices[i])];

void main() {
  group('minMaxPointsOf', () {
    test('空列表返回 null', () {
      expect(minMaxPointsOf(const []), isNull);
    });

    test('单个点返回 (0,0)，标签不重叠', () {
      expect(minMaxPointsOf(const [FlSpot(0, 5)]), (maxIndex: 0, minIndex: 0));
    });

    test('1..5 递增：最高在末尾、最低在开头', () {
      // 明确峰谷：prices 1,2,3,4,5
      final spots = _spots([1, 2, 3, 4, 5]);
      expect(minMaxPointsOf(spots), (maxIndex: 4, minIndex: 0));
    });

    test('峰谷在序列中部', () {
      // 3,5,2,4,3 → 峰 index1(5)、谷 index2(2)
      final spots = _spots([3, 5, 2, 4, 3]);
      expect(minMaxPointsOf(spots), (maxIndex: 1, minIndex: 2));
    });

    test('并列最高/最低取首次出现', () {
      // 4,6,6,1,1 → 峰 index1(首个 6)、谷 index3(首个 1)
      final spots = _spots([4, 6, 6, 1, 1]);
      expect(minMaxPointsOf(spots), (maxIndex: 1, minIndex: 3));
    });

    test('全部相等：max==min，取首次 (0,0)，只画一个点', () {
      final spots = _spots([7, 7, 7]);
      expect(minMaxPointsOf(spots), (maxIndex: 0, minIndex: 0));
    });
  });

  testWidgets('PriceLineChart 带最高/最低标签可正常渲染', (tester) async {
    final spots = _spots([1, 2, 3, 4, 5]);
    final times = [for (var i = 0; i < 5; i++) DateTime(2026, 1, 1, 9 + i)];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.theme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 240,
            child: PriceLineChart(spots: spots, times: times),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
