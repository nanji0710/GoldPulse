// test/transaction_test.dart
// I5 回归测试：多写序列必须原子化。
//   - HoldingDao.recordTrade：单事务内更新克重/成本并插入交易记录。
//   - HoldingDao.delete：单事务内删除持仓及其全部交易记录。
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/trade_dao.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'test_db.dart';

void main() {
  setUpAll(setUpTestDatabase); // 独立 FFI 数据库目录，避免并行 isolate 锁竞争
  setUp(() async {
    await AppDatabase.reset(); // 每个用例重建内存库
  });

  test('recordTrade 原子写入：持仓克重/成本与交易记录一致', () async {
    final dao = HoldingDao();
    final hId = await dao.insert(
        Holding(name: 'Au9999', kind: 'au9999', amount: 100, totalCost: 60000, createdAt: 1));

    await dao.recordTrade(
      holdingId: hId,
      amount: 50,
      totalCost: 60000, // 卖出不改总成本（Calculator.applyTrade 语义）
      record: TradeRecord(holdingId: hId, type: 'sell', amount: 50, price: 600, fee: 0, time: 1),
    );

    final h = await dao.get(hId);
    expect(h!.amount, 50);
    expect(h.totalCost, 60000);
    expect((await TradeDao().listByHolding(hId)).single.type, 'sell');
  });

  test('delete 原子删除：持仓及其全部交易记录一并移除', () async {
    final dao = HoldingDao();
    final hId = await dao.insert(
        Holding(name: 'Au9999', kind: 'au9999', amount: 100, totalCost: 60000, createdAt: 1));
    await TradeDao().insert(
        TradeRecord(holdingId: hId, type: 'buy', amount: 100, price: 600, fee: 0, time: 1));

    await dao.delete(hId);

    expect(await dao.get(hId), isNull);
    expect(await TradeDao().listByHolding(hId), isEmpty);
  });
}
