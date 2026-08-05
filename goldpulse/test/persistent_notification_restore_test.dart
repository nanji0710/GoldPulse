// test/persistent_notification_restore_test.dart
// Task 5 启动恢复：快照纯函数 / 恢复判定 / 失败静默兜底。
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/state/persistent_notification_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('buildNotificationSnapshot', () {
    const holdings = [
      Holding(id: 1, name: 'A', kind: 'accumulation', amount: 10,
          totalCost: 9000, boughtCost: 10000, createdAt: 1),
      Holding(id: 2, name: 'B', kind: 'accumulation', amount: 5,
          totalCost: 4700, boughtCost: 5000, createdAt: 2),
      // 其他品种不参与汇总
      Holding(id: 3, name: 'C', kind: 'icbc', amount: 20,
          totalCost: 18000, boughtCost: 20000, createdAt: 3),
    ];
    const trades = [
      // 持仓 1 卖出 2g @ 920，手续费 1.5；持仓 2 卖出 1g @ 950，手续费 2
      TradeRecord(id: 1, holdingId: 1, type: 'sell', amount: 2,
          price: 920, fee: 1.5, time: 1),
      TradeRecord(id: 2, holdingId: 2, type: 'sell', amount: 1,
          price: 950, fee: 2, time: 2),
      // 买入记录不计入卖出净得
      TradeRecord(id: 3, holdingId: 1, type: 'buy', amount: 2,
          price: 880, fee: 0, time: 3),
      // 其他品种（icbc）的卖出不计入 accumulation
      TradeRecord(id: 4, holdingId: 3, type: 'sell', amount: 1,
          price: 900, fee: 0, time: 4),
    ];

    test('汇总所选品种：克重/剩余成本/累计投入求和，卖出净得=Σ(克重×价−手续费)', () {
      final s = buildNotificationSnapshot(
          kind: 'accumulation', holdings: holdings, trades: trades);
      expect(s, isNotNull);
      expect(s!.kind, 'accumulation');
      expect(s.grams, closeTo(15, 1e-9));
      expect(s.totalCost, closeTo(13700, 1e-9));
      expect(s.boughtCost, closeTo(15000, 1e-9));
      // 2×920 − 1.5 + 1×950 − 2 = 1838.5 + 948 = 2786.5
      expect(s.soldNet, closeTo(2786.5, 1e-9));
    });

    test('该品种无持仓 → 返回 null（通知保持无持仓，不更新）', () {
      expect(buildNotificationSnapshot(
          kind: 'minsheng', holdings: holdings, trades: trades), isNull);
      expect(buildNotificationSnapshot(
          kind: 'accumulation', holdings: const [], trades: trades), isNull);
    });
  });

  group('loadPersistentNotificationRestoreConfig', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('未开启 → null（无需恢复服务）', () async {
      expect(await loadPersistentNotificationRestoreConfig(), isNull);
    });

    test('已开启 → 返回白名单校验后的配置', () async {
      SharedPreferences.setMockInitialValues({
        'notificationBarEnabled': true,
        'notificationBarKind': 'minsheng',
        'notificationBarIntervalSeconds': 30,
        'notificationBarMetrics': '["avgCost","bogus","profitRate"]',
      });
      final cfg = await loadPersistentNotificationRestoreConfig();
      expect(cfg, isNotNull);
      expect(cfg!.enabled, isTrue);
      expect(cfg.kind, 'minsheng');
      expect(cfg.intervalSeconds, 30);
      expect(cfg.metrics, ['avgCost', 'profitRate']); // 未知指标过滤
    });

    test('已开启但品种/频率非法 → 回退默认，避免脏配置启动服务', () async {
      SharedPreferences.setMockInitialValues({
        'notificationBarEnabled': true,
        'notificationBarKind': 'hacker',
        'notificationBarIntervalSeconds': 7,
      });
      final cfg = await loadPersistentNotificationRestoreConfig();
      expect(cfg, isNotNull);
      expect(cfg!.kind, 'accumulation');
      expect(cfg.intervalSeconds, 10);
    });
  });

  group('restorePersistentNotificationFromPrefs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('未开启 → 不调用启动动作，静默返回', () async {
      var booted = false;
      await restorePersistentNotificationFromPrefs(
          bootService: (_) async => booted = true);
      expect(booted, isFalse);
    });

    test('已开启 → 以 prefs 配置（品种/频率/指标）启动服务', () async {
      SharedPreferences.setMockInitialValues({
        'notificationBarEnabled': true,
        'notificationBarKind': 'icbc',
        'notificationBarIntervalSeconds': 30,
        'notificationBarMetrics': '["avgCost","todayProfit"]',
      });
      PersistentNotificationConfig? booted;
      await restorePersistentNotificationFromPrefs(
          bootService: (cfg) async => booted = cfg);
      expect(booted, isNotNull);
      final cfg = booted!;
      expect(cfg.kind, 'icbc');
      expect(cfg.intervalSeconds, 30);
      expect(cfg.metrics, ['avgCost', 'todayProfit']);
    });

    test('启动动作抛异常 → 静默兜底，不影响启动', () async {
      SharedPreferences.setMockInitialValues({'notificationBarEnabled': true});
      // 插件/数据库不可用场景：异常必须被内部捕获，调用方不感知。
      await expectLater(
          restorePersistentNotificationFromPrefs(
              bootService: (_) async => throw StateError('plugin unavailable')),
          completes);
    });
  });

  group('syncNotificationPositionIfEnabled', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('服务未启用 → 直接返回（不抛异常、不访问 DB）', () async {
      await syncNotificationPositionIfEnabled();
    });

    test('服务启用但 DB 不可用（测试环境无原生 sqflite）→ 静默兜底不抛', () async {
      SharedPreferences.setMockInitialValues({
        'notificationBarEnabled': true,
        'notificationBarKind': 'accumulation',
        'notificationBarIntervalSeconds': 10,
      });
      // HoldingDao().list() 在测试环境会因缺少原生 sqflite 抛 MissingPluginException，
      // 被 syncNotificationPositionIfEnabled 内部 catch 吞掉 → 不抛异常。
      await syncNotificationPositionIfEnabled();
    });
  });
}
