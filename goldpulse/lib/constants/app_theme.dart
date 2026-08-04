// lib/constants/app_theme.dart
// 黑金主题 v2（依据 ui-ux-pro-max 设计系统：Modern Dark Cinema + 信任海军蓝 + 高级金）
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  /// 金融字体：IBM Plex Sans（本地打包）
  static const fontFamily = 'IBMPlexSans';

  // ---- 色板：深海军蓝基调 + 金色强调（暗色为主）----
  static const background = Color(0xFF0F172A);      // 深海军蓝背景
  static const card = Color(0xFF1E293B);            // 卡片（海军蓝浅一层）
  static const cardHighlight = Color(0xFF28384E);   // 高亮卡片/渐变终点
  static const gold = Color(0xFFD9A441);            // 高级金（暗色主强调）
  static const goldSoft = Color(0xFF8A6A1F);        // 柔和金（描边/次级强调）
  static const up = Color(0xFFE5484D);              // 红涨（国内习惯）
  static const down = Color(0xFF2E9E6B);            // 绿跌
  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const divider = Color(0xFF334155);
  static const offline = Color(0xFF64748B);

  /// 卡片圆角与描边（统一语言）
  static const cardRadius = 20.0;

  /// 主卡片（价格卡）渐变：底部卡片色 → 顶部微金辉光
  static const heroGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2B3B55), cardHighlight],
  );

  static ThemeData theme() => ThemeData(
        brightness: Brightness.dark,
        fontFamily: fontFamily,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          surface: card,
          onSurface: textPrimary,
          secondary: goldSoft,
        ),
        cardColor: card,
        dividerColor: divider,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontFamily: fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: card,
          indicatorColor: gold.withValues(alpha: 0.16),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? gold : textSecondary,
              size: 24,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontFamily: fontFamily,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? gold : textSecondary,
            );
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: goldSoft, width: 1.5),
          ),
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: textPrimary),
          headlineMedium: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: textPrimary),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
          bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
          labelSmall: TextStyle(fontSize: 12, color: textSecondary),
        ),
      );
}
