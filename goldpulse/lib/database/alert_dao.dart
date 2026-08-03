// lib/database/alert_dao.dart
import '../database/app_database.dart';
import '../models/alert.dart';

class AlertDao {
  Future<List<Alert>> list() async {
    final rows = await (await AppDatabase.database).query('alert', orderBy: 'id');
    return rows.map(Alert.fromMap).toList();
  }
  Future<Alert?> get(int id) async {
    final rows = await (await AppDatabase.database).query('alert', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Alert.fromMap(rows.first);
  }
  Future<int> insert(Alert a) async {
    final map = a.toMap();
    if (map['id'] == 0) map.remove('id'); // id=0 由 AUTOINCREMENT 生成
    return (await AppDatabase.database).insert('alert', map);
  }
  Future<void> toggle(int id, bool enable) async {
    await (await AppDatabase.database).update('alert', {'enable': enable ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> recordTrigger(int id) async {
    await (await AppDatabase.database).update('alert',
        {'trigger_count': -1, 'last_triggered': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
  }
  Future<void> delete(int id) async {
    await (await AppDatabase.database).delete('alert', where: 'id = ?', whereArgs: [id]);
  }
}
