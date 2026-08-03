// lib/widgets/holding_list_tile.dart
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/utils/formatters.dart';
import '../services/calculator.dart';

class HoldingListTile extends StatelessWidget {
  final Holding holding;
  const HoldingListTile({super.key, required this.holding});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.card,
      child: ListTile(
        title: Text(holding.name),
        subtitle: Text('${fmtGrams(holding.amount)}g · 成本 ${fmtPrice(Calculator.avgCost(holding.totalCost, holding.amount))} 元/g'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
