// lib/database/price_dao.dart
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/gold_price.dart';

class PriceDao {
  Future<Database> get _db => AppDatabase.database;
  Future<void> insert(GoldPrice gp) async {
    final db = await _db;
    final map = gp.toMap();
    if (map['id'] == 0) map.remove('id'); // id=0 由 AUTOINCREMENT 生成
    await db.insert('gold_price', map,
        conflictAlgorithm: ConflictAlgorithm.ignore); // UNIQUE(code,time) 冲突时忽略
  }
  Future<List<GoldPrice>> recent(String code, {int limit = 500}) async {
    final db = await _db;
    final rows = await db.query('gold_price', where: 'code = ?', whereArgs: [code], orderBy: 'time DESC', limit: limit);
    return rows.map(GoldPrice.fromMap).toList();
  }
  Future<GoldPrice?> latest(String code) async {
    final list = await recent(code, limit: 1);
    return list.isEmpty ? null : list.first;
  }
  Future<void> pruneOlderThan({required int code, required int before}) async {
    final db = await _db;
    await db.delete('gold_price', where: 'time < ?', whereArgs: [before]);
  }
  Future<int> count() async => Sqflite.firstIntValue(await (await _db).rawQuery('SELECT COUNT(*) FROM gold_price')) ?? 0;
}
