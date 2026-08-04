// lib/pages/home_page.dart
// 首页 Dashboard：Au9999 实时价格 + 持仓收益概览
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
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
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(priceProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (price != null)
              GoldCard(
                code: price.code,
                price: price.price,
                change: price.change,
                percent: price.percent,
                statusLabel: trading ? '交易中' : '休市',
                isTrading: trading,
              )
            else
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: Row(children: [
                  const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold),
                  ),
                  const SizedBox(width: 12),
                  Text('行情加载中…', style: Theme.of(context).textTheme.bodyMedium),
                ]),
              ),
            const SizedBox(height: 14),
            if (summary != null)
              ProfitCard(
                name: summary.holding.name,
                grams: summary.holding.amount,
                avgCost: summary.avgCost,
                floatingProfit: summary.floatingProfit,
                profitRate: summary.profitRate,
              )
            else
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: Text('点击「资产」录入你的第一笔持仓',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}
