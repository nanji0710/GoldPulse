// lib/services/background_alert.dart
// 后台提醒检查：WorkManager background isolate 真正执行的入口。
// 拉 Au9999 最新价 → 汇总持仓资产/成本 → 对启用的价格/收益提醒判定 → 命中发通知。
import '../database/alert_dao.dart';
import '../database/holding_dao.dart';
import 'alert_service.dart';
import 'price_api.dart';

/// 后台提醒检查：拉 Au9999 最新价 → 对启用的价格/收益提醒判定 → 命中发通知。
/// 后台只拉 Au9999 行情：价格提醒仅判定 'au9999' 品种（其余品种跳过），
/// 收益提醒不区分品种照常判定。与前台共用 [AlertService.matches]，
/// 保证前后台判定语义一致。
///
/// [showNotification] 抽成回调（而非直接依赖 FlutterLocalNotificationsPlugin），
/// 便于单测注入 fake；真机路径由 callbackDispatcher 把插件实例绑定进闭包。
/// 整段包 try/catch：后台任务失败静默返回，绝不允许异常冒泡导致崩溃。
Future<void> runBackgroundAlertCheck({
  required PriceApi api,
  required AlertDao alertDao,
  required HoldingDao holdingDao,
  required Future<void> Function(String title, String body) showNotification,
}) async {
  try {
    final price = await api.fetchGoldPriceWithFallback('SGE-Au(T+D)');
    if (price == null) return; // 拉价失败/无数据 → 静默返回，不发通知

    final holdings = await holdingDao.list();
    var assetValue = 0.0, totalCost = 0.0;
    for (final h in holdings) {
      assetValue += price.price * h.amount;
      totalCost += h.totalCost;
    }

    final alerts = await alertDao.list();
    for (final a in alerts) {
      // 后台仅拉 Au9999 价：价格提醒只判定 Au9999 品种；收益提醒不区分品种。
      if (a.type != 'profit_target' && a.kind != 'au9999') continue;
      if (AlertService.matches(a,
          price: price.price, assetValue: assetValue, totalCost: totalCost)) {
        await showNotification('金脉提醒', AlertService.describe(a));
      }
    }
  } catch (_) {
    // 后台任务失败静默，不得崩溃。
  }
}
