// lib/widgets/chart.dart
// 价格走势图：折线（fl_chart LineChart）与 K 线（自绘 CustomPaint）两种形态。
// 注：fl_chart 0.69 不提供 CandlestickChart，故 K 线用 CustomPaint 渲染。
import 'dart:math' as math;
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

/// 单根 K 线的 OHLC 数据。
class CandlestickBar {
  final double open, high, low, close;
  const CandlestickBar({required this.open, required this.high, required this.low, required this.close});
}

/// 金价 K 线图：把连续价格序列按组聚合为 OHLC 柱，再用 CustomPaint 绘制。
/// 红涨绿跌：close >= open 用 [AppTheme.up]（红），否则 [AppTheme.down]（绿）。
class CandlestickChart extends StatelessWidget {
  final List<CandlestickBar> spots;
  const CandlestickChart({super.key, required this.spots});

  /// 把连续价格序列按 [groupSize] 个点一组聚合为 OHLC 柱。
  /// 每组的 open=组内首个、close=组内末个、high/low=组内极值。
  static List<CandlestickBar> aggregateBars({required List<double> prices, required int groupSize}) {
    final bars = <CandlestickBar>[];
    for (var i = 0; i < prices.length; i += groupSize) {
      final group = prices.sublist(i, (i + groupSize).clamp(0, prices.length));
      if (group.isEmpty) continue;
      bars.add(CandlestickBar(
        open: group.first,
        close: group.last,
        high: group.reduce((a, b) => a > b ? a : b),
        low: group.reduce((a, b) => a < b ? a : b),
      ));
    }
    return bars;
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CandlestickPainter(spots, upColor: AppTheme.up, downColor: AppTheme.down),
      child: const SizedBox.expand(),
    );
  }
}

class _CandlestickPainter extends CustomPainter {
  final List<CandlestickBar> bars;
  final Color upColor;   // 红涨
  final Color downColor; // 绿跌

  _CandlestickPainter(this.bars, {required this.upColor, required this.downColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    var minY = bars.first.low, maxY = bars.first.high;
    for (final b in bars) {
      if (b.low < minY) minY = b.low;
      if (b.high > maxY) maxY = b.high;
    }
    if (maxY - minY < 1e-9) {
      maxY += 1;
      minY -= 1;
    }
    // 上下各留 5% 边距，避免影线贴边。
    final range = maxY - minY;
    minY -= range * 0.05;
    maxY += range * 0.05;
    double y(double v) => size.height - (v - minY) / (maxY - minY) * size.height;

    final step = size.width / bars.length;
    final bodyWidth = math.min(step * 0.6, 24.0);
    final wickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, bodyWidth * 0.12);

    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final cx = step * i + step / 2;
      final color = b.close >= b.open ? upColor : downColor;
      // 影线：high -> low
      canvas.drawLine(Offset(cx, y(b.high)), Offset(cx, y(b.low)), wickPaint..color = color);
      // 实体：open -> close（红涨实体上沿为 open、下沿为 close）
      var top = y(math.max(b.open, b.close));
      var bottom = y(math.min(b.open, b.close));
      if (bottom - top < 1.0) bottom = top + 1.0; // 十字星至少 1px 高
      canvas.drawRect(
        Rect.fromLTRB(cx - bodyWidth / 2, top, cx + bodyWidth / 2, bottom),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) =>
      oldDelegate.bars != bars || oldDelegate.upColor != upColor || oldDelegate.downColor != downColor;
}
