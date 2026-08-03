// lib/state/holding_provider.dart
// 持仓全局状态：列表 FutureProvider。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/holding_dao.dart';
import '../database/trade_dao.dart';
import '../models/holding.dart';
import '../models/trade_record.dart';
import '../services/calculator.dart';

final holdingDaoProvider = Provider((ref) => HoldingDao());

final holdingsProvider = FutureProvider<List<Holding>>((ref) => ref.watch(holdingDaoProvider).list());

final tradeDaoProvider = Provider((ref) => TradeDao());

/// 新增持仓（首次引导/资产页）。
final addHoldingProvider = FutureProvider.family<void, Holding>((ref, holding) async {
  await ref.read(holdingDaoProvider).insert(holding);
  ref.invalidate(holdingsProvider);
});

/// 记录一笔交易并按规则更新持仓克重/成本。
final recordTradeProvider = FutureProvider.family<void, TradeRecord>((ref, record) async {
  final dao = ref.read(holdingDaoProvider);
  final h = await dao.get(record.holdingId);
  if (h == null) throw StateError('持仓不存在');
  final next = Calculator.applyTrade(amount: h.amount, totalCost: h.totalCost, record: record);
  await dao.updateAmount(record.holdingId, next.amount);
  await dao.updateCost(record.holdingId, next.totalCost);
  await ref.read(tradeDaoProvider).insert(record);
  ref.invalidate(holdingsProvider);
});

/// 数据变更后调用 `ref.invalidate(holdingsProvider)` 刷新列表。
final refreshHoldingsProvider = Provider<void>((ref) {
  // no-op：作为"变更后刷新"的语义锚点，实际刷新走 ref.invalidate(holdingsProvider)
});
