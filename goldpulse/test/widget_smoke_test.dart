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
}
