// test/persistent_notification_provider_test.dart
// 常驻通知栏配置 provider：默认值 / 8 选 4 限制 / 切换持久化 / loadFromPrefs 恢复。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/state/persistent_notification_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('默认配置：关闭、浙商、10 秒、4 个默认指标', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(persistentNotificationConfigProvider);
    expect(c.enabled, isFalse);
    expect(c.kind, 'accumulation');
    expect(c.intervalSeconds, 10);
    expect(c.metrics, hasLength(4));
    expect(c.metrics, ['avgCost', 'floatingProfit', 'profitRate', 'todayProfit']);
  });

  test('选第 5 个指标被拒绝（8 选 4 限制）', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier =
        container.read(persistentNotificationConfigProvider.notifier);
    // 已有 4 个，再选一个 → 返回 false 且列表仍 4 个
    expect(await notifier.toggleMetric('cumulativeProfit'), isFalse);
    expect(container.read(persistentNotificationConfigProvider).metrics,
        hasLength(4));
  });

  test('取消已选指标成功且列表更新', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier =
        container.read(persistentNotificationConfigProvider.notifier);
    expect(await notifier.toggleMetric('avgCost'), isTrue);
    expect(container.read(persistentNotificationConfigProvider).metrics,
        isNot(contains('avgCost')));
    expect(container.read(persistentNotificationConfigProvider).metrics,
        hasLength(3));
    // 移除后可重新加入
    expect(await notifier.toggleMetric('avgCost'), isTrue);
    expect(container.read(persistentNotificationConfigProvider).metrics,
        contains('avgCost'));
  });

  test('切换品种后配置持久化到 SharedPreferences', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(persistentNotificationConfigProvider.notifier)
        .setKind('icbc');
    expect(container.read(persistentNotificationConfigProvider).kind, 'icbc');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('notificationBarKind'), 'icbc');
  });

  test('loadFromPrefs 恢复已存配置', () async {
    SharedPreferences.setMockInitialValues({
      'notificationBarEnabled': true,
      'notificationBarKind': 'minsheng',
      'notificationBarIntervalSeconds': 30,
      'notificationBarMetrics':
          '["avgCost","todayProfit","cumulativeProfit","floatingProfit"]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(persistentNotificationConfigProvider.notifier)
        .loadFromPrefs();
    final c = container.read(persistentNotificationConfigProvider);
    expect(c.enabled, isTrue);
    expect(c.kind, 'minsheng');
    expect(c.intervalSeconds, 30);
    expect(c.metrics,
        ['avgCost', 'todayProfit', 'cumulativeProfit', 'floatingProfit']);
  });

  test('loadFromPrefs 白名单：非法品种/频率/指标回退或过滤', () async {
    SharedPreferences.setMockInitialValues({
      'notificationBarEnabled': true,
      'notificationBarKind': 'hacker',
      'notificationBarIntervalSeconds': 7,
      'notificationBarMetrics': '["avgCost","bogus","profitRate"]',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(persistentNotificationConfigProvider.notifier)
        .loadFromPrefs();
    final c = container.read(persistentNotificationConfigProvider);
    expect(c.enabled, isTrue);
    expect(c.kind, 'accumulation'); // 非法品种回退默认
    expect(c.intervalSeconds, 10); // 非法频率回退默认
    expect(c.metrics, contains('avgCost'));
    expect(c.metrics, contains('profitRate'));
    expect(c.metrics, isNot(contains('bogus'))); // 未知指标过滤
    expect(c.metrics, hasLength(2));
  });
}
