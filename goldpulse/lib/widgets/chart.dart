// lib/widgets/chart.dart
// 价格走势折线图：封装 fl_chart LineChart，金色曲线，平滑展示。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';

class PriceLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  const PriceLineChart({super.key, required this.spots});

  @override
  Widget build(BuildContext context) {
    return LineChart(LineChartData(
      minY: spots.isEmpty ? 0 : (spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) * 0.99),
      maxY: spots.isEmpty ? 1 : (spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.01),
      lineBarsData: [LineChartBarData(spots: spots, color: AppTheme.gold, isCurved: true, dotData: const FlDotData(show: false))],
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: const FlTitlesData(leftTitles: AxisTitles(), topTitles: AxisTitles(), rightTitles: AxisTitles()),
    ));
  }
}
