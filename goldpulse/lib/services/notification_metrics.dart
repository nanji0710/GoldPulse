// lib/services/notification_metrics.dart
// 常驻通知栏：8 个展示指标的纯函数计算（口径与资产页一致）+ 持仓快照模型。
// 纯 Dart、无 Flutter 依赖，供主 isolate 与后台 TaskHandler 复用。
import '../models/trade_record.dart';
import '../utils/formatters.dart' show fmtPrice;
import 'calculator.dart';

/// 持仓快照（后台 isolate 无法访问 sqflite，由主 isolate 在服务启动/持仓变更时传入）。
class PositionSnapshot {
  final String kind;
  final double grams;      // 总克重
  final double totalCost;  // 剩余总成本
  final double boughtCost; // 累计投入
  final double soldNet;    // 卖出净得合计
  /// 今日交易记录（time >= 当日 0 点），用于精确今日盈亏：今日买入按买入价、
  /// 今日卖出按卖出价，隔夜持仓按昨收。
  final List<TradeRecord> todayTrades;
  const PositionSnapshot({
    required this.kind,
    required this.grams,
    required this.totalCost,
    required this.boughtCost,
    required this.soldNet,
    this.todayTrades = const [],
  });

  Map<String, Object?> toJson() => {
        'kind': kind, 'grams': grams, 'totalCost': totalCost,
        'boughtCost': boughtCost, 'soldNet': soldNet,
        'todayTrades': todayTrades.map((t) => t.toMap()).toList(),
      };
  factory PositionSnapshot.fromJson(Map<String, dynamic> m) => PositionSnapshot(
        kind: m['kind'] as String,
        grams: (m['grams'] as num).toDouble(),
        totalCost: (m['totalCost'] as num).toDouble(),
        boughtCost: (m['boughtCost'] as num).toDouble(),
        soldNet: (m['soldNet'] as num).toDouble(),
        todayTrades: (m['todayTrades'] as List?)
                ?.map((e) =>
                    TradeRecord.fromMap((e as Map).cast<String, Object?>()))
                .toList() ??
            const [],
      );
}

/// 8 个指标 id（price/change/changePct 固定显示，其余为可选 4 指标）。
const metricIds = [
  'price', 'change', 'changePct', 'avgCost',
  'floatingProfit', 'profitRate', 'todayProfit', 'cumulativeProfit',
];

const metricLabels = {
  'price': '现价', 'change': '涨跌额', 'changePct': '涨跌幅',
  'avgCost': '均价(成本)', 'floatingProfit': '持仓收益',
  'profitRate': '收益率', 'todayProfit': '今日盈亏', 'cumulativeProfit': '累计收益',
};

String _money(double v) =>
    (v >= 0 ? '+' : '') + fmtPrice(v); // 金额带符号
String _pct(double v) =>
    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';

/// 计算 8 个指标 → 展示文本。无数据/除零 → '--'。
Map<String, String> computeNotificationMetrics({
  required double price,
  required double preClose,
  required PositionSnapshot pos,
}) {
  final avgCost = pos.grams <= 0 ? null : pos.totalCost / pos.grams;
  final floatingProfit = Calculator.floatingProfit(price, pos.grams, pos.totalCost);
  final profitRate = pos.totalCost <= 0 ? null : floatingProfit / pos.totalCost * 100;
  // 精确今日盈亏：隔夜持仓按昨收、今日买入按买入价、今日卖出按卖出价。
  final todayProfit = Calculator.todayProfitPrecise(
      price: price, preClose: preClose, amountNow: pos.grams,
      tradesToday: pos.todayTrades);
  final cumulativeProfit = pos.soldNet + price * pos.grams - pos.boughtCost;
  return {
    'price': fmtPrice(price),
    'change': _money(price - preClose),
    'changePct': _pct((price - preClose) / (preClose <= 0 ? 1 : preClose) * 100),
    'avgCost': avgCost == null ? '--' : fmtPrice(avgCost),
    'floatingProfit': pos.grams <= 0 ? '--' : _money(floatingProfit),
    'profitRate': profitRate == null ? '--' : _pct(profitRate),
    'todayProfit': pos.grams <= 0 ? '--' : _money(todayProfit),
    'cumulativeProfit': _money(cumulativeProfit),
  };
}
