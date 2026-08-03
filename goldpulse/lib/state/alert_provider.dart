// lib/state/alert_provider.dart
// 价格提醒全局状态：列表 FutureProvider。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/alert_dao.dart';
import '../models/alert.dart';

final alertDaoProvider = Provider((ref) => AlertDao());

final alertsProvider = FutureProvider<List<Alert>>((ref) => ref.watch(alertDaoProvider).list());
