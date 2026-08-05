// lib/services/background_alert.dart
// 后台提醒检查：WorkManager background isolate 真正执行的入口。
// 拉 Au9999 最新价 → 汇总持仓资产/成本 → 对启用的价格/收益提醒判定 → 命中发通知。
import '../database/alert_dao.dart';
import '../database/holding_dao.dart';
import 'alert_service.dart';
import 'price_api.dart';

/// 后台提醒检查：逐品种拉最新价 → 按品种对启用的价格/收益提醒判定 → 命中发通知。
/// 与前台完全同语义：**每个品种只判定同品种的提醒**，收益目标按该品种持仓的
/// 利润（assetValue−totalCost）判定。共用 [AlertService.matches] 保证前后台一致。
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
    // 品种 → 行情代码：与前台统一 getGoldPrice 源一致。
    const kindCodes = {
      'au9999': 'SGE-Au(T+D)',
      'accumulation': 'CZB-JCJ',
      'icbc': 'ICBC-JCJ',
      'minsheng': 'MSB-JCJ',
    };
    final holdings = await holdingDao.list();
    final alerts = await alertDao.list();
    for (final entry in kindCodes.entries) {
      final kind = entry.key;
      // 民生走独立 latestPrice 接口，其余走统一 getGoldPrice。
      final price = kind == 'minsheng'
          ? await api.fetchMinShengPriceWithFallback()
          : await api.fetchGoldPriceWithFallback(entry.value);
      if (price == null) continue; // 该品种拉价失败 → 跳过，不发通知
      // 只统计同品种持仓（收益目标按所选品种的利润判定）。
      var assetValue = 0.0, totalCost = 0.0;
      for (final h in holdings) {
        if (h.kind != kind) continue;
        assetValue += price.price * h.amount;
        totalCost += h.totalCost;
      }
      for (final a in alerts) {
        if (a.kind != kind) continue;
        if (AlertService.matches(a,
            price: price.price, assetValue: assetValue, totalCost: totalCost)) {
          await showNotification('金脉提醒', AlertService.describe(a));
        }
      }
    }
  } catch (_) {
    // 后台任务失败静默，不得崩溃。
  }
}
