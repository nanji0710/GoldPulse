// lib/database/holding_dao.dart
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/holding.dart';

class HoldingDao {
  Future<Database> get _db => AppDatabase.database;
  Future<int> insert(Holding h) async {
    final map = h.toMap();
    if (map['id'] == 0) map.remove('id'); // id=0 由 AUTOINCREMENT 生成
    return (await _db).insert('holding', map);
  }
  Future<List<Holding>> list() async {
    final rows = await (await _db).query('holding', orderBy: 'created_at');
    return rows.map(Holding.fromMap).toList();
  }
  Future<Holding?> get(int id) async {
    final rows = await (await _db).query('holding', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Holding.fromMap(rows.first);
  }
  Future<void> updateAmount(int id, double newAmount) async {
    await (await _db).update('holding', {'amount': newAmount}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> updateCost(int id, double newTotalCost) async {
    await (await _db).update('holding', {'total_cost': newTotalCost}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('trade_record', where: 'holding_id = ?', whereArgs: [id]);
    await db.delete('holding', where: 'id = ?', whereArgs: [id]);
  }
}
