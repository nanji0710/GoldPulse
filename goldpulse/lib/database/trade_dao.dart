// lib/database/trade_dao.dart
import '../database/app_database.dart';
import '../models/trade_record.dart';

class TradeDao {
  Future<List<TradeRecord>> listByHolding(int holdingId) async {
    final rows = await (await AppDatabase.database).query(
      'trade_record',
      where: 'holding_id = ?',
      whereArgs: [holdingId],
      orderBy: 'time ASC',
    );
    return rows.map(TradeRecord.fromMap).toList();
  }

  Future<TradeRecord?> get(int id) async {
    final rows = await (await AppDatabase.database).query(
      'trade_record',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : TradeRecord.fromMap(rows.first);
  }

  Future<int> insert(TradeRecord t) async {
    final map = t.toMap();
    if (map['id'] == 0) map.remove('id'); // id=0 由 AUTOINCREMENT 生成
    return (await AppDatabase.database).insert('trade_record', map);
  }

  Future<List<TradeRecord>> all() async {
    final rows = await (await AppDatabase.database).query(
      'trade_record',
      orderBy: 'time ASC',
    );
    return rows.map(TradeRecord.fromMap).toList();
  }

  Future<void> delete(int id) async {
    await (await AppDatabase.database).delete(
      'trade_record',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
