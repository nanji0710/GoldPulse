// lib/models/holding.dart
class Holding {
  final int id;
  final String name;
  final String kind;      // 'au9999' | 'accumulation'
  final double amount;    // 当前持有克重（含生息）
  final double totalCost; // 累计买入总成本（元）
  final int createdAt;
  const Holding({this.id = 0, required this.name, required this.kind, required this.amount, required this.totalCost, required this.createdAt});

  Map<String, Object?> toMap() => {
        'id': id, 'name': name, 'kind': kind, 'amount': amount,
        'total_cost': totalCost, 'created_at': createdAt,
      };
  factory Holding.fromMap(Map<String, Object?> m) => Holding(
        id: m['id'] as int? ?? 0,
        name: m['name'] as String,
        kind: m['kind'] as String,
        amount: (m['amount'] as num).toDouble(),
        totalCost: (m['total_cost'] as num).toDouble(),
        createdAt: m['created_at'] as int,
      );
}
