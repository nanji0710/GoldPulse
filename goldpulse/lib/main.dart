// lib/main.dart
// 应用入口：通知初始化 + WorkManager 后台轮询注册 + 依赖注入。
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'database/alert_dao.dart';
import 'database/app_database.dart';
import 'database/holding_dao.dart';
import 'services/alert_service.dart';
import 'services/background_alert.dart';
import 'services/price_api.dart';
import 'state/alert_provider.dart';
import 'state/price_provider.dart';

final notificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 本地通知初始化（Android 通道；图标复用启动图标）。
  const init = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notificationsPlugin.initialize(const InitializationSettings(android: init));
  // Android 13+（API 33）需运行时通知权限，否则通知不会展示。
  await notificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  // WorkManager 后台轮询：注册每 15 分钟一次的 'checkAlerts' 任务。
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask('price-alert', 'checkAlerts',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);

  final dio = Dio(BaseOptions(headers: {'User-Agent': 'goldpulse/1.0'}));
  runApp(ProviderScope(
    overrides: [
      dioProvider.overrideWithValue(dio),
      notificationsPluginProvider.overrideWithValue(notificationsPlugin),
    ],
    child: const GoldPulseApp(),
  ));
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // 后台任务：拉最新价 → 对启用的提醒做判定 → 命中则通知。
      // background isolate 与主 isolate 相互独立，需在此独立初始化
      // 通知插件与 sqflite（AppDatabase.database 打开文件路径数据库，参考其现有打开模式）。
      final dio = Dio(BaseOptions(headers: {'User-Agent': 'goldpulse/1.0'}));
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      await AppDatabase.database; // 确保数据库已打开（独立 isolate 内各自初始化）
      await runBackgroundAlertCheck(
        api: PriceApi(dio: dio),
        alertDao: AlertDao(),
        holdingDao: HoldingDao(),
        showNotification: (title, body) =>
            AlertService.showNotification(plugin, title, body),
      );
    } catch (_) {
      // 后台任务失败静默，不得崩溃（runBackgroundAlertCheck 内部已有兜底）。
    }
    return Future.value(true);
  });
}
