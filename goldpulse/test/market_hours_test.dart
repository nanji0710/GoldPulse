// test/market_hours_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/market_hours.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) {
    // 固定用 2026-08-03（周一）
    return DateTime(2026, 8, 3, hour, minute);
  }

  test('日盘交易中', () {
    expect(MarketHours.isTrading(at(10)), isTrue);
    expect(MarketHours.phaseAt(at(10)), MarketPhase.trading);
  });
  test('午间休市', () {
    expect(MarketHours.phaseAt(at(12)), MarketPhase.lunchBreak);
  });
  test('下午盘交易中', () {
    expect(MarketHours.phaseAt(at(14)), MarketPhase.trading);
  });
  test('收盘（夜盘前）', () {
    expect(MarketHours.phaseAt(at(17)), MarketPhase.closed);
  });
  test('夜盘交易中', () {
    expect(MarketHours.isTrading(at(22)), isTrue);
  });
  test('凌晨夜盘（次日 1 点）仍在交易', () {
    expect(MarketHours.isTrading(DateTime(2026, 8, 4, 1)), isTrue);
  });
  test('凌晨 3 点休市', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 4, 3)), MarketPhase.closed);
  });
  test('周日休市（weekend）', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 2, 12)), MarketPhase.weekend);
  });
}
