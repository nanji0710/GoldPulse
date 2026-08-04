// test/holding_detail_test.dart
// Task 4 持仓详情页 widget 级覆盖：
//   1) 详情页渲染（注入持仓/交易/行情：现价、三口径、克重 4 位小数、交易流水标签）；
//   2) 追加买入 → 克重与均价正确更新（recordTradeProvider）；
//   3) 删除买入交易 → 克重/成本回滚（deleteTradeProvider）；
//   4) 删除会致负（回滚后克重为负）的交易被拒绝并 SnackBar 提示原因。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/trade_dao.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/pages/holding_detail_page.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/state/price_provider.dart';

/// 共享交易存储：让两个假 DAO 读写同一条列表，模拟真实 DB 的一致性
/// （recordTrade 插入 → listByHolding 可见；deleteTrade 删除 → get 返回 null）。
class _Store {
  final List<TradeRecord> trades = [];
  int nextId = 100;
}

class _FakeHoldingDao extends HoldingDao {
  Holding holding;
  final _Store store;
  _FakeHoldingDao(this.holding, this.store);

  @override
  Future<Holding?> get(int id) async => holding;

  @override
  Future<List<Holding>> list() async => [holding];

  @override
  Future<int> insert(Holding h) async => h.id;

  @override
  Future<void> recordTrade({
    required int holdingId,
    required double amount,
    required double totalCost,
    required double boughtCost,
    required TradeRecord record,
  }) async {
    holding = Holding(
      id: holding.id,
      name: holding.name,
      kind: holding.kind,
      amount: amount,
      totalCost: totalCost,
      boughtCost: boughtCost,
      createdAt: holding.createdAt,
    );
    store.trades.add(
      TradeRecord(
        id: store.nextId++,
        holdingId: holdingId,
        type: record.type,
        amount: record.amount,
        price: record.price,
        fee: record.fee,
        time: record.time,
      ),
    );
  }

  @override
  Future<void> deleteTrade({
    required int holdingId,
    required double amount,
    required double totalCost,
    required double boughtCost,
    required int tradeId,
  }) async {
    holding = Holding(
      id: holding.id,
      name: holding.name,
      kind: holding.kind,
      amount: amount,
      totalCost: totalCost,
      boughtCost: boughtCost,
      createdAt: holding.createdAt,
    );
    store.trades.removeWhere((t) => t.id == tradeId);
  }
}

class _FakeTradeDao extends TradeDao {
  final _Store store;
  _FakeTradeDao(this.store);

  @override
  Future<List<TradeRecord>> listByHolding(int holdingId) async =>
      store.trades.where((t) => t.holdingId == holdingId).toList();

  @override
  Future<TradeRecord?> get(int id) async {
    for (final t in store.trades) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<int> insert(TradeRecord t) async {
    store.trades.add(
      TradeRecord(
        id: store.nextId++,
        holdingId: t.holdingId,
        type: t.type,
        amount: t.amount,
        price: t.price,
        fee: t.fee,
        time: t.time,
      ),
    );
    return store.nextId - 1;
  }

  @override
  Future<void> delete(int id) async {
    store.trades.removeWhere((t) => t.id == id);
  }
}

/// 固定逐帧推进，避免 TextField 光标闪烁导致 pumpAndSettle 无法收敛。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 加高测试视口（默认 800×600 下交易流水在折叠线以下，第二个条目甚至不构建），
/// 让整页内容一次性可见可交互。
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// 构造详情页测试壳：注入假 DAO + 浙商积存金行情流（持仓 kind=accumulation）。
Widget _buildApp(
  _FakeHoldingDao dao,
  _FakeTradeDao tradeDao,
  Stream<GoldPrice?> stream,
) {
  return ProviderScope(
    overrides: [
      holdingDaoProvider.overrideWithValue(dao),
      tradeDaoProvider.overrideWithValue(tradeDao),
      accumulationPriceProvider.overrideWith((ref) => stream),
    ],
    child: const MaterialApp(home: HoldingDetailPage(holdingId: 1)),
  );
}

GoldPrice _quote(double price) => GoldPrice(
  code: 'CZB-JCJ',
  price: price,
  change: 5,
  percent: 0.81,
  preClose: 615,
  time: 1,
);

void main() {
  testWidgets('详情页渲染：现价/三口径/克重 4 位小数/交易流水', (tester) async {
    _useTallSurface(tester);
    final store = _Store()
      ..trades.addAll([
        TradeRecord(
          id: 1,
          holdingId: 1,
          type: 'buy',
          amount: 50,
          price: 600,
          fee: 0,
          time: 1,
        ),
      ]);
    final dao = _FakeHoldingDao(
      Holding(
        id: 1,
        name: '浙商积存金',
        kind: 'accumulation',
        amount: 50,
        totalCost: 30000,
        boughtCost: 30000,
        createdAt: 1,
      ),
      store,
    );
    final tradeDao = _FakeTradeDao(store);

    await tester.pumpWidget(
      _buildApp(dao, tradeDao, Stream<GoldPrice?>.value(_quote(620))),
    );
    await _settle(tester);

    expect(find.textContaining('620.00'), findsOneWidget); // 现价
    expect(find.text('持仓收益'), findsOneWidget); // 三口径标题
    expect(find.text('今日盈亏'), findsOneWidget);
    expect(find.text('累计收益'), findsOneWidget);
    expect(find.textContaining('50.0000g'), findsWidgets); // 克重必须 4 位小数
    expect(find.text('交易流水'), findsOneWidget);
    expect(find.text('买入'), findsOneWidget); // 类型标签
    expect(find.textContaining('50.0000g × 600.00 元/g'), findsOneWidget);
    expect(find.textContaining('手续费 0.00 元'), findsOneWidget);
  });

  testWidgets('追加买入：克重与均价正确更新（默认价取现价）', (tester) async {
    _useTallSurface(tester);
    final store = _Store()
      ..trades.addAll([
        TradeRecord(
          id: 1,
          holdingId: 1,
          type: 'buy',
          amount: 50,
          price: 600,
          fee: 0,
          time: 1,
        ),
      ]);
    final dao = _FakeHoldingDao(
      Holding(
        id: 1,
        name: '浙商积存金',
        kind: 'accumulation',
        amount: 50,
        totalCost: 30000,
        boughtCost: 30000,
        createdAt: 1,
      ),
      store,
    );
    final tradeDao = _FakeTradeDao(store);

    await tester.pumpWidget(
      _buildApp(dao, tradeDao, Stream<GoldPrice?>.value(_quote(620))),
    );
    await _settle(tester);

    await tester.tap(find.text('追加买入'));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), '10');
    await tester.tap(find.text('确定'));
    await _settle(tester);

    // 第二段：买入价格，默认预填当前行情价 620（double.toString() → '620.0'）。
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '620.0',
    );
    await tester.tap(find.text('确定'));
    await _settle(tester);

    expect(dao.holding.amount, 60); // 50 + 10
    expect(dao.holding.totalCost, 36200); // 30000 + 10×620
    expect(store.trades.length, 2); // 原买入 + 追加买入
    expect(store.trades.last.type, 'buy');
    expect(store.trades.last.amount, 10);
    expect(store.trades.last.price, 620);
    expect(find.textContaining('60.0000g'), findsWidgets); // UI 克重刷新
  });

  testWidgets('删除买入交易：克重/成本回滚', (tester) async {
    _useTallSurface(tester);
    final store = _Store()
      ..trades.addAll([
        TradeRecord(
          id: 1,
          holdingId: 1,
          type: 'buy',
          amount: 50,
          price: 600,
          fee: 0,
          time: 1,
        ),
        TradeRecord(
          id: 2,
          holdingId: 1,
          type: 'buy',
          amount: 10,
          price: 620,
          fee: 0,
          time: 2,
        ),
      ]);
    final dao = _FakeHoldingDao(
      Holding(
        id: 1,
        name: '浙商积存金',
        kind: 'accumulation',
        amount: 60,
        totalCost: 36200,
        boughtCost: 36200,
        createdAt: 1,
      ),
      store,
    );
    final tradeDao = _FakeTradeDao(store);

    await tester.pumpWidget(
      _buildApp(dao, tradeDao, Stream<GoldPrice?>.value(_quote(620))),
    );
    await _settle(tester);

    // 删除第二条买入（10g@620）：listByHolding 按 time 升序，index 1。
    await tester.tap(find.byIcon(Icons.delete_outline).at(1));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('删除'));
    await _settle(tester);

    expect(dao.holding.amount, 50); // 60 - 10
    expect(dao.holding.totalCost, 30000); // 36200 - 10×620
    expect(store.trades.length, 1);
    expect(find.textContaining('50.0000g'), findsWidgets);
  });

  testWidgets('删除会致负（回滚后克重为负）的买入交易被拒绝', (tester) async {
    _useTallSurface(tester);
    final store = _Store()
      ..trades.addAll([
        TradeRecord(
          id: 1,
          holdingId: 1,
          type: 'buy',
          amount: 50,
          price: 600,
          fee: 0,
          time: 1,
        ),
        TradeRecord(
          id: 2,
          holdingId: 1,
          type: 'sell',
          amount: 10,
          price: 620,
          fee: 24.8,
          time: 2,
        ),
      ]);
    final dao = _FakeHoldingDao(
      Holding(
        id: 1,
        name: '浙商积存金',
        kind: 'accumulation',
        amount: 40,
        totalCost: 30000,
        boughtCost: 30000,
        createdAt: 1,
      ),
      store,
    );
    final tradeDao = _FakeTradeDao(store);

    await tester.pumpWidget(
      _buildApp(dao, tradeDao, Stream<GoldPrice?>.value(_quote(620))),
    );
    await _settle(tester);

    // 删除 50g 的买入（index 0）：当前仅 40g，回滚后克重为负 → 拒绝。
    await tester.tap(find.byIcon(Icons.delete_outline).at(0));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('删除'));
    await _settle(tester);

    expect(find.textContaining('禁止删除'), findsOneWidget); // SnackBar 提示原因
    expect(dao.holding.amount, 40); // 未变更
    expect(dao.holding.totalCost, 30000);
    expect(store.trades.length, 2); // 交易未被删除
  });
}
