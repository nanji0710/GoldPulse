// lib/widgets/profit_card.dart
// 首页收益卡片：持仓概览 + 浮动收益（红涨绿跌）
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/utils/formatters.dart';

class ProfitCard extends StatelessWidget {
  final String name;
  final double grams;
  final double avgCost;
  final double floatingProfit;
  final double profitRate;
  const ProfitCard({
    super.key,
    this.name = '浙商积存金',
    required this.grams,
    required this.avgCost,
    required this.floatingProfit,
    required this.profitRate,
  });

  @override
  Widget build(BuildContext context) {
    final up = floatingProfit >= 0;
    final color = up ? AppTheme.up : AppTheme.down;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 标题行：名称 + 收益率徽标
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('${up ? '+' : ''}${profitRate.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 持仓明细
          Row(
            children: [
              _Metric(label: '持仓', value: '${fmtGrams(grams)}g'),
              const SizedBox(width: 24),
              _Metric(label: '平均成本', value: '${fmtPrice(avgCost)} 元/g'),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 14),
          // 收益大数字
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('收益',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${arrow(floatingProfit)} ${fmtAmount(floatingProfit.abs())} 元',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 26,
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 15,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ],
    );
  }
}
