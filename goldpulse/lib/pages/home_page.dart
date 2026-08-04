// lib/pages/home_page.dart
// 首页 Dashboard：Au9999/浙商积存金 实时价格 + 持仓收益概览 + 刷新倒计时
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/app.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/services/market_hours.dart';
import 'package:goldpulse/state/asset_provider.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/widgets/gold_card.dart';
import 'package:goldpulse/widgets/profit_card.dart';

/// 手动刷新：重启两个行情轮询（流启动即强拉一次最新价），
/// 供下拉刷新与加载态"点击重试"按钮使用。
Future<void> refreshAllQuotes(WidgetRef ref) async {
  ref.invalidate(priceProvider);
  ref.invalidate(accumulationPriceProvider);
  await Future.wait([
    ref.refresh(priceProvider.future),
    ref.refresh(accumulationPriceProvider.future),
  ]);
}

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
        onRefresh: () => refreshAllQuotes(ref),
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
                time: price.time,
                source: price.source,
                statusLabel: phaseLabel,
                statusHint: resumeHint,
                isTrading: trading,
              )
            else
              _loadingCard(context, onRetry: () => refreshAllQuotes(ref)),
            const SizedBox(height: 14),
            if (accPrice != null)
              GoldCard(
                code: '浙商积存金',
                price: accPrice.price,
                change: accPrice.change,
                percent: accPrice.percent,
                time: accPrice.time,
                source: accPrice.source,
                statusLabel: phaseLabel,
                statusHint: resumeHint,
                isTrading: trading,
              )
            else
              _loadingCard(context, onRetry: () => refreshAllQuotes(ref)),
            const SizedBox(height: 14),
            if (summary != null)
              ProfitCard(
                name: summary.holding.name,
                grams: summary.holding.amount,
                avgCost: summary.avgCost,
                floatingProfit: summary.floatingProfit,
                todayProfit: summary.todayProfit,
                cumulativeProfit: summary.cumulativeProfit,
                profitRate: summary.profitRate,
              )
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                ),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        size: 22, color: AppTheme.gold),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('还没有持仓，录入第一笔黄金持仓即可查看收益',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: () =>
                        ref.read(shellTabProvider.notifier).state = 2, // 资产页
                    child: const Text('去添加'),
                  ),
                ]),
              ),
            const SizedBox(height: 10),
            const _NextRefreshLine(),
          ],
        ),
      ),
    );
  }

  /// 加载态卡片：转圈 + 自动重试说明 + 手动重试按钮（直接强拉两个行情源）。
  Widget _loadingCard(BuildContext context, {required VoidCallback onRetry}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('正在获取行情… 失败将每 30 秒自动重试',
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ]),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 16, color: AppTheme.gold),
          label: const Text('点击重试'),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44), // 触控目标 ≥44px（无障碍）
          ),
        ),
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
    final remain = next.at.difference(DateTime.now());
    final remainText = remain.isNegative ? '刷新中…' : '${remain.inSeconds}s 后';
    String two(int v) => v.toString().padLeft(2, '0');
    final hhmmss = '${two(next.at.hour)}:${two(next.at.minute)}:${two(next.at.second)}';
    // 仅真实进入 30 秒快速重试（无缓存且拉取失败）才提示"获取失败"；
    // 正常模式（有数据）一律按配置间隔显示，避免误报。
    final freqText = nextRefreshFreqText(retrying: next.retrying, configured: interval);
    return Text(
      '$freqText · 下次 $hhmmss（$remainText）',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall,
    );
  }
}
