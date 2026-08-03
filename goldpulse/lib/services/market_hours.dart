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
    if (now.weekday == DateTime.saturday && now.hour < 3) return true; // 周六凌晨属夜盘尾
    if (now.weekday == DateTime.friday && now.hour >= 21) return true;  // 周五夜盘（跨周六）
    if (now.weekday == DateTime.sunday && now.hour < 3) return true;    // 周日凌晨是周六夜盘尾
    return now.hour >= 21 || (now.hour < 3 && now.weekday != DateTime.monday);
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
