// lib/services/market_hours.dart
enum MarketPhase { trading, lunchBreak, closed, weekend }

class MarketHours {
  MarketHours._();

  static MarketPhase phaseAt(DateTime now) {
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      // 周六 0:00–2:30 仍属夜盘尾段
      if (now.weekday == DateTime.saturday && _isNightSession(now)) return MarketPhase.trading;
      return MarketPhase.weekend;
    }
    if (_isNightSession(now)) return MarketPhase.trading;
    final minutes = now.hour * 60 + now.minute;
    if (minutes >= 9 * 60 && minutes < 11 * 60 + 30) return MarketPhase.trading;   // 日盘上午
    if (minutes >= 11 * 60 + 30 && minutes < 13 * 60 + 30) return MarketPhase.lunchBreak;
    if (minutes >= 13 * 60 + 30 && minutes < 15 * 60 + 30) return MarketPhase.trading; // 日盘下午
    return MarketPhase.closed;
  }

  static bool _isNightSession(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    // 凌晨 00:00–02:30：周二至周六 = 前一夜盘尾；周一/周日无夜盘尾（周日无夜盘）
    if (minutes < 150) {
      return now.weekday != DateTime.monday && now.weekday != DateTime.sunday;
    }
    // 21:00–23:59：仅周一至周五有夜盘（周六、周日无夜盘）
    return now.hour >= 21 && now.weekday <= DateTime.friday;
  }

  static bool isTrading(DateTime now) => phaseAt(now) == MarketPhase.trading;

  /// 下一个开市时刻（精确到时段），交易中返回 null。
  /// 午间休市 → 当日 13:30；15:30 收盘 → 当日 21:00 夜盘；
  /// 凌晨休市 → 当日 9:00；周末 → 下周一 9:00。
  static DateTime? nextOpen(DateTime now) {
    final p = phaseAt(now);
    if (p == MarketPhase.trading) return null;
    final minutes = now.hour * 60 + now.minute;
    switch (p) {
      case MarketPhase.lunchBreak:
        return now.copyWith(hour: 13, minute: 30, second: 0, millisecond: 0, microsecond: 0);
      case MarketPhase.closed:
        // 15:30–21:00 → 当日 21:00 夜盘；凌晨 2:30–9:00 → 当日 9:00
        if (minutes >= 15 * 60 + 30 && minutes < 21 * 60) {
          return now.copyWith(hour: 21, minute: 0, second: 0, millisecond: 0, microsecond: 0);
        }
        return now.copyWith(hour: 9, minute: 0, second: 0, millisecond: 0, microsecond: 0);
      case MarketPhase.weekend:
        var d = now.copyWith(hour: 9, minute: 0, second: 0, millisecond: 0, microsecond: 0);
        while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          d = d.add(const Duration(days: 1));
        }
        return d;
      case MarketPhase.trading:
        return null;
    }
  }

  /// 当前时段中文标签（供状态胶囊显示）。
  static String label(DateTime now) => switch (phaseAt(now)) {
        MarketPhase.trading => '交易中',
        MarketPhase.lunchBreak => '午间休市',
        MarketPhase.closed => '已收盘',
        MarketPhase.weekend => '休市',
      };

  static const _weekdayCn = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  /// 恢复交易提示文案，如"13:30 恢复交易"、"21:00 夜盘开盘"、"周一 9:00 开盘"。
  static String? resumeHint(DateTime now) {
    final next = nextOpen(now);
    if (next == null) return null;
    final hm = '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
    return switch (phaseAt(now)) {
      MarketPhase.lunchBreak => '$hm 恢复交易',
      MarketPhase.closed => '$hm 开盘',
      MarketPhase.weekend => '${_weekdayCn[next.weekday - 1]} $hm 开盘',
      _ => null,
    };
  }
}
