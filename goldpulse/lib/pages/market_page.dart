// lib/pages/market_page.dart
// 行情页：周期切换（1日/7日/30日）+ 金价走势折线图。
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/widgets/chart.dart';

class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});
  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage> {
  String _period = '7日';
  static const _periods = ['1日', '7日', '30日'];
  bool _showCandles = false;

  int _pointsFor() => switch (_period) { '1日' => 240, '7日' => 240, _ => 720 };
  // K 线聚合组大小：各周期都聚合成约 30 根 K 线，保证图形密度一致。
  int _groupSizeFor() => (_pointsFor() / 30).ceil();

  @override
  Widget build(BuildContext context) {
    final dao = ref.watch(priceDaoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('行情')),
      body: FutureBuilder(
        future: dao.recent('SGE-Au(T+D)', limit: _pointsFor()),
        builder: (context, snap) {
          final rows = snap.data ?? <GoldPrice>[];
          final spots = rows.reversed.indexed.map((e) => FlSpot(e.$1.toDouble(), e.$2.price)).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final p in _periods)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ChoiceChip(
                        label: Text(p),
                        selected: _period == p,
                        selectedColor: AppTheme.gold,
                        onSelected: (_) => setState(() => _period = p)),
                  ),
                const SizedBox(width: 16),
                ChoiceChip(
                    label: const Text('K线'),
                    selected: _showCandles,
                    selectedColor: AppTheme.gold,
                    onSelected: (v) => setState(() => _showCandles = v)),
              ]),
            ),
            Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('暂无历史数据，请稍后再来'))
                    : Padding(
                        padding: const EdgeInsets.all(16),
                        child: _showCandles
                            ? CandlestickChart(
                                spots: CandlestickChart.aggregateBars(
                                  prices: rows.reversed.map((e) => e.price).toList(),
                                  groupSize: _groupSizeFor(),
                                ),
                              )
                            : PriceLineChart(spots: spots))),
          ]);
        },
      ),
    );
  }
}
