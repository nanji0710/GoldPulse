// test/holding_actions_test.dart
// Task 14 复审修正的覆盖测试（widget 级，DAO 用假实现避免真实 DB/isolate）：
//  1) 修改克重 ≥1000g 时预填为纯数字（无千分位），解析路径可成功保存；
//  2) 卖出克重超过持仓时对话框内联报错，不产生交易记录。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/trade_dao.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/widgets/holding_list_tile.dart';

/// 假持仓 DAO：仅记录调用，不触碰真实数据库。
class _FakeHoldingDao extends HoldingDao {
  Holding holding;
  final updatedAmounts = <double>[];
  _FakeHoldingDao(this.holding);

  @override
  Future<Holding?> get(int id) async => holding;

  @override
  Future<List<Holding>> list() async => [holding];

  @override
  Future<int> insert(Holding h) async => h.id;

  @override
  Future<void> updateAmount(int id, double newAmount) async {
    holding = Holding(id: holding.id, name: holding.name, kind: holding.kind,
        amount: newAmount, totalCost: holding.totalCost, createdAt: holding.createdAt);
    updatedAmounts.add(newAmount);
  }

  @override
  Future<void> updateCost(int id, double newTotalCost) async {
    holding = Holding(id: holding.id, name: holding.name, kind: holding.kind,
        amount: holding.amount, totalCost: newTotalCost, createdAt: holding.createdAt);
  }
}

/// 假交易 DAO：记录 insert，不触碰真实数据库。
class _FakeTradeDao extends TradeDao {
  final trades = <TradeRecord>[];
  @override
  Future<int> insert(TradeRecord t) async {
    trades.add(t);
    return t.id;
  }
}

/// 固定逐帧推进，避免 TextField 光标闪烁导致 pumpAndSettle 无法收敛。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('修改克重：≥1000g 预填为纯数字且解析路径可保存', (tester) async {
    final dao = _FakeHoldingDao(Holding(
        id: 1, name: '浙商积存金', kind: 'accumulation', amount: 1000.5, totalCost: 620000, createdAt: 1));

    await tester.pumpWidget(ProviderScope(
      overrides: [holdingDaoProvider.overrideWithValue(dao)],
      child: MaterialApp(home: Scaffold(body: HoldingListTile(holding: dao.holding))),
    ));
    await tester.longPress(find.byType(HoldingListTile));
    await _settle(tester);
    await tester.tap(find.text('修改克重'));
    await _settle(tester);

    // 预填必须是能被 double.tryParse 直接解析的纯数字（无千分位分隔符）。
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '1000.5');
    expect(field.controller!.text.contains(','), isFalse);
    expect(double.tryParse(field.controller!.text), 1000.5);

    // 输入带千分位分隔符的值也能解析保存（解析路径对 ≥1000 成立）。
    await tester.enterText(find.byType(TextField), '1,200.25');
    await tester.tap(find.text('确定'));
    await _settle(tester);
    expect(dao.updatedAmounts.single, 1200.25);
  });

  testWidgets('记一笔卖出：超卖被内联拦截且不产生交易', (tester) async {
    final dao = _FakeHoldingDao(Holding(
        id: 1, name: '浙商积存金', kind: 'accumulation', amount: 50, totalCost: 310000, createdAt: 1));
    final tradeDao = _FakeTradeDao();
    final stream = Stream<GoldPrice?>.value(
        GoldPrice(code: 'Au9999', price: 780.2, change: 0, percent: 0, preClose: 780.2, time: 1));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        holdingDaoProvider.overrideWithValue(dao),
        tradeDaoProvider.overrideWithValue(tradeDao),
        priceProvider.overrideWith((ref) => stream),
      ],
      child: MaterialApp(home: Scaffold(body: HoldingListTile(holding: dao.holding))),
    ));
    await tester.longPress(find.byType(HoldingListTile));
    await _settle(tester);
    await tester.tap(find.text('记一笔卖出'));
    await _settle(tester);

    // 超卖克重：内联报错，对话框不关闭。
    await tester.enterText(find.byType(TextField).at(0), '80');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('超过当前持仓'), findsOneWidget);

    await tester.tap(find.text('确定'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(dao.updatedAmounts, isEmpty);
    expect(tradeDao.trades, isEmpty);

    // 修正为合法克重 + 价格后，卖出成功。
    await tester.enterText(find.byType(TextField).at(0), '40');
    await tester.enterText(find.byType(TextField).at(1), '780.2');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('超过当前持仓'), findsNothing);
    await tester.tap(find.text('确定'));
    await _settle(tester);
    expect(dao.updatedAmounts.single, 10);
    expect(tradeDao.trades.single.type, 'sell');
  });
}
