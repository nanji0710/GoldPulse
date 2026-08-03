// lib/state/holding_provider.dart
// 持仓全局状态：列表 FutureProvider。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/holding_dao.dart';
import '../models/holding.dart';

final holdingDaoProvider = Provider((ref) => HoldingDao());

final holdingsProvider = FutureProvider<List<Holding>>((ref) => ref.watch(holdingDaoProvider).list());

/// 数据变更后调用 `ref.invalidate(holdingsProvider)` 刷新列表。
final refreshHoldingsProvider = Provider<void>((ref) {
  // no-op：作为"变更后刷新"的语义锚点，实际刷新走 ref.invalidate(holdingsProvider)
});
