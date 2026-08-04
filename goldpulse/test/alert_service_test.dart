// test/alert_service_test.dart
// Task 13：提醒判定纯逻辑测试（5 用例）。
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:goldpulse/services/alert_service.dart';

void main() {
  test('price_up：现价 >= 目标 触发', () {
    final a = Alert(type: 'price_up', target: 800, enable: true);
    expect(AlertService.matches(a, price: 805, assetValue: 0, totalCost: 0), isTrue);
    expect(AlertService.matches(a, price: 795, assetValue: 0, totalCost: 0), isFalse);
  });
  test('price_down：现价 <= 目标 触发', () {
    final a = Alert(type: 'price_down', target: 750, enable: true);
    expect(AlertService.matches(a, price: 748, assetValue: 0, totalCost: 0), isTrue);
  });
  test('profit_target：收益（资产价值-成本）>= 目标金额 触发', () {
    final a = Alert(type: 'profit_target', target: 4000, enable: true);
    // 收益 5000（资产 10000 - 成本 5000）>= 目标 4000 → 命中
    expect(AlertService.matches(a, price: 0, assetValue: 10000, totalCost: 5000), isTrue);
    // 收益 4000（资产 10000 - 成本 6000）== 目标 4000 → 边界命中
    expect(AlertService.matches(a, price: 0, assetValue: 10000, totalCost: 6000), isTrue);
    // 收益 3000（资产 10000 - 成本 7000）< 目标 4000 → 不命中
    expect(AlertService.matches(a, price: 0, assetValue: 10000, totalCost: 7000), isFalse);
    // 旧逻辑误判场景：资产价值恒大但成本也高 → 收益 1000 不足 → 不命中
    expect(AlertService.matches(a, price: 0, assetValue: 400000, totalCost: 399000), isFalse);
  });
  test('disabled 提醒不触发', () {
    final a = Alert(type: 'price_up', target: 800, enable: false);
    expect(AlertService.matches(a, price: 900, assetValue: 0, totalCost: 0), isFalse);
  });
  test('描述文案', () {
    expect(AlertService.describe(const Alert(type: 'price_up', target: 800, enable: true)), 'Au9999 价格 ≥ 800.00 元/g');
    expect(AlertService.describe(const Alert(type: 'profit_target', target: 400000, enable: true)), '收益 ≥ 400000 元');
  });
}
