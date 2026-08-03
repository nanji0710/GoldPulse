// test/backup_test.dart
// Task 14：备份服务测试——导出/导入无损往返、非法 JSON/版本抛错。
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/alert_dao.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/price_dao.dart';
import 'package:goldpulse/database/trade_dao.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/services/backup_service.dart';
import 'test_db.dart';

void main() {
  setUpAll(setUpTestDatabase); // 独立 FFI 数据库目录，避免并行 isolate 锁竞争
  setUp(() async {
    await AppDatabase.reset(); // 每个用例重建内存库
  });

  test('export → import 无损往返', () async {
    final svc = BackupService();
    final json = await svc.exportJson(holdings: [], trades: [], alerts: []);
    final map = jsonDecode(json);
    expect(map.containsKey('version'), isTrue);
    expect(map['holdings'], isA<List>());
  });

  test('import 非法 JSON 抛错', () {
    expect(() => BackupService.parseImport('not json'), throwsFormatException);
    expect(() => BackupService.parseImport('[1,2,3]'), throwsFormatException);
  });

  test('导出包含三张表全部数据', () async {
    final svc = BackupService();
    final json = await svc.exportJson(
      holdings: [Holding(name: '浙商积存金', kind: 'accumulation', amount: 501.2, totalCost: 310000, createdAt: 1)],
      trades: [TradeRecord(holdingId: 1, type: 'buy', amount: 100, price: 600, fee: 0, time: 1)],
      alerts: [Alert(type: 'price_up', target: 800, enable: true)],
    );
    final map = jsonDecode(json) as Map<String, dynamic>;
    expect(map['version'], 1);
    expect((map['holdings'] as List).single['name'], '浙商积存金');
    expect((map['trades'] as List).single['holding_id'], 1);
    expect((map['alerts'] as List).single['target'], 800);
  });

  test('importJson 清库后重建（id 保留、外键不破坏）', () async {
    final dao = HoldingDao();
    final hId = await dao.insert(
        Holding(name: '浙商积存金', kind: 'accumulation', amount: 500, totalCost: 310000, createdAt: 1));
    await TradeDao().insert(TradeRecord(holdingId: hId, type: 'buy', amount: 100, price: 600, fee: 0, time: 1));
    await AlertDao().insert(Alert(type: 'price_up', target: 800, enable: true));

    final svc = BackupService();
    final json = await svc.exportJson(
      holdings: await dao.list(),
      trades: await TradeDao().all(),
      alerts: await AlertDao().list(),
    );

    // 清库后应无数据
    final db = await AppDatabase.database;
    await db.delete('holding');
    await db.delete('trade_record');
    await db.delete('alert');
    expect(await dao.list(), isEmpty);

    // 恢复
    await svc.importJson(json);
    final restored = await dao.list();
    expect(restored.length, 1);
    expect(restored.single.id, hId); // id 保留，保证 trade.holding_id 仍指向
    expect(restored.single.amount, 500);
    expect((await TradeDao().all()).single.holdingId, hId);
    expect((await AlertDao().list()).single.target, 800);
  });

  test('I4：备份不含价格历史，导入会清空 gold_price（UI 导入前已确认告知）', () async {
    final dao = PriceDao();
    await dao.insert(GoldPrice(
        code: 'SGE-Au(T+D)', price: 780, change: 1, percent: 0.13, preClose: 779, time: 1));
    expect(await dao.count(), 1);

    final json = await BackupService().exportJson(holdings: [], trades: [], alerts: []);
    expect((jsonDecode(json) as Map<String, dynamic>).containsKey('gold_price'), isFalse);

    await BackupService().importJson(json);
    expect(await dao.count(), 0); // 导入清空价格历史（行为已由确认对话框明示）
  });

  test('importJson 版本不合法抛错', () async {
    final svc = BackupService();
    final json = jsonEncode({'version': 99, 'holdings': [], 'trades': [], 'alerts': []});
    await expectLater(svc.importJson(json), throwsFormatException);
  });

  test('importJson 字段缺失抛错', () async {
    final svc = BackupService();
    final json = jsonEncode({'version': 1});
    await expectLater(svc.importJson(json), throwsFormatException);
  });
}
