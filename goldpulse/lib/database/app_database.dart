// lib/database/app_database.dart
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static const _name = 'goldpulse.db';
  /// v2：gold_price 表新增当日日线字段 open_price/high_price/low_price
  /// （Task 9：getGoldPrice 统一行情源返回日线字段，持久化供历史统计使用）。
  /// v3：holding 表新增 bought_cost（累计买入总成本）——卖出扣成本后 total_cost 缩减，
  /// 用独立字段追踪累计投入，保证累计收益恒等式不变。
  static const _version = 3;
  static DatabaseFactory databaseFactory = databaseFactorySqflitePlugin;
  static Database? _db;

  static Future<Database> get database async => _db ??= await _open();
  static Future<void> reset() async {
    await _db?.close();
    _db = null;
    // 每个用例重建库：删除持久化的 .db 文件（含 -wal/-shm/-journal）
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(join(dir, _name));
  }

  static Future<Database> _open() async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = join(dir, _name);
    return databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(version: _version, onCreate: _onCreate, onUpgrade: _onUpgrade));
  }

  static Future<void> _onCreate(Database db, int version) async {
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
    await db.execute('CREATE INDEX idx_gold_price_code_time ON gold_price(code, time)');
    await db.execute('CREATE INDEX idx_trade_holding ON trade_record(holding_id)');
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // v1 → v2：gold_price 新增当日日线字段（旧安装原地 ALTER，新装走 onCreate）。
    // 已有旧行自动填 DEFAULT 0；fromMap 对缺失列同样回退 0，双保险。
    if (oldV < 2) {
      await db.execute('ALTER TABLE gold_price ADD COLUMN open_price REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE gold_price ADD COLUMN high_price REAL NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE gold_price ADD COLUMN low_price REAL NOT NULL DEFAULT 0');
    }
    // v2 → v3：holding 新增 bought_cost。存量行在旧模型下 total_cost 从未被卖出扣减，
    // 故其值即等于累计买入总成本，直接回填。
    if (oldV < 3) {
      await db.execute('ALTER TABLE holding ADD COLUMN bought_cost REAL NOT NULL DEFAULT 0');
      await db.execute('UPDATE holding SET bought_cost = total_cost');
    }
  }
}
