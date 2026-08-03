import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/utils/formatters.dart';

class GoldCard extends StatelessWidget {
  final String code;
  final double price;
  final double change;
  final double percent;
  const GoldCard({super.key, required this.code, required this.price, required this.change, required this.percent});

  @override
  Widget build(BuildContext context) {
    final up = change >= 0;
    final color = up ? AppTheme.up : AppTheme.down;
    return Card(
      color: AppTheme.card,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(code, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(fmtPrice(price),
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: AppTheme.textPrimary, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 4),
              Text('元/g', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text('${arrow(change)} ${fmtAmount(change.abs())}  (${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(2)}%)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ]),
      ),
    );
  }
}
