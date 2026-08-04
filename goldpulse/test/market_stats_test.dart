// test/market_stats_test.dart
// 行情页区间统计纯函数 periodStatsOf 单测。
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/pages/market_page.dart';

GoldPrice _p(int time, double price) =>
    GoldPrice(code: 'SGE-Au(T+D)', price: price, change: 0, percent: 0, preClose: 0, time: time);

void main() {
  test('不足 2 条数据返回 null', () {
    expect(periodStatsOf(const []), isNull);
    expect(periodStatsOf([_p(1000, 780)]), isNull);
  });

  test('区间最高/最低正确', () {
    final s = periodStatsOf([_p(3000, 785), _p(2000, 780), _p(1000, 770)]);
    expect(s, isNotNull);
    expect(s!.high, closeTo(785, 0.001));
    expect(s.low, closeTo(770, 0.001));
  });

  test('区间涨跌 = (最新 − 最早) ÷ 最早 × 100', () {
    final s = periodStatsOf([_p(3000, 785), _p(2000, 780), _p(1000, 770)]);
    expect(s!.changePct, closeTo((785 - 770) / 770 * 100, 0.0001));
  });

  test('最高/最低/涨跌与行序无关（按 time 取首尾）', () {
    // 乱序输入：最新 time=3000 在最前、最早 time=1000 在中间，仍按 time 定首尾。
    final shuffled = periodStatsOf([_p(3000, 785), _p(1000, 770), _p(2000, 780)]);
    final desc = periodStatsOf([_p(3000, 785), _p(2000, 780), _p(1000, 770)]);
    expect(shuffled!.high, closeTo(desc!.high, 0.001));
    expect(shuffled.low, closeTo(desc.low, 0.001));
    expect(shuffled.changePct, closeTo(desc.changePct, 0.0001));
  });
}
