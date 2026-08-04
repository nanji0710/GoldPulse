// lib/widgets/chart.dart
// 价格走势图：折线（fl_chart LineChart）与 K 线（自绘 CustomPaint）两种形态。
// 注：fl_chart 0.69 不提供 CandlestickChart，故 K 线用 CustomPaint 渲染。
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/utils/formatters.dart';

/// 找出最高（maxY）与最低（minY）数据点在 [spots] 中的下标；
/// 多个点并列时取首次出现。空列表返回 null，单个点返回 (0,0)。
({int maxIndex, int minIndex})? minMaxPointsOf(List<FlSpot> spots) {
  if (spots.isEmpty) return null;
  var maxIndex = 0, minIndex = 0;
  for (var i = 1; i < spots.length; i++) {
    final y = spots[i].y;
    if (y > spots[maxIndex].y) maxIndex = i;
    if (y < spots[minIndex].y) minIndex = i;
  }
  return (maxIndex: maxIndex, minIndex: minIndex);
}

class PriceLineChart extends StatelessWidget {
  /// [spots] 的 x 为「距 [periodStart] 的分钟数」（时间轴按日历周期定位，
  /// 无数据的时段也保留空档与刻度标签）。[spanMinutes] 为周期总跨度：
  /// 1日=1440（00:00–24:00）、7日=10080、30日=43200。
  final List<FlSpot> spots;
  final DateTime periodStart;
  final int spanMinutes;
  final String Function(DateTime)? timeFormatter; // 默认 HH:mm，长周期可传 MM-DD
  const PriceLineChart({
    super.key,
    required this.spots,
    required this.periodStart,
    required this.spanMinutes,
    this.timeFormatter,
  });

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();
    final minMax = minMaxPointsOf(spots);
    final ys = spots.map((s) => s.y).toList();
    final minY = ys.reduce((a, b) => a < b ? a : b) * 0.995;
    final maxY = ys.reduce((a, b) => a > b ? a : b) * 1.005;
    final fmt = timeFormatter ?? _fmtTime;
    // 时间轴约 5 档刻度：按周期总跨度均匀分布（无数据的时段同样显示日期/时间标签）。
    final tickEvery = (spanMinutes / 5).ceil().clamp(1, 1 << 30);
    return LineChart(LineChartData(
      minX: 0,
      maxX: spanMinutes.toDouble(),
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
              // v = 距周期起点的分钟数；无数据时段同样显示对应时间/日期标签。
              final time = periodStart.add(Duration(minutes: v.round()));
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(fmt(time),
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
          // 最高/最低点画金色强调点 + 金额标签；其余点不画。
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, _, index) {
              final mm = minMax;
              if (mm == null) {
                return FlDotCirclePainter(
                    color: Colors.transparent, radius: 0);
              }
              if (index == mm.maxIndex) {
                return _ExtremaDotPainter(
                  label: fmtPrice(spot.y),
                  dotColor: AppTheme.gold,
                  textColor: AppTheme.gold,
                  above: true,
                );
              }
              if (index == mm.minIndex) {
                return _ExtremaDotPainter(
                  label: fmtPrice(spot.y),
                  dotColor: AppTheme.gold,
                  textColor: AppTheme.gold,
                  above: false,
                );
              }
              // 防御分支：非极值点不可见。
              return FlDotCirclePainter(
                  color: Colors.transparent, radius: 0);
            },
          ),
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
            // t.x = 距周期起点的分钟数 → 换算回真实时间。
            final time = periodStart.add(Duration(minutes: t.x.round()));
            return LineTooltipItem(
              '${t.y.toStringAsFixed(2)} 元/g\n${fmt(time)}',
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

/// 最高/最低点的强调点：金色发光圆点 + fmtPrice 金额标签。
/// [above] 为 true 时标签画在点上方（最高点），否则画在下方（最低点），避免与坐标轴重叠。
class _ExtremaDotPainter extends FlDotPainter {
  final String label;
  final Color dotColor;
  final Color textColor;
  final bool above;

  static const double _radius = 3;
  static const double _fontSize = 12; // 与主题 labelSmall 一致
  static const double _gap = 3;

  const _ExtremaDotPainter({
    required this.label,
    required this.dotColor,
    required this.textColor,
    required this.above,
  });

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    // 轻微辉光：柔化的金色光晕。
    canvas.drawCircle(
      offsetInCanvas,
      _radius + 3,
      Paint()
        ..color = dotColor.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // 强调圆点。
    canvas.drawCircle(offsetInCanvas, _radius, Paint()..color = dotColor);

    // 金额标签：水平居中，最高点在上、最低点在下。
    // 自适应：最高/最低点贴近图表左右/上下边缘时，把标签收进裁剪范围内，避免被裁掉。
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: _fontSize,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
          shadows: const [
            Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final clip = canvas.getLocalClipBounds();
    final maxDx = (clip.right - tp.width).clamp(clip.left, clip.right);
    final maxDy = (clip.bottom - tp.height).clamp(clip.top, clip.bottom);
    final dx = (offsetInCanvas.dx - tp.width / 2).clamp(clip.left, maxDx);
    final dy = (above
            ? offsetInCanvas.dy - _radius - _gap - tp.height
            : offsetInCanvas.dy + _radius + _gap)
        .clamp(clip.top, maxDy);
    tp.paint(canvas, Offset(dx.toDouble(), dy.toDouble()));
  }

  @override
  Size getSize(FlSpot spot) => const Size(_radius * 2, _radius * 2);

  @override
  Color get mainColor => dotColor;

  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) => b;

  @override
  List<Object?> get props => [label, dotColor, textColor, above];
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
