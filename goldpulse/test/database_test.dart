// test/database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/database/price_dao.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/trade_dao.dart';
import 'package:goldpulse/database/alert_dao.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/models/alert.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    AppDatabase.databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await AppDatabase.reset(); // 每个用例重建内存库
  });

  test('gold_price 防重复写入', () async {
    final dao = PriceDao();
    final gp = GoldPrice(code: 'SGE-Au(T+D)', price: 780, change: 1, percent: 0.1, preClose: 779, time: 1000);
    await dao.insert(gp);
    await dao.insert(gp);
    expect(await dao.count(), 1);
  });
  test('holding CRUD', () async {
    final dao = HoldingDao();
    final id = await dao.insert(Holding(name: '浙商积存金', kind: 'accumulation', amount: 500, totalCost: 310000, createdAt: 1));
    final list = await dao.list();
    expect(list.single.amount, 500);
    await dao.updateAmount(id, 501.2);
    expect((await dao.get(id))!.amount, 501.2);
  });
  test('trade_record 支持三类事件', () async {
    final dao = TradeDao();
    await dao.insert(TradeRecord(holdingId: 1, type: 'buy', amount: 100, price: 600, fee: 0, time: 1));
    await dao.insert(TradeRecord(holdingId: 1, type: 'interest', amount: 0.08, price: 0, fee: 0, time: 2));
    final list = await dao.listByHolding(1);
    expect(list.map((t) => t.type), ['buy', 'interest']);
  });
  test('alert 默认 enable 关/开', () async {
    final dao = AlertDao();
    final id = await dao.insert(Alert(type: 'price_up', target: 800, enable: true));
    expect((await dao.get(id))!.enable, true);
    await dao.toggle(id, false);
    expect((await dao.get(id))!.enable, false);
  });
}
