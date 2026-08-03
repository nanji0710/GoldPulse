import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();
  static const background = Color(0xFF101216);
  static const card = Color(0xFF181B22);
  static const gold = Color(0xFFD9A441);
  static const up = Color(0xFFE5484D);     // 红涨（国内习惯）
  static const down = Color(0xFF2E9E6B);   // 绿跌
  static const textPrimary = Color(0xFFF2F3F5);
  static const textSecondary = Color(0xFF8A8F98);
  static const offline = Color(0xFF6B7280);

  static ThemeData theme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          surface: card,
        ),
        cardColor: card,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: textPrimary,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: textPrimary),
          headlineMedium: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: textPrimary),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
          bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
        ),
      );
}
