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

  static DateTime? nextOpen(DateTime now) {
    final p = phaseAt(now);
    if (p == MarketPhase.trading) return null;
    // 简化：下一交易日 9:00；周五收盘后/周末 → 下周一 9:00
    var d = now.copyWith(hour: 9, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    if (d.isBefore(now)) d = d.add(const Duration(days: 1));
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}
