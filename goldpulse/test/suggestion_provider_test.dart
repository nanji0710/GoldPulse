// test/suggestion_provider_test.dart
// suggestionsProvider 组合持仓汇总 + DB 行情序列 → 实时建议列表的测试。
// 注：brief 原用 tester.context.read（widget 级），但 Flutter 3.44.8 的 WidgetTester
// 无 context getter，改用代码库既有约定 ProviderContainer(overrides:) 注入假 dao/summaries。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/state/asset_provider.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/state/suggestion_provider.dart';
import 'package:goldpulse/services/signal_engine.dart';
import 'package:goldpulse/database/price_dao.dart';

/// 假 PriceDao：返回固定 recent 序列（time DESC）。
class _FakePriceDao extends PriceDao {
  final Map<String, List<GoldPrice>> byCode;
  _FakePriceDao(this.byCode);
  @override
  Future<List<GoldPrice>> recent(String code, {int limit = 500}) async =>
      byCode[code] ?? const [];
}

void main() {
  // 构造 60 个点（i=0 为最旧，升序），recent 需 DESC 交给调用方 .reversed。
  List<GoldPrice> asc(int n, double start, double step) => [
        for (var i = 0; i < n; i++)
          GoldPrice(code: 'CZB-JCJ', price: start + i * step,
              change: step, percent: step / (start + i * step) * 100,
              preClose: 880, time: 1000 + i)
      ];

  test('无持仓 → 空列表', () async {
    final container = ProviderContainer(overrides: [
      typeSummariesProvider.overrideWith((ref) async => const []),
      priceDaoProvider.overrideWithValue(_FakePriceDao({})),
    ]);
    addTearDown(container.dispose);
    final list = await container.read(suggestionsProvider.future);
    expect(list, isEmpty);
  });

  test('持仓且趋势数据充足 → 生成建议（浙商买入）', () async {
    final summaries = [
      const TypeAssetSummary(
        kind: 'accumulation', label: '浙商积存金',
        totalGrams: 50, totalCost: 45000, avgCost: 900,
        currentPrice: 899, preClose: 895,
        floatingProfit: -50, todayProfit: 200, cumulativeProfit: -50,
        holdingCount: 1,
      ),
    ];
    // asc(60, 880, 0.3) 升序 [880..897.7] → reversed DESC → provider 内 .reversed 复原升序，
    // 再 append currentPrice 899：first=880、last=899 → 窗口 +2.16% → 趋势 up。
    final dao = _FakePriceDao({
      'CZB-JCJ': asc(60, 880, 0.3).reversed.toList(), // DESC
    });
    final container = ProviderContainer(overrides: [
      typeSummariesProvider.overrideWith((ref) async => summaries),
      priceDaoProvider.overrideWithValue(dao),
    ]);
    addTearDown(container.dispose);
    final list = await container.read(suggestionsProvider.future);
    expect(list, hasLength(1));
    // 实测：窗口 +2.16%（首 880 → 末 899）→ 趋势 up；今天 +0.45%；亏损 -0.11% → hold（-5~5% 档）。
    expect(list.single.signal, TradeSignal.hold);
  });

  test('深度亏损 → riskAlert', () async {
    final summaries = [
      const TypeAssetSummary(
        kind: 'accumulation', label: '浙商积存金',
        totalGrams: 50, totalCost: 50000, avgCost: 1000,
        currentPrice: 820, preClose: 830,
        floatingProfit: -9000, todayProfit: -500, cumulativeProfit: -9000,
        holdingCount: 1,
      ),
    ];
    // asc(60, 900, -1.5) 升序 [900..811.5] → reversed DESC → provider 内 .reversed 复原升序，
    // 再 append currentPrice 820：first=900、last=820 → 窗口 -8.9% → 趋势 down。
    final dao = _FakePriceDao({
      'CZB-JCJ': asc(60, 900, -1.5).reversed.toList(), // 窗口下跌
    });
    final container = ProviderContainer(overrides: [
      typeSummariesProvider.overrideWith((ref) async => summaries),
      priceDaoProvider.overrideWithValue(dao),
    ]);
    addTearDown(container.dispose);
    final list = await container.read(suggestionsProvider.future);
    // 收益率 -18% ≤ -15 → riskAlert（趋势 down 亦符合）。
    expect(list.single.signal, TradeSignal.riskAlert);
  });

  test('实时价格变化 → 建议内容更新（非仅时间戳）', () async {
    // 同一持仓（50g、成本 45000、均价 900），仅实时价不同：
    // 899 → 浮亏 -0.11% → hold；760 → 浮亏 -15.6% → riskAlert。
    TypeAssetSummary make(double price) => TypeAssetSummary(
        kind: 'accumulation', label: '浙商积存金',
        totalGrams: 50, totalCost: 45000, avgCost: 900,
        currentPrice: price, preClose: 895,
        floatingProfit: (price - 900) * 50,
        todayProfit: (price - 895) * 50,
        cumulativeProfit: (price - 900) * 50,
        holdingCount: 1);
    final dao = _FakePriceDao({
      'CZB-JCJ': asc(60, 890, 0.1).reversed.toList(), // DESC
    });
    Future<List<TradeSuggestion>> run(double price) async {
      final container = ProviderContainer(overrides: [
        typeSummariesProvider.overrideWith((ref) async => [make(price)]),
        priceDaoProvider.overrideWithValue(dao),
      ]);
      addTearDown(container.dispose);
      return container.read(suggestionsProvider.future);
    }

    final at899 = await run(899); // 窗口 +1.01% → up；浮亏 -0.11% → hold
    final at760 = await run(760); // 浮亏 -15.6% ≤ -15 → riskAlert（与趋势无关）
    expect(at899.single.signal, TradeSignal.hold);
    expect(at760.single.signal, TradeSignal.riskAlert);
  });
}
