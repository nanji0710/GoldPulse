// lib/services/alert_service.dart
// 提醒判定（纯逻辑）与本地通知。
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert.dart';

class AlertService {
  /// 纯判定：某条提醒在给定行情/资产下是否命中。
  static bool matches(Alert a, {required double price, required double assetValue, required double totalCost}) {
    if (!a.enable) return false;
    switch (a.type) {
      case 'price_up': return price >= a.target;
      case 'price_down': return price <= a.target;
      case 'profit_target': return (assetValue - totalCost) >= a.target;
      default: return false;
    }
  }

  static String describe(Alert a) => switch (a.type) {
        'price_up' => 'Au9999 价格 ≥ ${a.target.toStringAsFixed(2)} 元/g',
        'price_down' => 'Au9999 价格 ≤ ${a.target.toStringAsFixed(2)} 元/g',
        'profit_target' => '收益 ≥ ${a.target.toStringAsFixed(0)} 元',
        _ => '未知提醒',
      };

  static Future<void> showNotification(
      FlutterLocalNotificationsPlugin plugin, String title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails('gold_alerts', '价格提醒',
          channelDescription: '黄金价格与收益目标提醒',
          importance: Importance.high, priority: Priority.high));
    await plugin.show(0, title, body, details);
  }
}
