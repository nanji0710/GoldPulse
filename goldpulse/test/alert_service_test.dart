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
  test('profit_target：资产价值 >= 目标金额 触发', () {
    final a = Alert(type: 'profit_target', target: 400000, enable: true);
    expect(AlertService.matches(a, price: 0, assetValue: 450000, totalCost: 0), isTrue);
    expect(AlertService.matches(a, price: 0, assetValue: 300000, totalCost: 0), isFalse);
  });
  test('disabled 提醒不触发', () {
    final a = Alert(type: 'price_up', target: 800, enable: false);
    expect(AlertService.matches(a, price: 900, assetValue: 0, totalCost: 0), isFalse);
  });
  test('描述文案', () {
    expect(AlertService.describe(const Alert(type: 'price_up', target: 800, enable: true)), 'Au9999 价格 ≥ 800.00 元/g');
  });
}
