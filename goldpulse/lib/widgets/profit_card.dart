import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/utils/formatters.dart';

class ProfitCard extends StatelessWidget {
  final double grams;
  final double avgCost;
  final double floatingProfit;
  final double profitRate;
  const ProfitCard({super.key, required this.grams, required this.avgCost, required this.floatingProfit, required this.profitRate});

  @override
  Widget build(BuildContext context) {
    final up = floatingProfit >= 0;
    final color = up ? AppTheme.up : AppTheme.down;
    return Card(
      color: AppTheme.card,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('浙商积存金', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text('${fmtGrams(grams)}g', style: Theme.of(context).textTheme.titleMedium),
          Text('成本 ${fmtPrice(avgCost)} 元/g', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text('收益 ${arrow(floatingProfit)} ${fmtAmount(floatingProfit.abs())} 元  (${profitRate.toStringAsFixed(1)}%)',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color)),
        ]),
      ),
    );
  }
}
