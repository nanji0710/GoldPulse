// test/widget_smoke_test.dart（引导 + 首页，后续任务追加）
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/pages/asset_page.dart';
import 'package:goldpulse/pages/home_page.dart';
import 'package:goldpulse/pages/market_page.dart';
import 'package:goldpulse/pages/onboarding_page.dart';
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
        // 测试环境无真实 dio：两个积存金轮询直接给空流，避免触发 UnimplementedError。
        accumulationPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: HomePage()),
    ));
    await tester.pump();
    expect(find.text('780.20'), findsOneWidget);
    expect(find.text('Au9999'), findsOneWidget);
  });

  testWidgets('资产页空状态提示录入', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AssetPage())));
    await tester.pumpAndSettle();
    expect(find.textContaining('添加你的第一笔黄金持仓'), findsOneWidget);
  });

  testWidgets('行情页渲染周期标签', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: MarketPage())));
    await tester.pumpAndSettle();
    expect(find.text('1日'), findsOneWidget);
    expect(find.text('7日'), findsOneWidget);
    expect(find.text('30日'), findsOneWidget);
  });

  testWidgets('行情页三类型切换：头卡价格随激活类型切换', (tester) async {
    // Au9999 给固定实时价；浙商/工商无真实源 → 空流（AsyncData(null)），
    // 同时覆盖 Task7 评审指出的 AsyncData(null) 监听崩溃路径。
    await tester.pumpWidget(ProviderScope(
      overrides: [
        priceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(
            GoldPrice(
                code: 'Au9999', price: 780.20, change: 3.50, percent: 0.45, preClose: 776.70, time: 1))),
        accumulationPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
      ],
      child: const MaterialApp(home: MarketPage()),
    ));
    await tester.pumpAndSettle();
    // 默认 Au9999：头卡显示实时价（区间统计空库为 '--'，不与价格文案冲突）
    expect(find.text('780.20'), findsOneWidget);

    await tester.tap(find.text('浙商积存金'));
    await tester.pumpAndSettle();
    expect(find.text('780.20'), findsNothing); // 浙商无实时价 → 头卡 '--'

    await tester.tap(find.text('工商积存金'));
    await tester.pumpAndSettle();
    expect(find.text('780.20'), findsNothing); // 工商无实时价 → 头卡 '--'

    await tester.tap(find.text('Au9999'));
    await tester.pumpAndSettle();
    expect(find.text('780.20'), findsOneWidget); // 切回 Au9999 恢复实时价
  });

  testWidgets('行情页当日统计卡：实时流填充日线字段显示四值', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        priceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(GoldPrice(
            code: 'Au9999',
            price: 780.20,
            change: 3.50,
            percent: 0.45,
            preClose: 776.70,
            openPrice: 777.00,
            highPrice: 781.50,
            lowPrice: 775.20,
            time: 1))),
        accumulationPriceProvider
            .overrideWith((ref) => Stream<GoldPrice?>.value(null)),
        icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)),
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
}
