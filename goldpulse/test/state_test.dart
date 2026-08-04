// test/state_test.dart
// 资产汇总模型 + 品种级聚合数据层测试。
//   - AssetSummary.compute 纯计算口径（既有用例，保持不动）。
//   - typeSummariesProvider / totalAssetSummaryProvider：同品种合并克重与均价、
//     多品种分开、卖单进入累计收益、无行情 → currentPrice=null、total 线性合计。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/trade_dao.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/state/asset_provider.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'test_db.dart';

void main() {
  test('AssetSummary 由计算模块聚合', () {
    final s = AssetSummary.compute(
        currentPrice: 781.5, preClose: 780.0, amount: 501.2, totalCost: 310000);
    expect(s.currentValue, closeTo(391687.80, 0.01));
    expect(s.floatingProfit, closeTo(81687.80, 0.01));
    expect(s.avgCost, closeTo(618.515, 0.001));
    // 今日盈亏 = (现价 − 昨收) × 克重 = 1.5 × 501.2
    expect(s.todayProfit, closeTo(751.80, 0.01));
    // 无卖出交易时，累计收益退化为持仓收益
    expect(s.cumulativeProfit, closeTo(s.floatingProfit, 0.001));
  });

  group('typeSummariesProvider / totalAssetSummaryProvider', () {
    setUpAll(setUpTestDatabase); // 独立 FFI 数据库目录，避免并行 isolate 锁竞争
    setUp(() async {
      await AppDatabase.reset(); // 每个用例重建内存库
    });

    test('同品种合并克重与均价、多品种分开、total 线性合计', () async {
      final holdingDao = HoldingDao();
      final tradeDao = TradeDao();
      // 浙商两笔：30g@870、20g@880（totalCost / boughtCost 分别 26100、17600）；工商一笔 10g@890
      final h1Id = await holdingDao.insert(
          Holding(name: '浙商1', kind: 'accumulation', amount: 30, totalCost: 26100, boughtCost: 26100, createdAt: 1));
      await holdingDao.insert(
          Holding(name: '浙商2', kind: 'accumulation', amount: 20, totalCost: 17600, boughtCost: 17600, createdAt: 2));
      await holdingDao.insert(
          Holding(name: '工商', kind: 'icbc', amount: 10, totalCost: 8900, boughtCost: 8900, createdAt: 3));
      // 浙商卖单：10g@900 fee 36
      await tradeDao.insert(
          TradeRecord(holdingId: h1Id, type: 'sell', amount: 10, price: 900, fee: 36, time: 4));
      final container = ProviderContainer(overrides: [
        holdingDaoProvider.overrideWithValue(holdingDao),
        tradeDaoProvider.overrideWithValue(tradeDao),
        holdingsProvider.overrideWith((ref) => holdingDao.list()),
        accumulationPriceProvider.overrideWith((ref) => Stream.value(
            GoldPrice(code: 'CZB-JCJ', price: 900, change: 1, percent: 0.1, preClose: 890, time: 5))),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)), // 工商无行情
      ]);
      addTearDown(container.dispose);
      // 先让行情流发出首值并缓存（Stream.value 为异步发射），
      // 否则 typeSummariesProvider 内 ref.watch(...).valueOrNull 读到的是 null。
      await container.read(accumulationPriceProvider.future);
      await container.read(icbcPriceProvider.future);
      final list = await container.read(typeSummariesProvider.future);
      // 浙商：totalGrams=50、totalCost=43700、avgCost=874.0；卖单净得=10*900-36=8964。
      // 无卖出扣成本场景 boughtCost = totalCost = 43700，累计收益用 boughtCost 口径。
      final czb = list.firstWhere((t) => t.kind == 'accumulation');
      expect(czb.totalGrams, 50);
      expect(czb.avgCost, closeTo(874.0, 0.001));
      expect(czb.cumulativeProfit, closeTo(8964 + 900 * 50 - 43700, 0.001));
      // 工商无行情 → currentPrice null
      final icbc = list.firstWhere((t) => t.kind == 'icbc');
      expect(icbc.currentPrice, isNull);
      expect(icbc.floatingProfit, 0);
      expect(icbc.todayProfit, 0);
      expect(icbc.cumulativeProfit, 0);
      // 多品种分开：各成一个 TypeAssetSummary
      expect(list.map((t) => t.kind), ['accumulation', 'icbc']);
      final total = await container.read(totalAssetSummaryProvider.future);
      expect(total!.floatingProfit, list.fold(0.0, (s, t) => s + t.floatingProfit));
      expect(total.todayProfit, list.fold(0.0, (s, t) => s + t.todayProfit));
      expect(total.cumulativeProfit, list.fold(0.0, (s, t) => s + t.cumulativeProfit));
      expect(total.totalGrams, 60);
      expect(total.totalCost, 52600);
      expect(total.holdingCount, 3);
    });

    test('无持仓 → typeSummaries 空、total 为 null', () async {
      final container = ProviderContainer(overrides: [
        holdingDaoProvider.overrideWithValue(HoldingDao()),
        tradeDaoProvider.overrideWithValue(TradeDao()),
        holdingsProvider.overrideWith((ref) async => <Holding>[]),
      ]);
      addTearDown(container.dispose);
      expect(await container.read(typeSummariesProvider.future), isEmpty);
      expect(await container.read(totalAssetSummaryProvider.future), isNull);
    });
  });
}
