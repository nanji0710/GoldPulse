// test/widget_smoke_test.dart（引导 + 首页，后续任务追加）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/pages/asset_page.dart';
import 'package:goldpulse/pages/home_page.dart';
import 'package:goldpulse/pages/market_page.dart';
import 'package:goldpulse/pages/onboarding_page.dart';
import 'package:goldpulse/state/asset_provider.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/state/price_provider.dart';

// 用 override 注入固定行情（单一时刻，避免轮询死循环）
final _fixedPriceStream = Stream<GoldPrice?>.value(
    GoldPrice(code: 'Au9999', price: 780.20, change: 3.50, percent: 0.45, preClose: 776.70, time: 1));

void main() {
  testWidgets('引导页渲染四步 + 跳过入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
    expect(find.text('金脉 GoldPulse'), findsWidgets);
    expect(find.text('跳过'), findsOneWidget);
  });

  testWidgets('首页展示 Au9999 大数字价格与涨跌', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        priceProvider.overrideWith((ref) => _fixedPriceStream),
        // 测试环境无真实 dio：各积存金轮询直接给空流，避免触发 UnimplementedError。
        accumulationPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        minshengPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    await tester.pump();
    expect(find.text('780.20'), findsOneWidget);
    expect(find.text('Au9999'), findsOneWidget);
  });

  testWidgets('资产页空状态提示录入', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // 测试环境无真实 dio：民生积存金轮询直接给空流，避免触发 UnimplementedError。
        minshengPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: AssetPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('添加你的第一笔黄金持仓'), findsOneWidget);
  });

  testWidgets('行情页渲染周期标签', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // 测试环境无真实 dio：民生积存金轮询直接给空流，避免触发 UnimplementedError。
        minshengPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: MarketPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('1日'), findsOneWidget);
    expect(find.text('7日'), findsOneWidget);
    expect(find.text('30日'), findsOneWidget);
  });

  testWidgets('行情页三类型切换：头卡价格随激活类型切换', (tester) async {
    // 默认品种为浙商（czb），浙商与 Au9999 各给固定实时价；工商无源 → 空流（AsyncData(null)），
    // 同时覆盖 Task7 评审指出的 AsyncData(null) 监听崩溃路径。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        priceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(
            GoldPrice(
                code: 'Au9999', price: 780.20, change: 3.50, percent: 0.45, preClose: 776.70, time: 1))),
        accumulationPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(
            GoldPrice(
                code: 'CZB-JCJ', price: 881.00, change: 1.00, percent: 0.11, preClose: 880.00, time: 1))),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        minshengPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: MarketPage()),
    ));
    await tester.pumpAndSettle();
    // 默认浙商：头卡显示浙商实时价（区间统计空库为 '--'）
    expect(find.text('881.00'), findsOneWidget);

    // 头卡 caption 与切换段同文案，用 .first 定位切换段。
    await tester.tap(find.text('Au9999'));
    await tester.pumpAndSettle();
    expect(find.text('780.20'), findsOneWidget); // 切到 Au9999 显示实时价

    await tester.tap(find.text('工商积存金').first);
    await tester.pumpAndSettle();
    expect(find.text('780.20'), findsNothing); // 工商无实时价 → 头卡 '--'
    expect(find.text('881.00'), findsNothing);

    await tester.tap(find.text('浙商积存金').first);
    await tester.pumpAndSettle();
    expect(find.text('881.00'), findsOneWidget); // 切回浙商恢复实时价
  });

  testWidgets('行情页当日统计卡：实时流填充日线字段显示四值', (tester) async {
    // 默认品种为浙商：浙商流注入日线字段，Au9999/工商为空。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        accumulationPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(GoldPrice(
            code: 'CZB-JCJ',
            price: 780.20,
            change: 3.50,
            percent: 0.45,
            preClose: 776.70,
            openPrice: 777.00,
            highPrice: 781.50,
            lowPrice: 775.20,
            time: 1))),
        priceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        minshengPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: MarketPage()),
    ));
    await tester.pumpAndSettle();
    // 当日统计卡标签与四字段值（fmtPrice 两位小数）
    expect(find.text('当日统计 · 实时行情'), findsOneWidget);
    expect(find.text('当日最高'), findsOneWidget);
    expect(find.text('当日最低'), findsOneWidget);
    expect(find.text('当日开盘'), findsOneWidget);
    expect(find.text('昨收'), findsOneWidget);
    expect(find.text('781.50'), findsOneWidget); // 当日最高
    expect(find.text('775.20'), findsOneWidget); // 当日最低
    expect(find.text('777.00'), findsOneWidget); // 当日开盘
    expect(find.text('776.70'), findsOneWidget); // 昨收
  });

  testWidgets('行情页当日统计卡：实时流为空四字段显示 --', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        priceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        accumulationPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        minshengPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: MarketPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('当日统计 · 实时行情'), findsOneWidget);
    expect(find.text('当日最高'), findsOneWidget);
    expect(find.text('当日最低'), findsOneWidget);
    expect(find.text('当日开盘'), findsOneWidget);
    expect(find.text('昨收'), findsOneWidget);
    // 实时流为空 → 头卡与当日四字段均不出现真实价格（'--' 兜底）
    expect(find.text('--'), findsWidgets);
    expect(find.text('776.70'), findsNothing);
  });

  testWidgets('首页收益区：每品种收益卡 + 全部持仓合计卡', (tester) async {
    // ListView 懒加载：加高视口让下方收益卡全部渲染，否则卡片会低于视口而不构建。
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 注入固定品种汇总与合计（绕过真实 DB）；行情轮询给空流以免真实 dio 抛错。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        priceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        accumulationPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        minshengPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        typeSummariesProvider.overrideWith((ref) async => [
              const TypeAssetSummary(
                kind: 'accumulation',
                label: '浙商积存金',
                totalGrams: 50,
                totalCost: 43500,
                avgCost: 870,
                currentPrice: 880,
                preClose: 875,
                floatingProfit: 500,
                todayProfit: 250,
                cumulativeProfit: 1200,
                holdingCount: 1,
              ),
              const TypeAssetSummary(
                kind: 'icbc',
                label: '工商积存金',
                totalGrams: 20,
                totalCost: 17400,
                avgCost: 870,
                currentPrice: 860,
                preClose: 865,
                floatingProfit: -200,
                todayProfit: -100,
                cumulativeProfit: 300,
                holdingCount: 1,
              ),
              const TypeAssetSummary(
                kind: 'minsheng',
                label: '民生积存金',
                totalGrams: 30,
                totalCost: 26400,
                avgCost: 880,
                currentPrice: 898.25,
                preClose: 887.30,
                floatingProfit: 547.5,
                todayProfit: 328.5,
                cumulativeProfit: 900,
                holdingCount: 1,
              ),
            ]),
        totalAssetSummaryProvider.overrideWith((ref) async => const TypeAssetSummary(
              kind: 'all',
              label: '全部持仓',
              totalGrams: 70,
              totalCost: 60900,
              avgCost: 870,
              floatingProfit: 300,
              todayProfit: 150,
              cumulativeProfit: 1500,
              holdingCount: 2,
            )),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    await tester.pump();
    await tester.pump();
    // 三行情卡此时均为空流加载态（不显示品种名），卡片标题即来自收益卡
    expect(find.text('浙商积存金'), findsOneWidget);
    expect(find.text('工商积存金'), findsOneWidget);
    expect(find.text('民生积存金'), findsOneWidget);
    expect(find.text('全部持仓'), findsOneWidget);
  });

  testWidgets('资产页顶部持仓汇总卡：标题 + 三口径收益标签', (tester) async {
    // 加高视口确保列表首项（汇总卡）在首帧即渲染
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // 注入固定持仓（非空才渲染列表）与全部持仓汇总；行情轮询给空流避免真实 dio。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        holdingsProvider.overrideWith((ref) async => const [
              Holding(
                  name: '浙商积存金',
                  kind: 'accumulation',
                  amount: 50,
                  totalCost: 43500,
                  createdAt: 0),
            ]),
        totalAssetSummaryProvider.overrideWith((ref) async =>
            const TypeAssetSummary(
              kind: 'all',
              label: '全部持仓',
              totalGrams: 50,
              totalCost: 43500,
              avgCost: 870,
              currentPrice: null,
              preClose: null,
              floatingProfit: 600,
              todayProfit: 18.5,
              cumulativeProfit: -3.6,
              holdingCount: 2,
            )),
        priceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        accumulationPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        minshengPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: AssetPage()),
    ));
    await tester.pumpAndSettle();
    // 汇总卡标题 + 品种数 pill
    expect(find.text('持仓汇总'), findsOneWidget);
    expect(find.text('2 个品种'), findsOneWidget);
    // 三口径标签：汇总卡与持仓卡片各渲染一份，故用 findsWidgets
    expect(find.text('持仓收益'), findsWidgets);
    expect(find.text('今日盈亏'), findsWidgets);
    expect(find.text('累计收益'), findsWidgets);
  });

  testWidgets('minshengPriceProvider 可被注入并取到值', (tester) async {
    // 直接 override 流：民生轮询依赖 priceApi/dio 等真实资源，注入流即绕过真实网络。
    final stream = Stream<GoldPrice?>.value(GoldPrice(
        code: 'MSB-JCJ', price: 898.25, change: 10.95,
        percent: 1.23, preClose: 887.30, time: 1));
    final container = ProviderContainer(overrides: [
      minshengPriceProvider.overrideWith((ref) => stream),
    ]);
    addTearDown(container.dispose);
    final gp = await container.read(minshengPriceProvider.future);
    expect(gp!.price, closeTo(898.25, 0.001));
    expect(gp.code, 'MSB-JCJ');
  });
}
