// test/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/models/alert.dart';

void main() {
  test('GoldPrice round-trip', () {
    final gp = GoldPrice(code: 'SGE-Au(T+D)', price: 780.20, change: 3.5, percent: 0.45, preClose: 776.70, time: 1000,
        openPrice: 775.00, highPrice: 782.00, lowPrice: 774.50);
    final back = GoldPrice.fromMap(gp.toMap()..['id'] = 1);
    expect(back.price, 780.20);
    expect(back.preClose, 776.70);
    expect(back.openPrice, 775.00);
    expect(back.highPrice, 782.00);
    expect(back.lowPrice, 774.50);
    expect(back.id, 1);
  });
  test('GoldPrice 旧行（无日线列）fromMap 回退 0', () {
    final back = GoldPrice.fromMap({'id': 1, 'code': 'CZB-JCJ', 'price': 780.0, 'change': 1.0, 'percent': 0.1, 'pre_close': 779.0, 'time': 1});
    expect(back.openPrice, 0);
    expect(back.highPrice, 0);
    expect(back.lowPrice, 0);
  });
  test('Holding fromMap', () {
    final h = Holding.fromMap({'id': 1, 'name': '浙商积存金', 'kind': 'accumulation', 'amount': 501.2, 'total_cost': 310000.0, 'created_at': 1});
    expect(h.kind, 'accumulation');
    expect(h.amount, 501.2);
  });
  test('TradeRecord types', () {
    final t = TradeRecord(holdingId: 1, type: 'interest', amount: 0.08, price: 0, fee: 0, time: 2);
    expect(t.type, 'interest');
  });
  test('Alert round-trip', () {
    final a = Alert(type: 'price_up', target: 800, enable: true);
    final back = Alert.fromMap(a.toMap()..['id'] = 3);
    expect(back.enable, true);
    expect(back.id, 3);
  });
}
