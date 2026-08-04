// lib/widgets/chart.dart
// 价格走势图：折线（fl_chart LineChart）与 K 线（自绘 CustomPaint）两种形态。
// 注：fl_chart 0.69 不提供 CandlestickChart，故 K 线用 CustomPaint 渲染。
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';

class PriceLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final List<DateTime> times; // 与 spots 等长的采样时间（时间轴刻度 + 触摸气泡）
  final String Function(DateTime)? timeFormatter; // 默认 HH:mm，长周期可传 MM-DD
  const PriceLineChart({super.key, required this.spots, required this.times, this.timeFormatter});

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();
    final ys = spots.map((s) => s.y).toList();
    final minY = ys.reduce((a, b) => a < b ? a : b) * 0.995;
    final maxY = ys.reduce((a, b) => a > b ? a : b) * 1.005;
    final fmt = timeFormatter ?? _fmtTime;
    // 时间轴约 4-5 档刻度
    final tickEvery = (spots.length / 4).ceil().clamp(1, 1 << 30);
    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (_) => FlLine(
            color: AppTheme.divider.withValues(alpha: 0.4), strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 52,
            interval: (maxY - minY) / 4,
            getTitlesWidget: (v, meta) => Text(
              v.toStringAsFixed(1),
              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: tickEvery.toDouble(),
            getTitlesWidget: (v, meta) {
              final i = v.round();
              if (i < 0 || i >= times.length) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(fmt(times[i]),
                    style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
              );
            },
          ),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          color: AppTheme.gold,
          isCurved: true,
          barWidth: 2,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.gold.withValues(alpha: 0.25),
                AppTheme.gold.withValues(alpha: 0.02),
              ],
            ),
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppTheme.cardHighlight,
          tooltipRoundedRadius: 10, // fl_chart 0.69：圆角参数为 double
          getTooltipItems: (touched) => touched.map((t) {
            final i = t.x.round();
            final label = (i >= 0 && i < times.length) ? fmt(times[i]) : '';
            return LineTooltipItem(
              '${t.y.toStringAsFixed(2)} 元/g\n$label',
              const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()]),
            );
          }).toList(),
        ),
      ),
    ));
  }

  static String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
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

    // 水平网格线：divider 色细线，画在 K 线之前。
    final gridPaint = Paint()
      ..color = AppTheme.divider.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var g = 0; g < 4; g++) {
      final gy = size.height * g / 3;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    for (var i = 0; i < bars.length; i++) {
      final b = bars[i];
      final cx = step * i + step / 2;
      final color = b.close >= b.open ? upColor : downColor;
      // 影线：high -> low（涨跌柱均保留）
      canvas.drawLine(Offset(cx, y(b.high)), Offset(cx, y(b.low)), wickPaint..color = color);
      // 实体：open -> close
      // 涨（close >= open）红实心填充；跌（close < open）绿仅描边空心（色盲友好）。
      var top = y(math.max(b.open, b.close));
      var bottom = y(math.min(b.open, b.close));
      if (bottom - top < 1.0) bottom = top + 1.0; // 十字星至少 1px 高
      final bodyRect = Rect.fromLTRB(cx - bodyWidth / 2, top, cx + bodyWidth / 2, bottom);
      if (b.close >= b.open) {
        canvas.drawRect(bodyRect, Paint()..color = color);
      } else {
        canvas.drawRect(
          bodyRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CandlestickPainter oldDelegate) =>
      oldDelegate.bars != bars || oldDelegate.upColor != upColor || oldDelegate.downColor != downColor;
}
