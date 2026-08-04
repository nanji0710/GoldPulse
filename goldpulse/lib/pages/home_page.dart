// lib/pages/home_page.dart
// 首页 Dashboard：Au9999/浙商积存金 实时价格 + 持仓收益概览 + 刷新倒计时
import 'dart:async';

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
    final summary = ref.watch(assetSummaryProvider).value;
    final price = ref.watch(priceProvider).value;                 // Au9999
    final accPrice = ref.watch(accumulationPriceProvider).value;  // 浙商积存金
    final now = DateTime.now();
    final trading = MarketHours.isTrading(now);
    final phaseLabel = MarketHours.label(now);
    final resumeHint = MarketHours.resumeHint(now);
    return Scaffold(
      appBar: AppBar(title: const Text('金脉 GoldPulse')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(priceProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // 双行情卡：Au9999 + 浙商积存金 同时展示
            if (price != null)
              GoldCard(
                code: 'Au9999',
                price: price.price,
                change: price.change,
                percent: price.percent,
                statusLabel: phaseLabel,
                statusHint: resumeHint,
                isTrading: trading,
              )
            else
              _loadingCard(context),
            const SizedBox(height: 14),
            if (accPrice != null)
              GoldCard(
                code: '浙商积存金',
                price: accPrice.price,
                change: accPrice.change,
                percent: accPrice.percent,
                statusLabel: phaseLabel,
                statusHint: resumeHint,
                isTrading: trading,
              )
            else
              _loadingCard(context),
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
            const SizedBox(height: 10),
            const _NextRefreshLine(),
          ],
        ),
      ),
    );
  }

  Widget _loadingCard(BuildContext context) {
    return Container(
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
        Text('行情加载中… 若无数据请下拉重试',
            style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }
}

/// 刷新频率 + 下次刷新时间（秒级倒计时）。
class _NextRefreshLine extends ConsumerStatefulWidget {
  const _NextRefreshLine();
  @override
  ConsumerState<_NextRefreshLine> createState() => _NextRefreshLineState();
}

class _NextRefreshLineState extends ConsumerState<_NextRefreshLine> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = ref.watch(nextRefreshProvider);
    final interval = ref.watch(refreshIntervalProvider).valueOrNull;
    if (next == null || interval == null) return const SizedBox.shrink();
    final remain = next.difference(DateTime.now());
    final remainText = remain.isNegative ? '刷新中…' : '${remain.inSeconds}s 后';
    String two(int v) => v.toString().padLeft(2, '0');
    final hhmmss = '${two(next.hour)}:${two(next.minute)}:${two(next.second)}';
    // 快速重试模式（无数据时 30s 一轮）与正常刷新模式（配置间隔）文案区分，
    // 避免"每 2 分钟刷新"与"30s 后"同时出现的困惑。
    final fastRetry = interval > const Duration(seconds: 30) && remain < interval;
    final freqText = fastRetry
        ? '行情获取失败，每 30 秒自动重试'
        : '每 ${interval.inSeconds ~/ 60 > 0 ? '${interval.inMinutes} 分钟' : '${interval.inSeconds} 秒'}刷新';
    return Text(
      '$freqText · 下次 $hhmmss（$remainText）',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}
