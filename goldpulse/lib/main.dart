// lib/main.dart
// 应用入口：通知初始化 + WorkManager 后台轮询注册 + 依赖注入。
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
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
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  await Workmanager().registerPeriodicTask('price-alert', 'checkAlerts',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingWorkPolicy.keep);

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
    // 后台任务：拉最新价 → 对启用的提醒做判定 → 命中则通知。
    // 复用 PriceApi/AlertDao/AlertService，需在 background isolate 中独立初始化 sqflite
    // （openDatabase 直接打开文件路径，参考 workmanager 官方文档）。
    // MVP 范围：仅注册任务并返回成功，真实后台抓取留待后续细化。
    return Future.value(true);
  });
}
