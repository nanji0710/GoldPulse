import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/constants/app_theme.dart';

void main() {
  test('主题色符合黑金规范', () {
    expect(AppTheme.background, const Color(0xFF101216));
    expect(AppTheme.card, const Color(0xFF181B22));
    expect(AppTheme.gold, const Color(0xFFD9A441));
    expect(AppTheme.up, const Color(0xFFE5484D));   // 红涨
    expect(AppTheme.down, const Color(0xFF2E9E6B)); // 绿跌
    expect(AppTheme.textSecondary, const Color(0xFF8A8F98));
  });
}
