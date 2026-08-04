# 持仓域重构 + 后台提醒落地 设计文档

> 日期：2026-08-04
> 来源：brainstorming 流程（用户选定范围 + 首页呈现形式）
> 关联计划：docs/superpowers/plans/2026-08-04-app-redesign-v2.md

## 1. 目标

修复并升级持仓域，使多持仓 / 多品种 / 多次不同价买入正确工作，并提供交易流水查看与后台提醒。

用户明确的三点诉求：
1. 同一积存金多次不同价买入 → 首页按对应品种计算，克重求和、成本按多次买入价**加权平均**。
2. 买了两种积存金 → 首页**每个品种都显示**（当前只显示第一笔）。
3. 资产页新增**汇总块**：全部持仓的 持仓收益 / 今日盈亏 / 累计收益 合计。

## 2. 范围界定

**本次做：**
- 持仓域：多品种收益聚合（类型级）、追加买入、持仓详情页（交易流水）、资产页汇总块、首页按品种多卡。
- 后台提醒：WorkManager `callbackDispatcher` 真正生效（后台拉价 + 提醒判定 + 通知）。

**本次不做：** 更多银行积存金、行情图表指标、主题切换、国际化、收益曲线（后续迭代）。

## 3. 收益模型（核心：按品种聚合）

### 3.1 聚合口径
- **按品种（kind）分组**：`accumulation`（浙商积存金）、`icbc`（工商积存金）、`au9999`（Au9999）。
- 同一品种多笔持仓合并：
  - 总克重 = Σ 各持仓克重
  - 总成本 = Σ 各持仓 totalCost（多次买入累加，`applyTrade` buy 分支天然支持）
  - **均价 = 总成本 ÷ 总克重**（加权平均，多价买入自动正确）
  - 累计收益的已实现部分 = Σ 该品种下所有持仓的卖单净得（amount×price − fee）
- 每个品种用**自己的行情价**（accumulation→CZB-JCJ、icbc→ICBC-JCJ、au9999→SGE-Au(T+D)）与 `preClose` 计算：
  - 持仓收益 = 现价 × 总克重 − 总成本
  - 今日盈亏 = (现价 − 昨收) × 总克重
  - 累计收益 = Σ卖单净得 + 现价 × 总克重 − 总成本

### 3.2 新增模型与 Provider
- `TypeAssetSummary`（lib/state/asset_provider.dart）：kind、label、totalGrams、avgCost、currentPrice、preClose、floatingProfit、todayProfit、cumulativeProfit。
- `typeSummariesProvider`（FutureProvider<List<TypeAssetSummary>>）：加载 holdings + trades，按 kind 聚合；行情价取对应 provider 的 valueOrNull，无行情返回 null 条目（该品种显示 '--'）。
- `totalAssetSummaryProvider`（FutureProvider<TypeAssetSummary?>）：全品种合计（线性可加：累计=Σ各品种累计，持仓=Σ各品种持仓，今日=Σ各品种今日）。
- **保留**每笔持仓自身的计算（资产列表/HoldingListTile 仍逐笔展示三口径）。

### 3.3 Calculator 新增
- `typeCumulativeProfit` / 复用现有 `cumulativeProfit`（sells 参数改为传入该品种全部卖单）。
- 均价计算复用 `avgCost(totalCost, amount)`（已是加权）。

## 4. UI 改动

### 4.1 首页（home_page.dart）
- 移除对 `assetSummaryProvider`（holdings.first）的依赖。
- 收益区改为：
  - 每个品种一张 `ProfitCard`（名称/克重/均价/三口径，数据来自 `typeSummariesProvider`），用该品种自己的行情价。
  - 底部一张**「全部持仓」合计卡**（来自 `totalAssetSummaryProvider`）。
  - 无持仓 → 现有 CTA 引导。
- 卡片文案区分品种（浙商积存金 / 工商积存金 / Au9999）。

### 4.2 资产页（asset_page.dart）
- 顶部新增**「持仓汇总」块**：合计 持仓收益 / 今日盈亏 / 累计收益（`totalAssetSummaryProvider`）；可折叠或固定一行。
- 持仓列表每笔可**点击进入详情页**（新增 route）。
- 长按菜单新增「追加买入」。

### 4.3 持仓详情页（新页面 holding_detail_page.dart）
- 展示：持仓名称/品种、当前克重、均价成本、该笔持仓三口径收益。
- 交易流水列表：buy/interest/sell 记录（时间、类型、克重、价格、手续费、该笔后克重）。
- 操作：追加买入 / 记卖出 / 加记生息 / 删除交易（从 DB 移除并回滚克重成本）。
- 样式复用黑金主题 + EmptyState。

### 4.4 追加买入流程（复用 Calculator.applyTrade 'buy'）
- 入口：持仓长按菜单 + 详情页按钮。
- 对话框：买入克重 + 买入价格（默认该品种当前行情价）。
- `recordTradeProvider(TradeRecord(type:'buy', amount, price, fee:0))` → 原子更新持仓克重与总成本。

## 5. 后台提醒（WorkManager callbackDispatcher 落地）

### 5.1 现状
- `main.dart:43` `callbackDispatcher` 仅注册任务并 `return true`，**后台不拉价不判定**。
- 前台轮询已在新价到达时即时判定（`runAlertChecks`）。

### 5.2 目标
- 后台（App 未运行/被系统冻结）每 15 分钟：拉取各品种最新价 → 对启用的提醒判定 → 命中发本地通知。

### 5.3 实现要点
- `callbackDispatcher` 内独立初始化：`Workmanager` 回调中创建 Dio、打开 sqflite（直接 openDatabase 文件路径）、初始化通知插件。
- 复用 `PriceApi.fetchGoldPriceWithFallback`（按品种 code）与 `AlertDao`、`runAlertChecks`。
- 每个启用提醒按其关联品种拉价判定（或一次拉全品种缓存后逐条判定）。
- 失败静默（后台任务不得崩溃）。
- 与前台共用的判定逻辑抽到 `AlertService`（保持单一实现，前后台一致）。

## 6. 测试

- `test/asset_provider_test.dart`：typeSummariesProvider 聚合（同品种多笔合并克重/均价、多品种分开、卖单已实现、无行情 → null 条目）。
- `test/calculator_test.dart`：追加 buy 后均价正确；跨品种 cumulative 线性可加。
- `test/holding_detail_test.dart`：详情页交易流水渲染、追加买入动作、删除交易回滚。
- `test/widget_smoke_test.dart`：首页多品种收益卡渲染、资产页汇总块。
- 后台提醒：`check_alerts_test.dart` 已有判定逻辑测试；新增后台 fetch+判定集成测试（模拟注入）。
- 全量回归：`flutter analyze` 零告警 + `flutter test` 全绿（基线 115）。

## 7. 验收标准

- [ ] 同品种多次不同价买入：克重求和、均价=加权平均、首页/资产页收益正确。
- [ ] 两种积存金：首页各品种一张收益卡 + 全部合计卡。
- [ ] 资产页顶部汇总块显示全部持仓三口径合计。
- [ ] 持仓详情页展示交易流水，可追加买入/卖出/生息/删除交易。
- [ ] 后台提醒：App 完全退出后，15 分钟级后台任务拉价并判定通知（前台行为不回归）。
- [ ] analyze 零告警、测试全绿、真机验证、推送 main。

## 8. 风险

| 风险 | 对策 |
|------|------|
| 后台 isolate 初始化 sqflite/dio 复杂 | 最小化后台依赖，失败静默；后台只做拉价+判定+通知 |
| 交易删除回滚成本复杂（如删除的是最早的买入） | 删除交易 = 反向 applyTrade（sell→buy、buy→sell）；克重/成本可能为负时禁止删除 |
| 首页多卡过长 | 品种卡片紧凑化；空品种不显示 |
