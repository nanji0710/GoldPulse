// lib/services/backup_service.dart
// 数据备份：导出三张业务表（持仓/交易/提醒）为 JSON，导入时校验版本并重建库。
import 'dart:convert';

import '../database/app_database.dart';
import '../models/alert.dart';
import '../models/holding.dart';
import '../models/trade_record.dart';

class BackupService {
  /// 导出全量数据为 JSON 字符串（含版本号便于迁移）。
  Future<String> exportJson({
    required List<Holding> holdings,
    required List<TradeRecord> trades,
    required List<Alert> alerts,
  }) async {
    return jsonEncode({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'holdings': holdings.map((h) => h.toMap()).toList(),
      'trades': trades.map((t) => t.toMap()).toList(),
      'alerts': alerts.map((a) => a.toMap()).toList(),
    });
  }

  /// 解析导入内容；非法 JSON 抛 [FormatException]。
  static Map<String, dynamic> parseImport(String raw) {
    final map = jsonDecode(raw);
    if (map is! Map<String, dynamic>) throw const FormatException('备份文件结构非法');
    return map;
  }

  /// 校验并重建数据库：version 必须为 1，字段必须齐备；随后清空四张表并
  /// 按原 id 重建 holdings/trades/alerts（保留外键关联）。
  /// 失败（版本不支持 / 结构非法）抛 [FormatException]，此时不落任何数据。
  Future<void> importJson(String raw) async {
    final map = parseImport(raw);
    if (map['version'] != 1) throw const FormatException('不支持的备份版本');
    final holdings = map['holdings'];
    final trades = map['trades'];
    final alerts = map['alerts'];
    if (holdings is! List || trades is! List || alerts is! List) {
      throw const FormatException('备份字段缺失或非法');
    }

    final db = await AppDatabase.database;
    await db.transaction((txn) async {
      await txn.delete('gold_price');
      await txn.delete('trade_record');
      await txn.delete('holding');
      await txn.delete('alert');
      // 保留原 id：AUTOINCREMENT 表允许显式插入 id，且 sqlite_sequence 自动跟进，
      // 从而保证 trade.holding_id / 各表外键关系在恢复后依然成立。
      for (final m in holdings) {
        await txn.insert('holding', (m as Map).cast<String, Object?>());
      }
      for (final m in trades) {
        await txn.insert('trade_record', (m as Map).cast<String, Object?>());
      }
      for (final m in alerts) {
        await txn.insert('alert', (m as Map).cast<String, Object?>());
      }
    });
  }
}
