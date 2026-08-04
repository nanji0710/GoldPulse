# 2026-08-04 全 App 界面重构 v2 实施计划

## 计划来源

- 设计总案：`docs/app-redesign-v2.md`（6 页面 + 弹层 + 共享组件）
- 行情页专项：`docs/market-page-redesign-v2.md`（图表规范）
- UI 可视化：`docs/ui-mockup.html`（8 框线框图，浏览器可预览）
- 用户新需求：收益三口径 —— **持仓收益 / 今日盈亏 / 累计收益**

## Global Constraints（全局约束）

1. 主题 token 一律取自 `lib/constants/app_theme.dart`（黑金 v2：#0F172A 背景 / #1E293B 卡片 / 金 #D9A441 / 红涨 #E5484D / 绿跌 #2E9E6B / cardRadius 20 / heroGradient），不得硬编码新色值。
2. 红涨绿跌（国内习惯）不变；数字一律 `FontFeature.tabularFigures()` 等宽对齐。
3. 收益三口径公式（不得改动口径）：
   - 持仓收益 = 现价 × 克重 − 总成本
   - 今日盈亏 = (现价 − 昨收 preClose) × 克重
   - 累计收益 = Σ卖出净得 + 当前市值 − 总成本
4. 触控目标 ≥44px；相邻可点元素间距 ≥8px。
5. 空态必须可行动（图标 + 标题 + 说明 + 按钮）。
6. 既有测试不得被破坏：`flutter analyze` 零告警；`flutter test` 全绿。
7. Windows 环境：每次 Bash 调用 flutter 前先执行
   `export PATH="$(printf '%s' "$PATH" | tail -n 1)"`，并设
   `FLUTTER_STORAGE_BASE_URL=https://mirror.nju.edu.cn/flutter`、
   `PUB_HOSTED_URL=https://pub.flutter-io.cn`（release 构建另加
   `GOLDPULSE_KEY_PASS='GoldPulse@2026Key'`）。
   flutter 位于 `/c/Users/RED CHAMBER/flutter/bin/flutter`。
8. 提交信息用中文前缀（feat/fix/style/test: 描述），直接提交 main（用户已授权）。

---

## Task 0: 数据层与共享基础（控制器已完成，待评审）

**状态：实现已完成（未提交），本任务只做评审门禁。**

已实现内容：
- `lib/services/calculator.dart`：新增 `todayProfit` / `sellNetProceeds` / `cumulativeProfit`
- `lib/state/asset_provider.dart`：AssetSummary 增加 preClose/todayProfit/cumulativeProfit；provider 读 tradeDao 卖单
- `lib/widgets/profit_card.dart`：三口径展示（持仓收益大字 + 今日/累计双迷你卡）
- `lib/pages/home_page.dart`：收益卡传三口径；持仓空态 → 图标+文案+「去添加」按钮；导入 app.dart 的 shellTabProvider
- `lib/app.dart`：新增 `shellTabProvider`，MainShell 改 ConsumerStatefulWidget 绑定
- `lib/widgets/gold_card.dart`：状态胶囊 Flexible + 溢出省略
- `lib/widgets/empty_state.dart`：新增统一空态组件（icon+title+desc+action，按钮 ≥44px）
- `lib/widgets/chart.dart`：PriceLineChart 增加左右双轴刻度 / 金色渐变面积 / 触摸气泡（价格+时间）/ 时间刻度（timeFormatter 可切换 HH:mm / MM-DD）；CandlestickChart 增加水平网格 + 绿跌空心（色盲友好）

评审要求：按 Global Constraints 逐条核对；重点核查收益公式与 mockup 一致、主题 token 复用、既有测试未被破坏。

## Task 1: 行情页整页重构（market_page）

**规格（详见 docs/market-page-redesign-v2.md + ui-mockup.html 行情框）：**

自上而下：
1. AppBar「行情」+ 右侧刷新按钮（invalidate priceProvider/accumulationPriceProvider + 重载历史）
2. 价格头卡（hero 渐变）：`Au9999 · 上海金` 标签 + 状态胶囊（MarketHours.label/resumeHint）；大字价格（实时流 priceProvider）+ `元/g`；涨跌胶囊（红涨绿跌，复用 GoldCard 语言）；`更新于 HH:MM:SS`
3. 区间统计卡：区间最高 / 区间最低 / 区间涨跌（首尾差%，红涨绿跌），三列等宽
4. 周期分段控件：胶囊容器（card 色 + radius 999 + padding 4 + border divider），激活段金底 alpha 0.16 金字，未激活次级色；高度 ≥44px；切换周期即重载数据；右侧独立「K线」切换按钮（图标 + 文字，选中金框）
5. 图表卡（card 色 + radius 20）：折线 → `PriceLineChart(spots, times, timeFormatter)`（1日 → HH:mm，7日/30日 → MM-DD）；K线 → `CandlestickChart`（grid 已内置）；空数据 → EmptyState（icon show_chart + 「暂无历史数据」+ 说明）
6. 数据加载：`_rows/_loading` 状态 + `_load()`（dao.recent 按周期取点），切换周期/刷新时 setState 重载；watch priceProvider 时新价入库后自动重载图表（半实时）；加载中显示转圈卡片

周期点数：1日=240、7日=240、30日=720；K线聚合组 = 点数/30 向上取整。
既有测试要求：`widget_smoke_test.dart` 中「1日/7日/30日/K线」文案必须仍可寻址（分段控件与按钮文字不变）。

## Task 2: 引导页优化（onboarding）

- 每步加 hero 金色图标（4 步：🔐 本地免费无账号 / 📈 选择行情 / 🏦 录入持仓 / 🔔 价格提醒 → 用 Material 图标：lock_outline、trending_up、account_balance_wallet_outlined、notifications_active_outlined）
- 图标呈现：96×96 圆形金底（alpha 0.12）+ 金色图标 + 柔和辉光
- 页面指示点：4 圆点，当前页金色加宽（18px），其余 divider 色 6px
- 背景：顶部 heroGradient 渐变（#1B2A44 → background）
- 保留「跳过」、底部金色 CTA（下一步/开始使用，高 52）
- 不破坏 `widget_smoke_test.dart` 引导页测试（金脉 GoldPulse / 跳过 可寻）

## Task 3: 资产页（asset + holding_list_tile）

- 空态：EmptyState（icon account_balance_wallet_outlined + 「还没有持仓记录」+ 说明 + 「添加第一笔持仓」按钮 → 打开添加弹层）
- `holding_list_tile.dart`：
  - 标题行：名称 + 右侧浮动盈亏胶囊（红涨绿跌，▲/▼ + 金额）
  - 副标题：`50.00g · 成本 870.00 元/g`
  - 卡片底部三口径收益行：持仓收益 / 今日盈亏 / 累计收益（等宽三列，着色）
  - 价格来源按持仓类型：accumulation → accumulationPriceProvider，否则 priceProvider
- 添加弹层 `_AddHoldingSheet`：顶部加拖拽把手（36×4 divider 色圆条）；其余保持
- 不破坏 `widget_smoke_test.dart` 资产页测试（「添加你的第一笔黄金持仓」文案保留）

## Task 4: 提醒页（alert）

- 顶部延迟提示：整条色块 → 卡片化 notice（card 色 + border divider + radius 14 + ℹ 图标 + 文案），水平 padding 16
- 空态：EmptyState（icon notifications_none + 「暂无提醒」+ 说明 + 「添加提醒」按钮 → 打开添加弹层）
- `_AlertTile`：加类型 leading 图标（price_up → trending_up 金底；price_down → trending_down 绿底；profit_target → savings_outlined 绿底）
- `_AddAlertSheet`：
  - 顶部拖拽把手
  - 类型下拉用 DropdownButtonFormField（样式与资产页一致）
  - 目标值 TextField 非法时**内联 errorText**（当前实现非法值静默返回，必须改为显示错误）
  - 保存按钮金色
- 不破坏 `widget_smoke_test.dart`（无提醒页断言）

## Task 5: 设置页（setting）

- 三组分组卡片：刷新频率 / 数据管理 / 关于（card 色 + radius 16 + 组间间距 8）
- 每行 leading 图标：刷新间隔 timelapse、导出 upload、导入 download、清空 delete_sweep_outlined（红色）、关于 info_outline
- 关于行右侧加金色版本徽标 pill（v0.1.0）
- 保留全部既有功能（导出/导入/清空/间隔选择逻辑不动）
- 不破坏 `widget_smoke_test.dart`（无设置页断言）

## Task 6: 测试补充与回归

- `test/calculator_test.dart` 增补：todayProfit（含负值）、sellNetProceeds（多卖单+手续费）、cumulativeProfit（无交易=持仓收益；全卖出=纯已实现；部分卖出混合）
- 新增 `test/market_stats_test.dart`：区间统计计算（最高/最低/涨跌%）纯函数化后单测（若统计逻辑在 widget 内，先抽出可测函数）
- 新增 `test/empty_state_test.dart`：EmptyState 渲染 icon/title/action 回调
- 全量回归：`flutter analyze` 零告警 + `flutter test` 全绿

---

## 验收（全部任务完成后）

- [ ] 6 页面 + 弹层与 ui-mockup.html 一致
- [ ] 行情页图表可读（双轴刻度/触摸气泡/区间统计/空态）
- [ ] 收益三口径在首页收益卡与资产列表均展示
- [ ] analyze 零告警、测试全绿、真机安装验证
- [ ] 提交并推送 main

## Task 7（修订）: 行情页黄金类型切换（三类型，依赖 Task 9）

行情页需支持在 **Au9999 / 浙商积存金 / 工商积存金** 三类型间切换（依赖 Task 9 提供的 icbcPriceProvider 与统一 getGoldPrice 源）。

规格：
1. 价格头卡顶部标签区改为紧凑分段控件 `[Au9999 | 浙商积存金 | 工商积存金]`（两段，样式与周期分段控件一致但更小，高度 ≥44px 可点击；激活段金底 alpha 0.16 金字）
2. 切换类型时：
   - 实时价来源切换：Au9999 → `priceProvider`；浙商 → `accumulationPriceProvider`；工商 → `icbcPriceProvider`（均 valueOrNull）
   - 历史数据代码切换：`'SGE-Au(T+D)'` ↔ `'CZB-JCJ'` ↔ `'ICBC-JCJ'`（dao.recent），重载图表与区间统计
   - 头卡「数据源」展示跟随实时价
3. 状态在类型切换间独立保留？不要求——切换即重载即可
4. 空态/加载态复用现有逻辑（CZB-JCJ 无历史时显示 EmptyState 提示）
5. 既有 smoke test 的 1日/7日/30日/K线 文案保持可寻址
6. flutter analyze 零告警 + flutter test 全绿

## Task 8: 刷新频率增加 1S/5S/10S（用户新需求）

设置页刷新间隔选项需增加 1 秒 / 5 秒 / 10 秒。
- setting_page.dart `_refreshOptions`（当前 30/60/120/300/900 秒）前置插入 1/5/10
- `_label(Duration)` 显示格式化需正确显示「1 秒 / 5 秒 / 10 秒」（检查现有秒级分支）
- 行情页倒计时 `nextRefreshFreqText` 已支持秒级（"每 10 秒刷新"）——验证不回归
- 1 秒级轮询对免费接口压力大：实现即可，不额外限流（用户明确要求）
- flutter analyze 零告警 + flutter test 全绿

## Task 9: 工商积存金（京东金融源）（用户新需求）

新增**工商银行积存金**行情（来源同为 api.jdjygold.com stdLatestPrice，SKU 待发现验证）。
- `lib/services/price_api.dart`：fetchAccumulationPrice 参数化 productSku + 展示名（或新增 fetchIcbcPrice），code='ICBC-JCJ'
- `lib/state/price_provider.dart`：新增 `icbcPriceProvider`（StreamProvider，模式同 accumulationPriceProvider，轮询/降级/30s 重试一致）
- 持仓类型：addHolding 下拉新增「工商积存金」（kind='icbc'）；asset_provider / holding_list_tile 价格选择 kind=='icbc' → icbcPriceProvider
- 首页：新增第三张 GoldCard（工商积存金）
- 行情页类型切换（Task 7）扩展为三类型 [Au9999 | 浙商积存金 | 工商积存金]
- flutter analyze 零告警 + flutter test 全绿

## Task 9（修订）: 工商积存金 + 统一行情源（用户新需求 + 参考项目确认）

**SKU/接口已确认**（参考 https://github.com/SkrMiiKio/gold-price-monitor + 实测 2026-08-04）：
- 所有品种统一走 `getGoldPrice?goldCode=<uniqueCode>`，返回完整当日字段
  - Au9999 = `SGE-Au(T+D)`；浙商积存金 = `CZB-JCJ`；工商积存金 = `ICBC-JCJ`
- 实测 ICBC-JCJ: lastPrice=884.21 preClose=878.20 openPrice=880.69 highPrice=884.76 lowPrice=880.46

改动：
1. `lib/models/gold_price.dart`：GoldPrice 增加可选日线字段 `openPrice/highPrice/lowPrice`（day stats；fromMap/toMap 同步，旧行默认 0/null 兼容）
2. `lib/services/price_api.dart`：parseJdGoldPrice 解析 openPrice/highPrice/lowPrice；浙商积存金改用 getGoldPrice?goldCode=CZB-JCJ（替换 stdLatestPrice，代码统一、获得日线字段）；新增 `fetchGoldPrice('ICBC-JCJ')` 即可（已通用）
3. `lib/state/price_provider.dart`：新增 `icbcPriceProvider`（StreamProvider，code='ICBC-JCJ'，模式同 priceProvider：轮询/降级/30s重试）；浙商与工商均为独立轮询流
4. 持仓类型下拉：新增「工商积存金」kind='icbc'；asset_provider / holding_list_tile 价格选择 kind=='icbc' → icbcPriceProvider
5. 首页：新增第三张 GoldCard（工商积存金）
6. flutter analyze 零告警 + flutter test 全绿

## Task 10: 当日行情四字段（用户新需求）

行情页增加**当日最高价 / 当日最低价 / 当日开盘价 / 上日收盘价**展示（数据来自 getGoldPrice 返回的 highPrice/lowPrice/openPrice/preClose）。
- 行情页在价格头卡与区间统计之间（或区间统计卡内）加「当日统计」行：当日最高 / 当日最低 / 当日开盘 / 昨收（四列或 2×2）
- 数据源：当前所选类型的实时流（priceProvider/accumulationPriceProvider/icbcPriceProvider）的 day 字段；无数据时显示 '--'
- 与现有「区间统计」（按周期历史计算）区分：当日统计 = API 日线字段；区间统计 = 所选周期历史高低
- 首页 GoldCard 可选加一行当日幅度（可选，先做行情页）
- 不破坏既有测试；flutter analyze 零告警 + flutter test 全绿
