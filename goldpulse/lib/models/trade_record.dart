// lib/models/trade_record.dart
class TradeRecord {
  final int id;
  final int holdingId;
  final String type;      // 'buy' | 'sell' | 'interest'
  final double amount;    // 克重（生息为正克重）
  final double price;     // 成交价（interest 为 0）
  final double fee;       // 手续费（元）
  final int time;
  const TradeRecord({this.id = 0, required this.holdingId, required this.type, required this.amount, required this.price, required this.fee, required this.time});

  Map<String, Object?> toMap() => {
        'id': id, 'holding_id': holdingId, 'type': type, 'amount': amount,
        'price': price, 'fee': fee, 'time': time,
      };
  factory TradeRecord.fromMap(Map<String, Object?> m) => TradeRecord(
        id: m['id'] as int? ?? 0,
        holdingId: m['holding_id'] as int,
        type: m['type'] as String,
        amount: (m['amount'] as num).toDouble(),
        price: (m['price'] as num).toDouble(),
        fee: (m['fee'] as num).toDouble(),
        time: m['time'] as int,
      );
}
