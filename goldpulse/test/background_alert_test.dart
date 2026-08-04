// test/background_alert_test.dart
// Task 5：后台提醒检查 runBackgroundAlertCheck 单测。
// 注入固定价假 PriceApi + 真实 FFI 测试库（AlertDao/HoldingDao）+ 记录型 showNotification，
// 断言：命中提醒发通知（文案正确）、禁用提醒不通知、拉价失败静默返回。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/alert_dao.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/services/background_alert.dart';
import 'package:goldpulse/services/price_api.dart';
import 'test_db.dart';

/// 固定价假行情源：返回注入的固定价；[result] 为 null 时模拟"全部行情源拉价失败"。
class _FixedApi extends PriceApi {
  _FixedApi(this.result) : super(dio: Dio());
  final GoldPrice? result;
  int calls = 0;
  @override
  Future<GoldPrice?> fetchGoldPriceWithFallback(String code) async {
    calls++;
    return result;
  }
}

/// 记录型通知回调：把 title/body 收进列表，供断言。
class _RecordingNotifier {
  final notifications = <(String, String)>[];
  Future<void> call(String title, String body) async {
    notifications.add((title, body));
  }
}

void main() {
  setUpAll(setUpTestDatabase); // 独立 FFI 数据库目录，避免并行 isolate 锁竞争
  setUp(() async {
    await AppDatabase.reset(); // 每个用例重建库
  });

  GoldPrice fixedPrice(double p) => GoldPrice(
      code: 'SGE-Au(T+D)', price: p, change: 10, percent: 1.25,
      preClose: p - 10, time: DateTime.now().millisecondsSinceEpoch);

  test('命中启用价格提醒：通知触发且文案为 describe', () async {
    final notifier = _RecordingNotifier();
    final api = _FixedApi(fixedPrice(805));
    await AlertDao().insert(Alert(type: 'price_up', target: 800, enable: true));
    await AlertDao().insert(Alert(type: 'price_down', target: 700, enable: true)); // 不命中
    await HoldingDao().insert(
        Holding(name: 'Au9999', kind: 'au9999', amount: 100, totalCost: 70000, createdAt: 1));

    await runBackgroundAlertCheck(
      api: api,
      alertDao: AlertDao(),
      holdingDao: HoldingDao(),
      showNotification: notifier.call,
    );

    expect(notifier.notifications, hasLength(1)); // 仅 price_up 命中
    expect(notifier.notifications.single.$1, '金脉提醒');
    expect(notifier.notifications.single.$2, 'Au9999 价格 ≥ 800.00 元/g');
  });

  test('命中收益提醒：收益（资产-成本）达标才触发', () async {
    final notifier = _RecordingNotifier();
    final api = _FixedApi(fixedPrice(850));
    // 10g × 850 = 8500 元资产，成本 7500 → 收益 1000 元。
    // 目标 1000 达标命中；目标 1500 收益不足不命中（总资产恒大但收益不足不再误触发）。
    await AlertDao().insert(Alert(type: 'profit_target', target: 1000, enable: true));
    await AlertDao().insert(Alert(type: 'profit_target', target: 1500, enable: true));
    await HoldingDao().insert(
        Holding(name: 'Au9999', kind: 'au9999', amount: 10, totalCost: 7500, createdAt: 1));

    await runBackgroundAlertCheck(
      api: api,
      alertDao: AlertDao(),
      holdingDao: HoldingDao(),
      showNotification: notifier.call,
    );

    expect(notifier.notifications, hasLength(1)); // 仅目标 1000 命中
    expect(notifier.notifications.single.$2, '收益 ≥ 1000 元');
  });

  test('禁用提醒即使价格命中也不通知', () async {
    final notifier = _RecordingNotifier();
    final api = _FixedApi(fixedPrice(900));
    await AlertDao().insert(Alert(type: 'price_up', target: 800, enable: false));

    await runBackgroundAlertCheck(
      api: api,
      alertDao: AlertDao(),
      holdingDao: HoldingDao(),
      showNotification: notifier.call,
    );

    expect(notifier.notifications, isEmpty);
  });

  test('拉价返回 null：静默返回，不发通知也不崩溃', () async {
    final notifier = _RecordingNotifier();
    final api = _FixedApi(null);
    await AlertDao().insert(Alert(type: 'price_up', target: 800, enable: true));

    await runBackgroundAlertCheck(
      api: api,
      alertDao: AlertDao(),
      holdingDao: HoldingDao(),
      showNotification: notifier.call,
    );

    expect(api.calls, 1);
    expect(notifier.notifications, isEmpty);
  });
}
