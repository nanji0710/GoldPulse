// test/check_alerts_test.dart
// 验证 checkAlertsProvider：遍历启用提醒，命中即通知 + recordTrigger 自增。
// 使用 sqflite_common_ffi（内存/临时库）+ 假通知插件，避免平台通道调用。
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/alert_dao.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:goldpulse/state/alert_provider.dart';
import 'test_db.dart';

/// 假通知插件：implements + noSuchMethod 拦截 show，避免 MissingPluginException。
class _FakeNotifications implements FlutterLocalNotificationsPlugin {
  final notifications = <(String, String)>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #show) {
      final title = invocation.positionalArguments[1] as String? ?? '';
      final body = invocation.positionalArguments[2] as String? ?? '';
      notifications.add((title, body));
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  setUpAll(setUpTestDatabase); // 独立 FFI 数据库目录，避免并行 isolate 锁竞争
  setUp(() async {
    await AppDatabase.reset(); // 每个用例重建库
  });

  test('checkAlertsProvider 命中启用提醒：通知 + trigger 自增', () async {
    final plugin = _FakeNotifications();
    final container = ProviderContainer(overrides: [
      notificationsPluginProvider.overrideWithValue(plugin),
    ]);
    addTearDown(container.dispose);
    final dao = AlertDao();
    final up = await dao.insert(Alert(type: 'price_up', target: 800, enable: true));
    final down = await dao.insert(Alert(type: 'price_down', target: 700, enable: true));
    await dao.insert(Alert(type: 'profit_target', target: 500000, enable: true)); // 不命中

    await container.read(checkAlertsProvider((price: 805, assetValue: 0, totalCost: 0)).future);

    expect(plugin.notifications, hasLength(1));
    expect(plugin.notifications.single.$1, '金脉提醒');
    expect((await dao.get(up))!.triggerCount, 1);
    expect((await dao.get(down))!.triggerCount, 0);
  });

  test('checkAlertsProvider 禁用提醒不通知', () async {
    final plugin = _FakeNotifications();
    final container = ProviderContainer(overrides: [
      notificationsPluginProvider.overrideWithValue(plugin),
    ]);
    addTearDown(container.dispose);
    final dao = AlertDao();
    await dao.insert(Alert(type: 'price_up', target: 800, enable: false));

    await container.read(checkAlertsProvider((price: 900, assetValue: 0, totalCost: 0)).future);

    expect(plugin.notifications, isEmpty);
  });
}
