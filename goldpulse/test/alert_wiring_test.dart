// test/alert_wiring_test.dart
// C1 + I3b 回归测试：
//   - 行情轮询收到新价后确实触发 checkAlertsProvider（价格/资产命中即通知）；
//   - 行情源抛意外异常（畸形响应）时轮询不中断，不进 AsyncError。
// 通过 isTradingNowProvider 注入"交易中"与极短刷新间隔，确定性驱动真实轮询循环。
import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/alert_dao.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/price_dao.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/services/price_api.dart';
import 'package:goldpulse/state/alert_provider.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'test_db.dart';

/// 假通知插件：implements + noSuchMethod 拦截 show，避免平台通道调用。
class _FakeNotifications implements FlutterLocalNotificationsPlugin {
  final notifications = <(String, String)>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #show) {
      notifications.add((
        invocation.positionalArguments[1] as String? ?? '',
        invocation.positionalArguments[2] as String? ?? '',
      ));
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

/// 仅首轮返回新价的假行情源：让告警判定恰好跑一次，便于断言。
class _OnceApi extends PriceApi {
  _OnceApi() : super(dio: Dio());
  int calls = 0;
  @override
  Future<GoldPrice?> fetchGoldPriceWithFallback(String code) async {
    calls++;
    if (calls > 1) return null;
    return GoldPrice(code: code, price: 805, change: 10, percent: 1.25, preClose: 795,
        time: DateTime.now().millisecondsSinceEpoch);
  }
}

/// 首轮返回新价、之后抛非 Dio 异常的假行情源（模拟畸形响应/解析异常）。
class _ThrowingApi extends PriceApi {
  _ThrowingApi() : super(dio: Dio());
  int calls = 0;
  @override
  Future<GoldPrice?> fetchGoldPriceWithFallback(String code) async {
    calls++;
    if (calls == 1) {
      return GoldPrice(code: code, price: 805, change: 10, percent: 1.25, preClose: 795,
          time: DateTime.now().millisecondsSinceEpoch);
    }
    throw Exception('malformed response');
  }
}

/// 仅首轮返回新价的假积存金行情源：让 accumulation 轮询恰好跑一次判定。
class _AccOnceApi extends PriceApi {
  _AccOnceApi() : super(dio: Dio());
  int calls = 0;
  @override
  Future<GoldPrice?> fetchAccumulationPriceWithFallback() async {
    calls++;
    if (calls > 1) return null;
    return GoldPrice(code: 'CZB-JCJ', price: 820, change: 5, percent: 0.6, preClose: 815,
        time: DateTime.now().millisecondsSinceEpoch);
  }
}

void main() {
  setUpAll(setUpTestDatabase); // 独立 FFI 数据库目录，避免并行 isolate 锁竞争
  setUp(() async {
    await AppDatabase.reset(); // 每个用例重建内存库
  });

  test('行情轮询拉到新价后触发提醒判定并入库', () async {
    final plugin = _FakeNotifications();
    final api = _OnceApi();
    await AlertDao().insert(Alert(type: 'price_up', target: 800, enable: true));
    await AlertDao().insert(Alert(type: 'price_down', target: 700, enable: true)); // 不命中
    await HoldingDao().insert(
        Holding(name: 'Au9999', kind: 'au9999', amount: 100, totalCost: 70000, createdAt: 1));

    final container = ProviderContainer(overrides: [
      priceApiProvider.overrideWithValue(api),
      notificationsPluginProvider.overrideWithValue(plugin),
      isTradingNowProvider.overrideWithValue(() => true),
      refreshIntervalProvider.overrideWith((ref) => Future.value(const Duration(milliseconds: 5))),
    ]);
    final sub = container.listen(priceProvider, (_, _) {});
    addTearDown(container.dispose);
    addTearDown(sub.close);

    // 等轮询跑至少一轮（真实异步，非 FakeAsync）。
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(api.calls, greaterThanOrEqualTo(1));
    expect(plugin.notifications, hasLength(1)); // 仅 price_up 命中
    expect(plugin.notifications.single.$1, '金脉提醒');
    expect(await PriceDao().count(), 1); // 新价已入库
  });

  test('行情源抛异常时轮询不中断（保留缓存，不进 AsyncError）', () async {
    final api = _ThrowingApi();
    final container = ProviderContainer(overrides: [
      priceApiProvider.overrideWithValue(api),
      notificationsPluginProvider.overrideWithValue(_FakeNotifications()),
      isTradingNowProvider.overrideWithValue(() => true),
      refreshIntervalProvider.overrideWith((ref) => Future.value(const Duration(milliseconds: 5))),
    ]);
    final sub = container.listen(priceProvider, (_, _) {});
    addTearDown(container.dispose);
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(api.calls, greaterThanOrEqualTo(2)); // 首轮成功，其后多次抛异常
    expect(container.read(priceProvider).hasError, isFalse); // 流未被异常打死
  });

  test('品种过滤：accumulation 提醒不在 au9999 判定中触发，在 accumulation 判定中触发', () async {
    final plugin = _FakeNotifications();
    final dao = AlertDao();
    await dao.insert(Alert(type: 'price_up', kind: 'accumulation', target: 800, enable: true));
    await dao.insert(Alert(type: 'price_down', kind: 'au9999', target: 700, enable: true)); // 不命中

    // Au9999 判定：accumulation 品种提醒被过滤，不触发。
    await runAlertChecks(dao: dao, plugin: plugin, price: 805, assetValue: 0, totalCost: 0, kind: 'au9999');
    expect(plugin.notifications, isEmpty);

    // accumulation 判定：命中 accumulation 品种提醒。
    await runAlertChecks(dao: dao, plugin: plugin, price: 805, assetValue: 0, totalCost: 0, kind: 'accumulation');
    expect(plugin.notifications, hasLength(1));
    expect(plugin.notifications.single.$1, '金脉提醒');
  });

  test('profit_target 不区分品种：仅在 Au9999 轮询（checkProfitTarget=true）触发一次', () async {
    final plugin = _FakeNotifications();
    final dao = AlertDao();
    await dao.insert(Alert(type: 'profit_target', target: 1000, enable: true));

    // icbc/accumulation 轮询 checkProfitTarget=false：不重复触发收益提醒。
    await runAlertChecks(dao: dao, plugin: plugin, price: 850, assetValue: 9000, totalCost: 7500,
        kind: 'icbc', checkProfitTarget: false);
    expect(plugin.notifications, isEmpty);

    // Au9999 轮询 checkProfitTarget=true：触发收益提醒。
    await runAlertChecks(dao: dao, plugin: plugin, price: 850, assetValue: 9000, totalCost: 7500,
        kind: 'au9999');
    expect(plugin.notifications, hasLength(1));
    expect(plugin.notifications.single.$2, '收益 ≥ 1000 元');
  });

  test('accumulation 轮询触发同品种价格提醒并带品种文案', () async {
    final plugin = _FakeNotifications();
    final api = _AccOnceApi();
    await AlertDao().insert(Alert(type: 'price_up', kind: 'accumulation', target: 800, enable: true));
    await AlertDao().insert(Alert(type: 'price_up', kind: 'au9999', target: 800, enable: true)); // 品种不符，不触发
    await HoldingDao().insert(
        Holding(name: '浙商积存金', kind: 'accumulation', amount: 100, totalCost: 70000, createdAt: 1));

    final container = ProviderContainer(overrides: [
      priceApiProvider.overrideWithValue(api),
      notificationsPluginProvider.overrideWithValue(plugin),
      isTradingNowProvider.overrideWithValue(() => true),
      refreshIntervalProvider.overrideWith((ref) => Future.value(const Duration(milliseconds: 5))),
    ]);
    final sub = container.listen(accumulationPriceProvider, (_, _) {});
    addTearDown(container.dispose);
    addTearDown(sub.close);

    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(api.calls, greaterThanOrEqualTo(1));
    expect(plugin.notifications, hasLength(1)); // 仅 accumulation 品种提醒命中
    expect(plugin.notifications.single.$2, '浙商积存金 价格 ≥ 800.00 元/g');
  });
}
