// lib/models/holding.dart
class Holding {
  final int id;
  final String name;
  final String kind;      // 'au9999' | 'accumulation' | 'icbc' | 'minsheng'
  final double amount;    // 当前持有克重（含生息）
  final double totalCost; // 剩余总成本（元）；卖出时按均价×卖出克重扣减，均价不变
  final double boughtCost; // 累计买入总成本（元）；仅随买入增加，卖出/生息不变
  final int createdAt;
  const Holding({this.id = 0, required this.name, required this.kind, required this.amount, required this.totalCost, this.boughtCost = 0, required this.createdAt});

  Map<String, Object?> toMap() => {
        'id': id, 'name': name, 'kind': kind, 'amount': amount,
        'total_cost': totalCost, 'bought_cost': boughtCost, 'created_at': createdAt,
      };
  factory Holding.fromMap(Map<String, Object?> m) => Holding(
        id: m['id'] as int? ?? 0,
        name: m['name'] as String,
        kind: m['kind'] as String,
        amount: (m['amount'] as num).toDouble(),
        totalCost: (m['total_cost'] as num).toDouble(),
        boughtCost: (m['bought_cost'] as num? ?? 0).toDouble(),
        createdAt: m['created_at'] as int,
      );
}
