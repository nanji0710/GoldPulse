// test/transaction_test.dart
// I5 回归测试：多写序列必须原子化。
//   - HoldingDao.recordTrade：单事务内更新克重/成本并插入交易记录。
//   - HoldingDao.delete：单事务内删除持仓及其全部交易记录。
//   - HoldingDao.deleteTrade：单事务内删除交易行并回滚持仓克重/成本。
//   - Calculator.reverseTrade：删除交易时的状态回滚纯逻辑。
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/trade_dao.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/services/calculator.dart';
import 'test_db.dart';

void main() {
  setUpAll(setUpTestDatabase); // 独立 FFI 数据库目录，避免并行 isolate 锁竞争
  setUp(() async {
    await AppDatabase.reset(); // 每个用例重建内存库
  });

  test('recordTrade 原子写入：持仓克重/成本与交易记录一致', () async {
    final dao = HoldingDao();
    final hId = await dao.insert(
      Holding(
        name: 'Au9999',
        kind: 'au9999',
        amount: 100,
        totalCost: 60000,
        createdAt: 1,
      ),
    );

    await dao.recordTrade(
      holdingId: hId,
      amount: 50,
      totalCost: 60000, // 卖出不改总成本（Calculator.applyTrade 语义）
      record: TradeRecord(
        holdingId: hId,
        type: 'sell',
        amount: 50,
        price: 600,
        fee: 0,
        time: 1,
      ),
    );

    final h = await dao.get(hId);
    expect(h!.amount, 50);
    expect(h.totalCost, 60000);
    expect((await TradeDao().listByHolding(hId)).single.type, 'sell');
  });

  test('delete 原子删除：持仓及其全部交易记录一并移除', () async {
    final dao = HoldingDao();
    final hId = await dao.insert(
      Holding(
        name: 'Au9999',
        kind: 'au9999',
        amount: 100,
        totalCost: 60000,
        createdAt: 1,
      ),
    );
    await TradeDao().insert(
      TradeRecord(
        holdingId: hId,
        type: 'buy',
        amount: 100,
        price: 600,
        fee: 0,
        time: 1,
      ),
    );

    await dao.delete(hId);

    expect(await dao.get(hId), isNull);
    expect(await TradeDao().listByHolding(hId), isEmpty);
  });

  test('deleteTrade 原子删除并回滚：删交易行 + 更新持仓克重/成本', () async {
    final dao = HoldingDao();
    final tradeDao = TradeDao();
    final hId = await dao.insert(
      Holding(
        name: 'Au9999',
        kind: 'au9999',
        amount: 60,
        totalCost: 36200,
        createdAt: 1,
      ),
    );
    final buyId = await tradeDao.insert(
      TradeRecord(
        holdingId: hId,
        type: 'buy',
        amount: 10,
        price: 620,
        fee: 0,
        time: 1,
      ),
    );
    expect(await tradeDao.get(buyId), isNotNull);

    await dao.deleteTrade(
      holdingId: hId,
      amount: 50,
      totalCost: 30000,
      tradeId: buyId,
    );

    final h = await dao.get(hId);
    expect(h!.amount, 50);
    expect(h.totalCost, 30000);
    expect(await tradeDao.get(buyId), isNull);
    expect(await tradeDao.listByHolding(hId), isEmpty);
  });

  group('Calculator.reverseTrade', () {
    test('buy 回滚：克重减、成本减（金额与成本同减）', () {
      final next = Calculator.reverseTrade(
        amount: 60,
        totalCost: 36200,
        record: TradeRecord(
          holdingId: 1,
          type: 'buy',
          amount: 10,
          price: 620,
          fee: 0,
          time: 1,
        ),
      );
      expect(next, isNotNull);
      expect(next!.amount, closeTo(50, 0.0001));
      expect(next.totalCost, closeTo(30000, 0.0001));
    });
    test('buy 回滚后克重为负 → null（禁止删除）', () {
      final next = Calculator.reverseTrade(
        amount: 40,
        totalCost: 30000,
        record: TradeRecord(
          holdingId: 1,
          type: 'buy',
          amount: 50,
          price: 600,
          fee: 0,
          time: 1,
        ),
      );
      expect(next, isNull);
    });
    test('buy 回滚后成本为负 → null（禁止删除）', () {
      final next = Calculator.reverseTrade(
        amount: 50,
        totalCost: 29000,
        record: TradeRecord(
          holdingId: 1,
          type: 'buy',
          amount: 50,
          price: 600,
          fee: 0,
          time: 1,
        ),
      );
      expect(next, isNull);
    });
    test('interest 回滚：仅减克重、成本保留', () {
      final next = Calculator.reverseTrade(
        amount: 51.2,
        totalCost: 31000,
        record: TradeRecord(
          holdingId: 1,
          type: 'interest',
          amount: 1.2,
          price: 0,
          fee: 0,
          time: 1,
        ),
      );
      expect(next, isNotNull);
      expect(next!.amount, closeTo(50, 0.0001));
      expect(next.totalCost, closeTo(31000, 0.0001));
    });
    test('interest 回滚后克重为负 → null（禁止删除）', () {
      final next = Calculator.reverseTrade(
        amount: 0.5,
        totalCost: 31000,
        record: TradeRecord(
          holdingId: 1,
          type: 'interest',
          amount: 1.2,
          price: 0,
          fee: 0,
          time: 1,
        ),
      );
      expect(next, isNull);
    });
    test('sell 回滚：加回克重、成本保留（卖出从不致负）', () {
      final next = Calculator.reverseTrade(
        amount: 40,
        totalCost: 30000,
        record: TradeRecord(
          holdingId: 1,
          type: 'sell',
          amount: 10,
          price: 620,
          fee: 24.8,
          time: 1,
        ),
      );
      expect(next, isNotNull);
      expect(next!.amount, closeTo(50, 0.0001));
      expect(next.totalCost, closeTo(30000, 0.0001));
    });
  });
}
