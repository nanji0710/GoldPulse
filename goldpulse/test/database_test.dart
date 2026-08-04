// test/database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/database/price_dao.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/trade_dao.dart';
import 'package:goldpulse/database/alert_dao.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'test_db.dart';

void main() {
  setUpAll(setUpTestDatabase); // 独立 FFI 数据库目录，避免并行 isolate 锁竞争
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
  test('v1→v2 迁移：gold_price ALTER 新增日线列，旧行默认 0', () async {
    // 手动构造一个 user_version=1 的旧库（无日线列）并插入旧数据，
    // 然后由 AppDatabase 以 version=2 重开 → 触发 _onUpgrade 的 ALTER。
    final factory = AppDatabase.databaseFactory;
    final dir = await factory.getDatabasesPath();
    final path = join(dir, 'goldpulse.db');
    final old = await factory.openDatabase(path, options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE gold_price(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL,
            price REAL NOT NULL,
            change REAL NOT NULL,
            percent REAL NOT NULL,
            pre_close REAL NOT NULL,
            time INTEGER NOT NULL,
            UNIQUE(code, time)
          )''');
        // 真实 v1 库含 holding/trade_record/alert 表（无 bought_cost/kind 列）；
        // v3 迁移 ALTER holding，v4 迁移 ALTER alert。
        await db.execute('''
          CREATE TABLE holding(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            amount REAL NOT NULL,
            total_cost REAL NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE trade_record(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            holding_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            price REAL NOT NULL,
            fee REAL NOT NULL,
            time INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE alert(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            target REAL NOT NULL,
            enable INTEGER NOT NULL DEFAULT 0,
            trigger_count INTEGER NOT NULL DEFAULT 0,
            last_triggered INTEGER NOT NULL DEFAULT 0
          )''');
      },
    ));
    await old.insert('gold_price', {
      'code': 'CZB-JCJ', 'price': 780.0, 'change': 1.0, 'percent': 0.1,
      'pre_close': 779.0, 'time': 1,
    });
    await old.close();

    final db = await AppDatabase.database; // 触发 onUpgrade(1→2)
    final cols = (await db.rawQuery('PRAGMA table_info(gold_price)'))
        .map((c) => c['name'])
        .toSet();
    expect(cols, contains('open_price'));
    expect(cols, contains('high_price'));
    expect(cols, contains('low_price'));
    // 旧行读回：日线列被 DEFAULT 0 填充。
    final rows = await db.query('gold_price', where: 'code = ?', whereArgs: ['CZB-JCJ']);
    expect(rows.single['open_price'], 0);
    expect(rows.single['high_price'], 0);
    expect(rows.single['low_price'], 0);
  });
  test('v2→v3 迁移：holding ALTER 新增 bought_cost，存量行回填 = total_cost', () async {
    // 手动构造一个 user_version=2 的旧库（holding 无 bought_cost 列）并插入旧数据，
    // 然后由 AppDatabase 以 version=3 重开 → 触发 _onUpgrade 的 ALTER + UPDATE 回填。
    final factory = AppDatabase.databaseFactory;
    final dir = await factory.getDatabasesPath();
    final path = join(dir, 'goldpulse.db');
    final old = await factory.openDatabase(path, options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE gold_price(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL,
            price REAL NOT NULL,
            change REAL NOT NULL,
            percent REAL NOT NULL,
            pre_close REAL NOT NULL,
            time INTEGER NOT NULL,
            open_price REAL NOT NULL DEFAULT 0,
            high_price REAL NOT NULL DEFAULT 0,
            low_price REAL NOT NULL DEFAULT 0,
            UNIQUE(code, time)
          )''');
        await db.execute('''
          CREATE TABLE holding(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            amount REAL NOT NULL,
            total_cost REAL NOT NULL,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE trade_record(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            holding_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            price REAL NOT NULL,
            fee REAL NOT NULL,
            time INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE alert(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            target REAL NOT NULL,
            enable INTEGER NOT NULL DEFAULT 0,
            trigger_count INTEGER NOT NULL DEFAULT 0,
            last_triggered INTEGER NOT NULL DEFAULT 0
          )''');
      },
    ));
    // 旧模型 total_cost 从未被卖出扣减 → 即为累计买入成本
    await old.insert('holding', {
      'name': '浙商积存金', 'kind': 'accumulation',
      'amount': 100.0, 'total_cost': 78000.0, 'created_at': 1,
    });
    await old.close();

    final db = await AppDatabase.database; // 触发 onUpgrade(2→3)
    final cols = (await db.rawQuery('PRAGMA table_info(holding)'))
        .map((c) => c['name'])
        .toSet();
    expect(cols, contains('bought_cost'));
    // 存量行回填：bought_cost = total_cost = 78000
    final rows = await db.query('holding');
    expect(rows.single['bought_cost'], 78000);
  });
  test('v3→v4 迁移：alert ALTER 新增 kind，存量行默认 au9999', () async {
    // 手动构造一个 user_version=3 的旧库（alert 无 kind 列）并插入旧数据，
    // 然后由 AppDatabase 以 version=4 重开 → 触发 _onUpgrade 的 ALTER。
    final factory = AppDatabase.databaseFactory;
    final dir = await factory.getDatabasesPath();
    final path = join(dir, 'goldpulse.db');
    final old = await factory.openDatabase(path, options: OpenDatabaseOptions(
      version: 3,
      onCreate: (db, _) async {
        // v3 完整 schema：gold_price 含日线列、holding 含 bought_cost、alert 无 kind。
        await db.execute('''
          CREATE TABLE gold_price(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            code TEXT NOT NULL,
            price REAL NOT NULL,
            change REAL NOT NULL,
            percent REAL NOT NULL,
            pre_close REAL NOT NULL,
            time INTEGER NOT NULL,
            open_price REAL NOT NULL DEFAULT 0,
            high_price REAL NOT NULL DEFAULT 0,
            low_price REAL NOT NULL DEFAULT 0,
            UNIQUE(code, time)
          )''');
        await db.execute('''
          CREATE TABLE holding(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            amount REAL NOT NULL,
            total_cost REAL NOT NULL,
            bought_cost REAL NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE trade_record(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            holding_id INTEGER NOT NULL,
            type TEXT NOT NULL,
            amount REAL NOT NULL,
            price REAL NOT NULL,
            fee REAL NOT NULL,
            time INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE alert(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            target REAL NOT NULL,
            enable INTEGER NOT NULL DEFAULT 0,
            trigger_count INTEGER NOT NULL DEFAULT 0,
            last_triggered INTEGER NOT NULL DEFAULT 0
          )''');
      },
    ));
    await old.insert('alert', {
      'type': 'price_up', 'target': 800.0, 'enable': 1,
    });
    await old.close();

    final db = await AppDatabase.database; // 触发 onUpgrade(3→4)
    final cols = (await db.rawQuery('PRAGMA table_info(alert)'))
        .map((c) => c['name'])
        .toSet();
    expect(cols, contains('kind'));
    // 存量提醒读回：kind 被 DEFAULT 'au9999' 填充。
    final rows = await db.query('alert');
    expect(rows.single['kind'], 'au9999');
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
  test('alert recordTrigger 自增且不影响其他行', () async {
    final dao = AlertDao();
    final triggered = await dao.insert(Alert(type: 'price_down', target: 700, enable: true));
    final untouched = await dao.insert(Alert(type: 'profit_target', target: 900, enable: true));
    final t = DateTime.fromMillisecondsSinceEpoch(5000);
    await dao.recordTrigger(triggered, time: t);
    await dao.recordTrigger(triggered, time: t);
    expect((await dao.get(triggered))!.triggerCount, 2);
    expect((await dao.get(triggered))!.lastTriggered, 5000);
    expect((await dao.get(untouched))!.triggerCount, 0);
    expect((await dao.get(untouched))!.lastTriggered, 0);
  });
}
