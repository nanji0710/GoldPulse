// lib/database/app_database.dart
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static const _name = 'goldpulse.db';
  static const _version = 1;
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
    await db.execute('CREATE INDEX idx_gold_price_code_time ON gold_price(code, time)');
    await db.execute('CREATE INDEX idx_trade_holding ON trade_record(holding_id)');
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // 未来 schema 变更在此用版本号分叉处理（示例）：
    // if (oldV < 2) { await db.execute('ALTER TABLE ...'); }
  }
}
