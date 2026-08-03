import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/services/market_hours.dart';
import 'package:goldpulse/state/asset_provider.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/widgets/gold_card.dart';
import 'package:goldpulse/widgets/profit_card.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = ref.watch(priceProvider).value;
    final summary = ref.watch(assetSummaryProvider).value;
    final trading = MarketHours.isTrading(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('金脉 GoldPulse')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (price != null)
          GoldCard(code: price.code, price: price.price, change: price.change, percent: price.percent)
        else
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('行情加载中…'))),
        const SizedBox(height: 12),
        if (summary != null)
          ProfitCard(grams: summary.holding.amount, avgCost: summary.avgCost,
              floatingProfit: summary.floatingProfit, profitRate: summary.profitRate)
        else
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('点击"资产"录入你的第一笔持仓'))),
        const SizedBox(height: 12),
        Text(trading ? '● 交易中' : '○ 休市', textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }
}
