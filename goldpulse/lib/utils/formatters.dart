import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/app_theme.dart';

final _number = NumberFormat('#,##0.00');
// 克数需精确到小数点后 4 位（积存金生息常出现 0.0825g 级小数）
final _grams = NumberFormat('#,##0.0000');
final _money = NumberFormat('#,##0.00');

String fmtPrice(double v) => _number.format(v);
String fmtAmount(double v) => _money.format(v);
String fmtGrams(double v) => _grams.format(v);

/// 涨跌箭头：正/零 → ▲，负 → ▼（红涨绿跌由调用方着色）
String arrow(double v) => v < 0 ? '▼' : '▲';

/// 涨跌颜色：上涨红、下跌绿（国内习惯）
Color arrowColor(double v) => v < 0 ? AppTheme.down : AppTheme.up;
