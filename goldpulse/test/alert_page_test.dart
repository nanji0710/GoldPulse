// test/alert_page_test.dart
// Task 7：提醒页删除流程 widget 测试。
// 用假 AlertDao 注入（避免真实 DB/isolate）：pump 提醒页 → 点删除图标 →
// 确认对话框（含取消分支）→ 列表移除 → 空态出现。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/database/alert_dao.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:goldpulse/pages/alert_page.dart';
import 'package:goldpulse/services/alert_service.dart';
import 'package:goldpulse/state/alert_provider.dart';

/// 假提醒 DAO：仅维护内存列表，不触碰真实数据库。
class _FakeAlertDao extends AlertDao {
  final List<Alert> _alerts;
  _FakeAlertDao(this._alerts);

  @override
  Future<List<Alert>> list() async => List.of(_alerts);

  @override
  Future<void> delete(int id) async {
    _alerts.removeWhere((a) => a.id == id);
  }
}

/// 固定逐帧推进，避免任何持续动画导致 pumpAndSettle 无法收敛。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('删除提醒：点删除 → 确认 → 列表移除', (tester) async {
    const alert = Alert(id: 1, type: 'price_up', target: 800, enable: true);
    final dao = _FakeAlertDao([alert]);

    await tester.pumpWidget(ProviderScope(
      overrides: [alertDaoProvider.overrideWithValue(dao)],
      child: const MaterialApp(home: AlertPage()),
    ));
    await _settle(tester);

    // 初始列表含该提醒。
    expect(find.text(AlertService.describe(alert)), findsOneWidget);

    // 点删除 → 弹出确认框。
    await tester.tap(find.byIcon(Icons.delete_outline));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);

    // 取消：列表保留，删除入口仍在。
    await tester.tap(find.text('取消'));
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    expect(find.text(AlertService.describe(alert)), findsOneWidget);

    // 再点删除 → 确认 → 列表移除 → 空态。
    await tester.tap(find.byIcon(Icons.delete_outline));
    await _settle(tester);
    await tester.tap(find.text('删除'));
    await _settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('暂无提醒'), findsOneWidget);
    expect(dao._alerts, isEmpty);
  });
}
