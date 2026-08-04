# 持仓域增强 + 后台提醒落地 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有基础上增量增强持仓域——多品种收益聚合、追加买入、持仓详情与交易流水、资产汇总块，并让后台提醒真正生效。

**Architecture:** 新增类型级聚合 Provider（`typeSummariesProvider` / `totalAssetSummaryProvider`），首页收益区改为按品种多卡 + 合计；资产页加汇总块并支持进入新详情页；后台 WorkManager 复用前台 PriceApi/AlertService 做拉价+判定+通知。

**Tech Stack:** Flutter 3.44 / Riverpod 2.x / sqflite / workmanager / flutter_local_notifications / dio。

**Spec:** `docs/superpowers/specs/2026-08-04-holding-domain-alerts-design.md`

## Global Constraints（全局约束）

1. **增量原则**：所有改动在原有功能基础上增加，不删除/替换现有页面与功能；首页三行情卡、行情页、提醒页、设置页、引导页保持原样。
2. 主题 token 一律取自 `lib/constants/app_theme.dart`（黑金 v2）；红涨绿跌；数字 `FontFeature.tabularFigures()`；触控目标 ≥44px。
3. 收益三口径公式（Task 6 修订后）：持仓=现价×克重−总成本(剩余成本基础)；今日=(现价−昨收)×克重；累计=Σ卖出净得+现价×克重−累计买入总成本(boughtCost)。
4. 同品种多笔持仓聚合：总克重=Σ克重；总成本=ΣtotalCost；均价=总成本÷总克重（加权）。
5. **克数一律显示到小数点后 4 位**（`fmtGrams` 已改 `#,##0.0000`）；金额/价格仍 2 位。
6. 既有测试不得破坏：`flutter analyze` 零告警；`flutter test` 全绿（基线 115）。
7. Windows 环境：每次 Bash 调用 flutter 前先执行
   `export PATH="$(printf '%s' "$PATH" | tail -n 1)"`，并设
   `FLUTTER_STORAGE_BASE_URL=https://mirror.nju.edu.cn/flutter`、
   `PUB_HOSTED_URL=https://pub.flutter-io.cn`（release 构建另加
   `GOLDPULSE_KEY_PASS='GoldPulse@2026Key'`）。flutter 位于 `/c/Users/RED CHAMBER/flutter/bin/flutter`。
7. 提交信息用中文前缀（feat/fix/style/test/docs: 描述），直接提交 main（用户已授权）。

---

### Task 1: 收益聚合数据层（TypeAssetSummary + providers）

**Files:**
- Modify: `goldpulse/lib/state/asset_provider.dart`
- Test: `goldpulse/test/state_test.dart`（新增聚合用例；保留既有 assetSummaryProvider 用例不动）

**Interfaces:**
- Produces: `TypeAssetSummary` 模型、`typeSummariesProvider`（FutureProvider<List<TypeAssetSummary>>）、`totalAssetSummaryProvider`（FutureProvider<TypeAssetSummary?>）。
- `TypeAssetSummary` 字段（后续任务消费）：`kind`、`label`、`totalGrams`、`totalCost`、`avgCost`、`currentPrice`(double?)、`preClose`(double?)、`floatingProfit`、`todayProfit`、`cumulativeProfit`、`holdingCount`。

- [ ] **Step 1: 在 `lib/state/asset_provider.dart` 增加类型级汇总模型与两个 Provider**

```dart
/// 按品种聚合的持仓收益汇总。
/// kind: 'accumulation'(浙商) | 'icbc'(工商) | 'au9999'；label 为中文品种名。
class TypeAssetSummary {
  final String kind;
  final String label;
  final double totalGrams;
  final double totalCost;
  final double avgCost;
  final double? currentPrice; // 无行情时为 null
  final double? preClose;
  final double floatingProfit;   // 持仓收益
  final double todayProfit;      // 今日盈亏
  final double cumulativeProfit; // 累计收益
  final int holdingCount;
  const TypeAssetSummary({
    required this.kind, required this.label,
    required this.totalGrams, required this.totalCost, required this.avgCost,
    this.currentPrice, this.preClose,
    required this.floatingProfit, required this.todayProfit, required this.cumulativeProfit,
    required this.holdingCount,
  });
}

String _kindLabel(String kind) => switch (kind) {
      'accumulation' => '浙商积存金',
      'icbc' => '工商积存金',
      _ => 'Au9999',
    };

/// 按品种聚合全部持仓的收益汇总（同品种多笔合并：克重求和、均价=总成本÷总克重）。
/// 每个品种用其自身行情价计算三口径；无行情 → currentPrice=null（收益记 0，UI 显示 '--'）。
final typeSummariesProvider = FutureProvider<List<TypeAssetSummary>>((ref) async {
  final holdings = await ref.watch(holdingsProvider.future);
  if (holdings.isEmpty) return const [];
  final trades = await ref.read(tradeDaoProvider).all();
  // 固定品种顺序：浙商 → 工商 → Au9999
  const order = ['accumulation', 'icbc', 'au9999'];
  final byKind = <String, List<Holding>>{};
  for (final h in holdings) {
    byKind.putIfAbsent(h.kind, () => []).add(h);
  }
  final results = <TypeAssetSummary>[];
  for (final kind in order) {
    final hs = byKind[kind];
    if (hs == null || hs.isEmpty) continue;
    final totalGrams = hs.fold(0.0, (s, h) => s + h.amount);
    final totalCost = hs.fold(0.0, (s, h) => s + h.totalCost);
    final ids = hs.map((h) => h.id).toSet();
    final sells = trades.where((t) => ids.contains(t.holdingId) && t.type == 'sell');
    final price = kind == 'icbc'
        ? ref.watch(icbcPriceProvider).valueOrNull
        : kind == 'accumulation'
            ? ref.watch(accumulationPriceProvider).valueOrNull
            : ref.watch(priceProvider).valueOrNull;
    results.add(TypeAssetSummary(
      kind: kind,
      label: _kindLabel(kind),
      totalGrams: totalGrams,
      totalCost: totalCost,
      avgCost: Calculator.avgCost(totalCost, totalGrams),
      currentPrice: price?.price,
      preClose: price?.preClose,
      floatingProfit: price == null
          ? 0
          : Calculator.floatingProfit(price.price, totalGrams, totalCost),
      todayProfit: price == null
          ? 0
          : Calculator.todayProfit(price.price, price.preClose, totalGrams),
      cumulativeProfit: price == null
          ? 0
          : Calculator.cumulativeProfit(
              currentPrice: price.price, amount: totalGrams,
              totalCost: totalCost, sellTrades: sells),
      holdingCount: hs.length,
    ));
  }
  return results;
});

/// 全部持仓合计（跨品种线性相加）。
final totalAssetSummaryProvider = FutureProvider<TypeAssetSummary?>((ref) async {
  final list = await ref.watch(typeSummariesProvider.future);
  if (list.isEmpty) return null;
  final grams = list.fold(0.0, (s, t) => s + t.totalGrams);
  final cost = list.fold(0.0, (s, t) => s + t.totalCost);
  return TypeAssetSummary(
    kind: 'all',
    label: '全部持仓',
    totalGrams: grams,
    totalCost: cost,
    avgCost: Calculator.avgCost(cost, grams),
    currentPrice: null,
    preClose: null,
    floatingProfit: list.fold(0.0, (s, t) => s + t.floatingProfit),
    todayProfit: list.fold(0.0, (s, t) => s + t.todayProfit),
    cumulativeProfit: list.fold(0.0, (s, t) => s + t.cumulativeProfit),
    holdingCount: list.fold(0, (s, t) => s + t.holdingCount),
  );
});
```

- [ ] **Step 2: 在 `test/state_test.dart` 增加聚合测试**

参考 `test/test_db.dart` 现有夹具模式（临时数据库 + HoldingDao/TradeDao 写入），行情 Provider 用 overrideWithValue 注入固定 GoldPrice。结构如下：

```dart
test('typeSummariesProvider：同品种合并克重与均价、多品种分开、total 线性合计', () async {
  final db = await createTestDb(); // test_db.dart 现有夹具
  final holdingDao = HoldingDao(db: db);
  final tradeDao = TradeDao(db: db);
  // 浙商两笔：30g@870、20g@880（totalCost 分别 26100、17600）；工商一笔 10g@890
  final h1 = await holdingDao.insertReturning(Holding(name: '浙商1', kind: 'accumulation', amount: 30, totalCost: 26100, createdAt: 1));
  final h2 = await holdingDao.insertReturning(Holding(name: '浙商2', kind: 'accumulation', amount: 20, totalCost: 17600, createdAt: 2));
  await holdingDao.insertReturning(Holding(name: '工商', kind: 'icbc', amount: 10, totalCost: 8900, createdAt: 3));
  // 浙商卖单：10g@900 fee 36
  await tradeDao.insert(TradeRecord(holdingId: h1.id, type: 'sell', amount: 10, price: 900, fee: 36, time: 4));
  final container = ProviderContainer(overrides: [
    holdingDaoProvider.overrideWithValue(holdingDao),
    tradeDaoProvider.overrideWithValue(tradeDao),
    holdingsProvider.overrideWith((ref) => holdingDao.list()),
    accumulationPriceProvider.overrideWith((ref) => Stream.value(GoldPrice(code: 'CZB-JCJ', price: 900, change: 1, percent: 0.1, preClose: 890, time: 5))),
    icbcPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null)), // 工商无行情
  ]);
  addTearDown(container.dispose);
  final list = await container.read(typeSummariesProvider.future);
  // 浙商：totalGrams=50、totalCost=43700、avgCost=874.0；卖单净得=10*900-36=8964
  final czb = list.firstWhere((t) => t.kind == 'accumulation');
  expect(czb.totalGrams, 50);
  expect(czb.avgCost, closeTo(874.0, 0.001));
  expect(czb.cumulativeProfit, closeTo(8964 + 900 * 50 - 43700, 0.001));
  expect(list.firstWhere((t) => t.kind == 'icbc').currentPrice, isNull);
  final total = await container.read(totalAssetSummaryProvider.future);
  expect(total!.floatingProfit, list.fold(0.0, (s, t) => s + t.floatingProfit));
});
```

（`holdingDao.insertReturning` 若不存在，用现有 `insert` 后 `list()` 取回 id 的方式代替。）

- [ ] **Step 3: 运行测试确认通过**

Run（在 goldpulse/ 下）: `flutter test test/state_test.dart`
Expected: 新增用例 PASS，既有用例 PASS。

- [ ] **Step 4: analyze + 全量回归**

Run: `flutter analyze`（No issues found）+ `flutter test`（全绿，基线 115 + 新增）。

- [ ] **Step 5: Commit**

```bash
git add goldpulse/lib/state/asset_provider.dart goldpulse/test/state_test.dart
git commit -m "feat: 品种级收益聚合（typeSummariesProvider + totalAssetSummaryProvider）"
```

---

### Task 2: 首页按品种多张收益卡 + 全部合计

**Files:**
- Modify: `goldpulse/lib/pages/home_page.dart`
- Modify: `goldpulse/lib/widgets/profit_card.dart`（支持 currentPrice 为 null 时显示 '--'）
- Test: `goldpulse/test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `typeSummariesProvider`、`totalAssetSummaryProvider`、`TypeAssetSummary`（Task 1）。
- Produces: 首页收益区渲染（每品种一张 ProfitCard + 合计卡）。

- [ ] **Step 1: 改造 `ProfitCard` 支持无行情占位**

`ProfitCard` 增加可选参数 `bool showMetrics = true` 或让三口径在无行情时显示 '--'。实现：新增可选字段 `String? priceText`，若非空则在收益大字区下方/替代处显示；**最简做法**：让 `floatingProfit/todayProfit/cumulativeProfit` 显示逻辑不变，仅当 `currentPrice == null` 时首页不渲染该品种卡（见 Step 2）。此步只需给 `ProfitCard` 加可选 `String? gramsHint`（默认 null，显示 `持仓 Xg · 均价 Y`），无需其它改动。

```dart
// ProfitCard 增加可选参数：
final String? gramsHint; // 如 '50g · 均价 870.00'，为 null 时显示原「持仓/平均成本」两列
```

- [ ] **Step 2: 首页收益区改为每品种卡 + 合计卡**

在 `home_page.dart` 中：
- 移除对 `assetSummaryProvider` 的 watch 与 `ProfitCard`（旧单卡）。
- watch `typeSummariesProvider` 与 `totalAssetSummaryProvider`。
- 收益区渲染：
  - 空持仓 → 保留现有 CTA 引导容器。
  - 有持仓 → 对每个 `TypeAssetSummary`（仅当 `currentPrice != null`）渲染一张 `ProfitCard(name: t.label, grams: t.totalGrams, avgCost: t.avgCost, floatingProfit: t.floatingProfit, todayProfit: t.todayProfit, cumulativeProfit: t.cumulativeProfit, profitRate: t.totalCost == 0 ? 0 : t.floatingProfit / t.totalCost, gramsHint: '${fmtGrams(t.totalGrams)}g · 均价 ${fmtPrice(t.avgCost)}')`；
  - 末尾渲染合计卡：`totalAssetSummaryProvider` 非空时，渲染一张 `ProfitCard(name: '全部持仓', grams: t.totalGrams, ..., gramsHint: '${t.holdingCount} 个品种')`（合计卡 currentPrice 为 null，仅展示三口径数字）。

- [ ] **Step 3: 更新 widget_smoke_test**

首页测试的 ProviderScope 需要 override `typeSummariesProvider`/`totalAssetSummaryProvider`（注入一条品种汇总）或确保现有 override 不导致 UnimplementedError。若直接 pump HomePage 不 override，则这两个 FutureProvider 会走真实 DB → 测试库为空 → 渲染空态 CTA，现有断言需核对。新增用例：注入一条品种汇总后，`find.text('浙商积存金')` 与 `find.text('全部持仓')` 可寻。

- [ ] **Step 4: analyze + 全量测试**

Run: `flutter analyze` + `flutter test`，全绿。

- [ ] **Step 5: Commit**

```bash
git add goldpulse/lib/pages/home_page.dart goldpulse/lib/widgets/profit_card.dart goldpulse/test/widget_smoke_test.dart
git commit -m "feat: 首页收益区按品种多卡 + 全部合计"
```

---

### Task 3: 资产页顶部汇总块 + 持仓进入详情入口

**Files:**
- Modify: `goldpulse/lib/pages/asset_page.dart`
- Modify: `goldpulse/lib/widgets/holding_list_tile.dart`（增加 onTap → 详情页；详情页路由在 Task 4 建立，此步先占位跳转由 Task 4 落地，或本任务先加 `onTap` 回调参数、Task 4 传入路由）
- Test: `goldpulse/test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `totalAssetSummaryProvider`（Task 1）。
- Produces: `HoldingListTile` 的 `onTap` 回调参数（Task 4 传入 Navigator.push）。

- [ ] **Step 1: 资产页顶部「持仓汇总」块**

在 `asset_page.dart` 的 ListView 顶部（持仓列表之前）插入汇总卡：watch `totalAssetSummaryProvider`，非空时渲染一个容器（复用设计文档的汇总卡样式：AppTheme.card + heroGradient 或 card + divider，三列 持仓收益/今日盈亏/累计收益 + 品种数）。

```dart
// 概要结构
final total = ref.watch(totalAssetSummaryProvider).value;
// 在 ListView children 最前：
if (total != null)
  _SummaryCard(total: total), // 三列：持仓/今日/累计（红涨绿跌）
```

- [ ] **Step 2: HoldingListTile 增加 onTap 参数（仅加参数，不接线）**

`HoldingListTile` 增加 `final VoidCallback? onTap;`，`ListTile(onTap: onTap, ...)`（保留 onLongPress）。**本任务只加参数、不改 asset_page 调用**（保持编译通过）；真正的 `onTap` 接线到 `HoldingDetailPage` 由 Task 4 Step 5 完成。

- [ ] **Step 3: 测试**

widget_smoke_test 资产页用例：注入 totalAssetSummaryProvider 后 `find.text('持仓汇总')` 可寻。

- [ ] **Step 4: analyze + 全量测试**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: 资产页顶部持仓汇总块 + 持仓项 onTap 参数"
```

---

### Task 4: 持仓详情页 + 追加买入 + 交易流水管理

**Files:**
- Create: `goldpulse/lib/pages/holding_detail_page.dart`
- Create: `goldpulse/lib/widgets/number_dialogs.dart`（把 holding_list_tile.dart 里的私有 `_promptNumber` / `_promptSell` / `_parseNum` 提取为公共 `promptNumber` / `promptSell`，holding_list_tile 改为引用）
- Modify: `goldpulse/lib/services/calculator.dart`（新增 `reverseTrade`）
- Modify: `goldpulse/lib/database/holding_dao.dart`（新增 `deleteTrade`）
- Modify: `goldpulse/lib/state/holding_provider.dart`（新增 `deleteTradeProvider`）
- Modify: `goldpulse/lib/widgets/holding_list_tile.dart`（追加买入入口 + onTap 接线）
- Modify: `goldpulse/lib/pages/asset_page.dart`（HoldingListTile 传 onTap → HoldingDetailPage）
- Test: 新增 `goldpulse/test/holding_detail_test.dart`、`goldpulse/test/transaction_test.dart`

**Interfaces:**
- Consumes: `HoldingDetailPage(holdingId)`、`holdingTradesProvider(holdingId)`、`recordTradeProvider`、`promptNumber`/`promptSell`、新增 `deleteTradeProvider(holdingId, tradeId)`。
- Produces: 持仓详情页；追加买入；删除交易回滚。

- [ ] **Step 1: Calculator 新增 `reverseTrade`**

```dart
/// 反向应用一笔交易（删除交易时回滚持仓状态）。
/// buy → 减克重减成本；sell → 加克重；interest → 减克重。
/// 回滚后克重/成本为负时返回 null（禁止删除）。
static ({double amount, double totalCost})? reverseTrade({
  required double amount,
  required double totalCost,
  required TradeRecord record,
}) {
  switch (record.type) {
    case 'buy':
      if (amount < record.amount || totalCost < record.amount * record.price) return null;
      return (amount: amount - record.amount, totalCost: totalCost - record.amount * record.price);
    case 'interest':
      if (amount < record.amount) return null;
      return (amount: amount - record.amount, totalCost: totalCost);
    case 'sell':
      return (amount: amount + record.amount, totalCost: totalCost);
    default:
      return (amount: amount, totalCost: totalCost);
  }
}
```

- [ ] **Step 2: HoldingDao.deleteTrade + deleteTradeProvider**

`HoldingDao` 新增 `deleteTrade({required int holdingId, required double amount, required double totalCost, required int tradeId})`：事务内删除 trade 行并更新 holding 的克重/成本（复用现有 `recordTrade` 的事务模式）。

`holding_provider.dart` 新增：

```dart
/// 删除一笔交易并回滚持仓状态；回滚后非法（负克重/负成本）则拒绝。
final deleteTradeProvider =
    FutureProvider.family<void, ({int holdingId, int tradeId})>(
        (ref, arg) async {
  final dao = ref.read(holdingDaoProvider);
  final trade = await ref.read(tradeDaoProvider).get(arg.tradeId);
  if (trade == null) throw StateError('交易不存在');
  final h = await dao.get(arg.holdingId);
  if (h == null) throw StateError('持仓不存在');
  final next = Calculator.reverseTrade(
      amount: h.amount, totalCost: h.totalCost, record: trade);
  if (next == null) throw StateError('删除该交易会导致克重或成本为负，禁止删除');
  await dao.deleteTrade(
      holdingId: arg.holdingId, amount: next.amount,
      totalCost: next.totalCost, tradeId: arg.tradeId);
  ref.invalidate(holdingsProvider);
  ref.invalidate(holdingTradesProvider(arg.holdingId));
});
```

（`TradeDao.get(id)` 若不存在，则新增一个 `Future<TradeRecord?> get(int id)`。）

- [ ] **Step 3: 提取公共数字对话框**

新建 `lib/widgets/number_dialogs.dart`：把 `holding_list_tile.dart` 中 `_parseNum`/`_promptNumber`/`_promptSell` 复制为公共 `parseNum`/`promptNumber`/`promptSell`（签名不变），并把 holding_list_tile 内的调用改为引用公共版。

- [ ] **Step 4: 新建持仓详情页**

`lib/pages/holding_detail_page.dart`（ConsumerStatefulWidget，参数 `int holdingId`）：
- watch `holdingsProvider` 找到该持仓（不存在 → EmptyState）；watch `holdingTradesProvider(holdingId)`；watch 对应品种行情 provider 的 valueOrNull。
- 顶部：名称/品种、现价与涨跌胶囊、该笔持仓三口径（持仓收益大字 + 今日/累计迷你卡）。
- 操作行：追加买入 / 记卖出 / 加记生息（三按钮，分别调 `promptNumber`/`promptSell` + `recordTradeProvider`，追加买入默认价=该品种现价）。
- 交易流水 ListView：每条 TradeRecord 显示 类型标签（买入/生息/卖出）+ 克重×价格 + 手续费 + 时间；长按或删除按钮 → 确认 → `deleteTradeProvider`，失败 SnackBar 提示原因。
- 样式复用 AppTheme + EmptyState；AppBar 返回。

- [ ] **Step 5: 接线详情入口 + 追加买入**

- `asset_page.dart`：`HoldingListTile(onTap: () => Navigator.push(... HoldingDetailPage(holdingId: h.id)))`。
- `holding_list_tile.dart` 长按菜单新增「追加买入」项（复用 promptNumber 两次或一个双输入对话框，调用 `recordTradeProvider(TradeRecord(type:'buy', amount, price, fee:0))`）。

- [ ] **Step 6: 测试**

`test/holding_detail_test.dart`：详情页渲染（注入持仓/交易/行情）；追加买入后克重与均价正确；删除买入交易后克重/成本回滚；删除会致负的卖出交易被拒绝。
`test/transaction_test.dart` 增补 reverseTrade 用例。

- [ ] **Step 7: analyze + 全量测试**

- [ ] **Step 8: Commit**

```bash
git commit -m "feat: 持仓详情页 + 追加买入 + 交易流水管理"
```

---

### Task 5: 后台提醒落地（WorkManager 真正执行）

**Files:**
- Modify: `goldpulse/lib/main.dart`（callbackDispatcher 真实实现）
- Modify: `goldpulse/lib/state/alert_provider.dart`（把 `runAlertChecks` 依赖参数化，便于后台复用；或新增后台判定入口 `runBackgroundAlertCheck`）
- Test: 新增 `goldpulse/test/background_alert_test.dart`

**Interfaces:**
- Consumes: `PriceApi`、`AlertDao`、`AlertService`、`AppDatabase`、`Calculator`。
- Produces: 后台任务真实拉价 + 判定 + 通知。

- [ ] **Step 1: 抽取后台判定函数**

`alert_provider.dart` 或新 `lib/services/background_alert.dart`：

```dart
/// 后台提醒检查：拉 Au9999 最新价 → 对启用的价格/收益提醒判定 → 命中发通知。
/// 供 WorkManager background isolate 调用；与前台共用 AlertService.matches。
Future<void> runBackgroundAlertCheck({
  required PriceApi api,
  required AlertDao alertDao,
  required HoldingDao holdingDao,
  required FlutterLocalNotificationsPlugin plugin,
}) async {
  try {
    final price = await api.fetchGoldPriceWithFallback('SGE-Au(T+D)');
    if (price == null) return;
    final holdings = await holdingDao.list();
    var assetValue = 0.0, totalCost = 0.0;
    for (final h in holdings) {
      assetValue += price.price * h.amount;
      totalCost += h.totalCost;
    }
    final alerts = await alertDao.list();
    for (final a in alerts) {
      if (AlertService.matches(a, price: price.price, assetValue: assetValue, totalCost: totalCost)) {
        await AlertService.showNotification(plugin, '金脉提醒', AlertService.describe(a));
      }
    }
  } catch (_) {
    // 后台任务失败静默，不得崩溃。
  }
}
```

（`AlertDao.list()` / `HoldingDao.list()` 若不存在，参考现有 DAO 模式新增。）

- [ ] **Step 2: 实现 callbackDispatcher**

`main.dart` 的 `callbackDispatcher`：

```dart
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final dio = Dio(BaseOptions(headers: {'User-Agent': 'goldpulse/1.0'}));
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    await AppDatabase.init(); // 确保数据库已打开（background isolate 内独立初始化）
    await runBackgroundAlertCheck(
      api: PriceApi(dio: dio),
      alertDao: AlertDao(),
      holdingDao: HoldingDao(),
      plugin: plugin,
    );
    return Future.value(true);
  });
}
```

（背景 isolate 中 sqflite 需直接用文件路径打开；若 `AppDatabase.init()` 已在主 isolate 打开单例，background isolate 是独立 isolate，需各自初始化——按 `lib/database/app_database.dart` 现有打开方式处理。）

- [ ] **Step 3: 测试**

`test/background_alert_test.dart`：注入 fake PriceApi（返回固定价）+ 内存 AlertDao/HoldingDao + 注入 FakePlugin，断言：价格/资产/收益提醒在命中时触发 `showNotification`；未启用提醒不触发；拉价失败静默返回。

- [ ] **Step 4: analyze + 全量测试**

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: 后台提醒落地（WorkManager 拉价+判定+通知）"
```

---

## 验收（全部任务完成后）

- [ ] 同品种多次不同价买入：克重求和、均价=加权平均，首页/资产页收益正确
- [ ] 两种积存金：首页每品种一张收益卡 + 全部合计卡
- [ ] 资产页顶部汇总块显示全部持仓三口径合计
- [ ] 持仓详情页展示交易流水，可追加买入/卖出/生息/删除交易（回滚）
- [ ] 后台提醒：App 完全退出后 15 分钟级任务拉价并判定通知（前台行为不回归）
- [ ] `flutter analyze` 零告警 + `flutter test` 全绿 + 真机验证 + 推送 main

### Task 6: 买卖成本逻辑修正（加权平均成本法，用户明确规则）

**用户规则（2026-08-04 明确）：**
1. **买入**：新总成本 = 原总成本 + 本次买入金额；新数量 = 原数量 + 本次数量；新均价 = 新总成本 ÷ 新数量（**加权平均，均价改变**）。
2. **卖出**：扣除成本 = 均价 × 卖出数量；新总成本 = 原总成本 − 扣除成本；新数量 = 原数量 − 卖出数量；**均价保持不变**。

**现状问题**：`applyTrade` 卖出分支 `totalCost` 不变 → 卖出后均价跳升，违反规则 2；且累计收益公式 `Σ卖出净得+现价×数量−totalCost` 在"卖出扣成本"的新模型下会虚增已实现部分。

**Files:**
- Modify: `goldpulse/lib/models/holding.dart`（新增 `boughtCost` 字段）
- Modify: `goldpulse/lib/database/app_database.dart`（DB v2→v3 迁移）
- Modify: `goldpulse/lib/services/calculator.dart`（applyTrade / reverseTrade / cumulativeProfit）
- Modify: `goldpulse/lib/database/holding_dao.dart`（recordTrade / deleteTrade 维护 boughtCost）
- Modify: `goldpulse/lib/state/holding_provider.dart`（recordTradeProvider / deleteTradeProvider 传 boughtCost）
- Modify: `goldpulse/lib/state/asset_provider.dart`（typeSummaries 用 boughtCost 算累计；**删除死代码 assetSummaryProvider**）
- Modify: `goldpulse/test/state_test.dart`（删 assetSummaryProvider 用例；typeSummaries 累计断言改 boughtCost 口径）
- Test: `goldpulse/test/calculator_test.dart`、`goldpulse/test/transaction_test.dart`、`goldpulse/test/database_test.dart`

- [ ] **Step 1: Holding 增 `boughtCost` + DB v2→v3 迁移**

`Holding` 新增 `final double boughtCost;`（累计买入总成本）。toMap/fromMap 增列 `bought_cost`；构造器缺省 `this.boughtCost = 0` 但**创建持仓（addHolding）时必传 boughtCost = totalCost**。

`app_database.dart` 版本 2→3：`_onUpgrade` 中 `oldV < 3` 时执行 `ALTER TABLE holdings ADD COLUMN bought_cost REAL NOT NULL DEFAULT 0`；随后 `UPDATE holdings SET bought_cost = total_cost`（存量行：旧模型 totalCost 从未被卖出扣减，即等于买入总成本）。`_onCreate` 建表 SQL 同步加 `bought_cost REAL NOT NULL DEFAULT 0`。

- [ ] **Step 2: Calculator 三方法改造**

```dart
/// 加权平均成本法。
/// 买入：总成本与累计买入成本都加 amount×price（均价改变）。
/// 卖出：总成本扣除 当前均价×卖出数量（均价不变），累计买入成本不变。
/// 生息：仅克重增，成本不变。
static ({double amount, double totalCost, double boughtCost}) applyTrade({
  required double amount,
  required double totalCost,
  required double boughtCost,
  required TradeRecord record,
}) {
  switch (record.type) {
    case 'buy':
      return (amount: amount + record.amount,
          totalCost: totalCost + record.amount * record.price,
          boughtCost: boughtCost + record.amount * record.price);
    case 'interest':
      return (amount: amount + record.amount, totalCost: totalCost, boughtCost: boughtCost);
    case 'sell':
      if (record.amount > amount) throw ArgumentError('卖出克重不能大于当前持仓');
      final avg = avgCost(totalCost, amount);
      return (amount: amount - record.amount,
          totalCost: totalCost - avg * record.amount,
          boughtCost: boughtCost);
    default:
      throw ArgumentError('未知交易类型: ${record.type}');
  }
}
```

`reverseTrade` 对称回滚（buy 减回、sell 加回 avg×卖出数量、interest 减克重；负值返回 null）。`cumulativeProfit` 签名改 `boughtCost`：

```dart
/// 累计收益 = Σ卖出净得 + 现价×数量 − 累计买入总成本（boughtCost）。
static double cumulativeProfit({
  required double currentPrice,
  required double amount,
  required double boughtCost,
  required Iterable<TradeRecord> sellTrades,
}) => sellNetProceeds(sellTrades) + currentPrice * amount - boughtCost;
```

- [ ] **Step 3: DAO / Provider 维护 boughtCost**

`HoldingDao.recordTrade` / `deleteTrade` 增加 `boughtCost` 参数写入。`recordTradeProvider` / `deleteTradeProvider` 调 `applyTrade`/`reverseTrade`（含 boughtCost）后传入。

- [ ] **Step 4: typeSummaries 用 boughtCost；删除死代码 assetSummaryProvider**

`typeSummariesProvider` 中：`boughtCost = Σ holding.boughtCost`；`cumulativeProfit(currentPrice, totalGrams, boughtCost: ΣboughtCost, sells)`。持仓收益仍用 `ΣtotalCost`（剩余成本基础）；均价 = ΣtotalCost ÷ Σ克重。

删除 `assetSummaryProvider`（死代码，仅 state_test 引用）与其 state_test 用例；若 state_test 中旧 `assetSummaryProvider` 测试断言改为改用 `typeSummariesProvider`。

- [ ] **Step 5: 测试（按用户示例逐条验证）**

```dart
// calculator_test.dart
test('加权平均成本法：买卖成本变化', () {
  // 买 100g@780 → (100, 78000, 78000, avg 780)
  final b1 = Calculator.applyTrade(amount: 0, totalCost: 0, boughtCost: 0,
      record: TradeRecord(holdingId: 1, type: 'buy', amount: 100, price: 780, fee: 0, time: 1));
  expect(b1.amount, 100); expect(b1.totalCost, 78000); expect(b1.boughtCost, 78000);
  // 再买 50g@800 → (150, 118000, 118000, avg 786.67)
  final b2 = Calculator.applyTrade(amount: b1.amount, totalCost: b1.totalCost, boughtCost: b1.boughtCost,
      record: TradeRecord(holdingId: 1, type: 'buy', amount: 50, price: 800, fee: 0, time: 2));
  expect(b2.amount, 150); expect(b2.totalCost, 118000);
  expect(Calculator.avgCost(b2.totalCost, b2.amount), closeTo(786.67, 0.01));
  // 卖 50g@900 → (100, 78666.5, 118000, avg 786.67 不变)
  final s = Calculator.applyTrade(amount: b2.amount, totalCost: b2.totalCost, boughtCost: b2.boughtCost,
      record: TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 900, fee: 36, time: 3));
  expect(s.amount, 100);
  expect(s.totalCost, closeTo(78666.5, 0.01));
  expect(s.boughtCost, 118000);
  expect(Calculator.avgCost(s.totalCost, s.amount), closeTo(786.67, 0.01));
  // 累计收益不虚增：Σ卖出净得(45000−36) + 现价×100 − 118000
  expect(Calculator.cumulativeProfit(currentPrice: 900, amount: 100, boughtCost: 118000,
      sellTrades: [TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 900, fee: 36, time: 3)]),
      closeTo(44964 + 90000 - 118000, 0.01));
});
```

数据库迁移测试（database_test.dart）：v2 库（旧列）打开后 bought_cost 列存在且回填 = total_cost。

- [ ] **Step 6: analyze + 全量测试**

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: 买卖成本加权平均法（卖出扣成本、均价不变，boughtCost 追踪累计投入）"
```


---

### Task 7: 提醒删除 + 收益目标判定修正（用户反馈）

**问题**：① 提醒条目只有开关、无法删除；② 收益目标 `profit_target` 判定用**总资产**（assetValue ≥ 40）而非**收益**，资产价值恒大导致 <40 也触发；文案显示「黄金资产 ≥ 40」。

**Files:**
- Modify: `goldpulse/lib/services/alert_service.dart`（matches / describe）
- Modify: `goldpulse/lib/state/alert_provider.dart`（新增 `deleteAlertProvider`）
- Modify: `goldpulse/lib/pages/alert_page.dart`（_AlertTile 加删除入口）
- Test: `goldpulse/test/alert_service_test.dart`、`goldpulse/test/alert_wiring_test.dart`

**改动：**
1. `AlertService.matches`：`profit_target` 改为 `(assetValue - totalCost) >= a.target`（收益达标才触发）。
2. `AlertService.describe`：`profit_target` 文案改为 `'收益 ≥ ${a.target.toStringAsFixed(0)} 元'`。
3. `alert_provider.dart` 新增 `deleteAlertProvider = FutureProvider.family<void, int>`（alertDao.delete + invalidate alertsProvider）。
4. `alert_page.dart` `_AlertTile`：trailing 加删除 IconButton（红，Icons.delete_outline）+ 确认 AlertDialog；开关保留。
5. 添加弹层 profit_target 输入提示改「收益目标（元）」。
6. 测试：matches 收益判定正反例；describe 文案；删除动作（tap 删除 → 确认 → 列表移除）。

### Task 8: 提醒品种选择（Au9999/浙商/工商，用户反馈）

**问题**：创建提醒无法选品种，默认 Au9999；价格提醒判定只用 Au9999 价。

**Files:**
- Modify: `goldpulse/lib/models/alert.dart`（新增 `kind` 字段，默认 'au9999'）
- Modify: `goldpulse/lib/database/app_database.dart`（DB v3→v4：alerts 表加 `kind TEXT NOT NULL DEFAULT 'au9999'`）
- Modify: `goldpulse/lib/state/alert_provider.dart`（runAlertChecks 加 `kind` 参数 + 按品种过滤）
- Modify: `goldpulse/lib/pages/alert_page.dart`（添加弹层加品种下拉；_AlertTile 副标题显示品种）
- Modify: `goldpulse/lib/state/price_provider.dart`（三个行情轮询调用 runAlertChecks 时传各自 kind）
- Modify: `goldpulse/lib/services/background_alert.dart`（后台检查按品种）
- Test: `goldpulse/test/alert_wiring_test.dart`、`goldpulse/test/database_test.dart`（迁移）

**改动：**
1. `Alert` 新增 `kind`（'au9999'|'accumulation'|'icbc'，默认 'au9999'）；toMap/fromMap 增列 `kind`；DB v3→v4 迁移 `ALTER TABLE alerts ADD COLUMN kind TEXT NOT NULL DEFAULT 'au9999'`（_onCreate 同步）。
2. `runAlertChecks` 增加 `String? kind` 参数：`price_up`/`price_down` 仅当 `a.kind == kind` 时判定；`profit_target` 不区分品种（用传入的聚合 assetValue−totalCost）。
3. `priceProvider`（Au9999）调用 `runAlertChecks(kind: 'au9999')`；`accumulationPriceProvider` → kind 'accumulation'；`icbcPriceProvider` → kind 'icbc'。profit_target 只在 Au9999 轮询判一次（避免重复通知）。
4. 添加弹层：新增「品种」下拉（Au9999 / 浙商积存金 / 工商积存金）；选择 profit_target 时品种下拉禁用（不区分品种）。
5. `AlertService.describe`：price_up/down 显示品种名（如「浙商积存金 价格 ≥ X 元/g」）。
6. `_AlertTile` 副标题显示品种名。
7. 后台 `runBackgroundAlertCheck` 拉各品种价并按品种判定 Au9999 提醒 + profit_target。

### Task 9: 行情页折线图最高/最低点金额标签（用户反馈）

**Files:**
- Modify: `goldpulse/lib/widgets/chart.dart`（PriceLineChart 加最高/最低点标签）
- Test: 新增 `goldpulse/test/chart_label_test.dart`

**改动：**
1. `PriceLineChart`：识别 spots 中最高（maxY）与最低（minY）的数据点；用 `FlDotData(getDotPainter: ...)` 在最高/最低点绘制强调圆点 + 金额文本标签（fmtPrice，2 位小数，金/白色，置于点上方或下方避免重叠）。
2. 标签文案：最高点显示如 `886.10`、最低点 `878.51`。
3. 不影响既有坐标轴/触摸气泡/渐变面积；1 个点时标签不重叠。
4. 测试：构造含明确最高/最低的 spots，断言标签文本渲染（pump 后 find.text）。


### Task 10: 追加买入对话框合并（克重 + 买入均价同框可编辑，用户反馈）

**问题**：追加买入用两个连续 `promptNumber`（先克重、再价格），用户反馈"只能写克重，不能写买入时均价"——体验混乱。改为**单个对话框同时输入克重与买入单价**，单价默认当前行情价且可编辑。

**Files:**
- Modify: `goldpulse/lib/widgets/number_dialogs.dart`（新增 `promptBuy`）
- Modify: `goldpulse/lib/pages/holding_detail_page.dart`（_buy 改用 promptBuy）
- Modify: `goldpulse/lib/widgets/holding_list_tile.dart`（追加买入改用 promptBuy）
- Test: `goldpulse/test/holding_detail_test.dart`、`goldpulse/test/holding_actions_test.dart`

**改动：**
1. `number_dialogs.dart` 新增 `Future<({double amount, double price})?> promptBuy(BuildContext, {String? defaultPrice})`：单个 AlertDialog，含「买入克重 (g)」与「买入价格 (元/g)」两个 TextField（价格默认 defaultPrice，可编辑）；两字段校验 >0 且克重≤当前持仓上限时返回 record，否则内联报错（复用 _promptSell 的双输入模式）。
2. `holding_detail_page._buy` 与 `holding_list_tile` 追加买入改用 `promptBuy(defaultPrice: 该品种现价)`；成功后 recordTradeProvider(buy)。
3. 测试：追加买入对话框渲染双字段；输入克重+价格后持仓克重/均价正确更新。
