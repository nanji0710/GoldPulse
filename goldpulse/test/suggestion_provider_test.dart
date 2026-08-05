// test/suggestion_provider_test.dart
// suggestionsProvider 组合持仓汇总 + DB 行情序列 → 建议列表（含冷却）的测试。
// 注：brief 原用 tester.context.read（widget 级），但 Flutter 3.44.8 的 WidgetTester
// 无 context getter，改用代码库既有约定 ProviderContainer(overrides:) 注入假 dao/summaries/prefs。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  // 冷却存储用 SharedPreferences：测试必须 mock 空初始值。
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 构造 60 个点（升序 880 → 899），recent 需 DESC。
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
    // 趋势向上（窗口 +2%），亏损 -0.11% → hold（-5~5% 档）。
    // 今天 percent = (899-895)/895 ≈ +0.45%。趋势 up，小幅盈亏 → hold。
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
    final dao = _FakePriceDao({
      'CZB-JCJ': asc(60, 900, -1.5).reversed.toList(), // 窗口下跌
    });
    final container = ProviderContainer(overrides: [
      typeSummariesProvider.overrideWith((ref) async => summaries),
      priceDaoProvider.overrideWithValue(dao),
    ]);
    addTearDown(container.dispose);
    final list = await container.read(suggestionsProvider.future);
    expect(list.single.signal, TradeSignal.riskAlert);
  });
}
