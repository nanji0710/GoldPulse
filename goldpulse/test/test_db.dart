// test/test_db.dart
// 共享测试初始化：每个测试文件（isolate）使用独立的 FFI 数据库目录。
// 默认路径 .dart_tool/sqflite_common_ffi/databases 被所有并行 isolate 共享，
// 并发读写同一 goldpulse.db 会触发 "database is locked"（SQLITE_BUSY）随机失败。
import 'dart:io';

import 'package:goldpulse/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 初始化 FFI 并把数据库路径指到本文件独有的临时目录。
/// 每个测试文件的 setUpAll 调用一次即可。
Future<void> setUpTestDatabase() async {
  sqfliteFfiInit();
  AppDatabase.databaseFactory = databaseFactoryFfi;
  final tmp = await Directory.systemTemp.createTemp('goldpulse_test_');
  await databaseFactoryFfi.setDatabasesPath(tmp.path);
}
