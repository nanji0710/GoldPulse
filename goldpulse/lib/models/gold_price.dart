// lib/models/gold_price.dart
class GoldPrice {
  final int id;
  final String code;      // 如 'SGE-Au(T+D)' / 'CZB-JCJ'
  final double price;     // 元/g
  final double change;    // 涨跌额
  final double percent;   // 涨跌幅 %
  final double preClose;  // 上日收盘价
  final int time;         // 毫秒时间戳
  const GoldPrice({this.id = 0, required this.code, required this.price, required this.change, required this.percent, required this.preClose, required this.time});

  Map<String, Object?> toMap() => {
        'id': id, 'code': code, 'price': price, 'change': change,
        'percent': percent, 'pre_close': preClose, 'time': time,
      };
  factory GoldPrice.fromMap(Map<String, Object?> m) => GoldPrice(
        id: m['id'] as int? ?? 0,
        code: m['code'] as String,
        price: (m['price'] as num).toDouble(),
        change: (m['change'] as num).toDouble(),
        percent: (m['percent'] as num).toDouble(),
        preClose: (m['pre_close'] as num).toDouble(),
        time: m['time'] as int,
      );
}
