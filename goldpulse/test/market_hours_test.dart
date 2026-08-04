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
  test('周一凌晨 0:00–2:30 休市（周日无夜盘）', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 3, 1)), MarketPhase.closed);
  });
  test('周六凌晨 2:00 仍属周五夜盘尾', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 1, 2)), MarketPhase.trading);
  });
  test('凌晨 2:45 已收盘（夜盘 2:30 截止）', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 4, 2, 45)), MarketPhase.closed);
  });
  test('周六凌晨 2:45 休市', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 1, 2, 45)), MarketPhase.weekend);
  });
  // ---- 下一开市时刻（精确到时段）----
  test('午间休市 → 当日 13:30 恢复', () {
    final next = MarketHours.nextOpen(DateTime(2026, 8, 3, 12, 0))!;
    expect(next.hour, 13);
    expect(next.minute, 30);
    expect(next.day, 3);
  });
  test('15:30 收盘 → 当日 21:00 夜盘', () {
    final next = MarketHours.nextOpen(DateTime(2026, 8, 3, 17, 0))!;
    expect(next.hour, 21);
    expect(next.day, 3);
  });
  test('凌晨 3 点 → 当日 9:00 开盘', () {
    final next = MarketHours.nextOpen(DateTime(2026, 8, 4, 3, 0))!;
    expect(next.hour, 9);
    expect(next.day, 4);
  });
  test('周末 → 下周一 9:00 开盘', () {
    final next = MarketHours.nextOpen(DateTime(2026, 8, 2, 12, 0))!; // 周日
    expect(next.hour, 9);
    expect(next.weekday, DateTime.monday);
  });
  // ---- 时段标签与恢复提示 ----
  test('时段标签', () {
    expect(MarketHours.label(DateTime(2026, 8, 3, 10)), '交易中');
    expect(MarketHours.label(DateTime(2026, 8, 3, 12)), '午间休市');
    expect(MarketHours.label(DateTime(2026, 8, 3, 17)), '已收盘');
    expect(MarketHours.label(DateTime(2026, 8, 2, 12)), '休市');
  });
  test('恢复提示文案', () {
    expect(MarketHours.resumeHint(DateTime(2026, 8, 3, 12)), '13:30 恢复交易');
    expect(MarketHours.resumeHint(DateTime(2026, 8, 3, 17)), '21:00 开盘');
    expect(MarketHours.resumeHint(DateTime(2026, 8, 2, 12)), '周一 09:00 开盘');
    expect(MarketHours.resumeHint(DateTime(2026, 8, 3, 10)), isNull);
  });
}
