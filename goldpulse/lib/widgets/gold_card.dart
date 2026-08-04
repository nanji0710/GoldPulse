// lib/widgets/gold_card.dart
// 首页主卡片：Au9999 实时价格（渐变背景 + 状态胶囊 + 红涨绿跌）
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/utils/formatters.dart';

class GoldCard extends StatelessWidget {
  final String code;
  final double price;
  final double change;
  final double percent;
  final int time; // 行情时间戳（毫秒），用于显示更新时间
  final String source; // 数据源标签（京东/东方财富/Au9999 参考/缓存），空则不显示
  final String? statusLabel; // 如 "交易中" / "午间休市"
  final String? statusHint;  // 如 "13:30 恢复交易"
  final bool? isTrading;

  const GoldCard({
    super.key,
    required this.code,
    required this.price,
    required this.change,
    required this.percent,
    required this.time,
    this.source = '',
    this.statusLabel,
    this.statusHint,
    this.isTrading,
  });

  @override
  Widget build(BuildContext context) {
    final up = change >= 0;
    final color = up ? AppTheme.up : AppTheme.down;
    final trading = isTrading ?? true;
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.goldSoft.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 头部：代码 + 状态胶囊
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(code,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 15, color: AppTheme.textSecondary, letterSpacing: 0.5)),
              if (statusLabel != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: trading
                          ? AppTheme.gold.withValues(alpha: 0.14)
                          : AppTheme.divider.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: trading ? AppTheme.gold : AppTheme.offline,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(statusLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: trading ? AppTheme.gold : AppTheme.textSecondary,
                                fontWeight: FontWeight.w600)),
                      ),
                      if (statusHint != null) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(statusHint!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppTheme.textSecondary)),
                        ),
                      ],
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // 大数字价格
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(fmtPrice(price),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: AppTheme.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 6),
              Text('元/g',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          // 涨跌行（胶囊底色）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${arrow(change)} ${fmtAmount(change.abs())}  (${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 15,
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(height: 8),
          // 数据更新时间（来自行情拉取时间戳）+ 数据源标签，便于确认新鲜度与来源
          Text(
            '更新于 ${_timeLabel(DateTime.fromMillisecondsSinceEpoch(time))}'
            '${source.isEmpty ? '' : ' · 数据源：$source'}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 11),
          ),
        ]),
      ),
    );
  }

  static String _timeLabel(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
