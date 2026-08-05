# 智能交易建议卡片 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在首页顶部（三行情卡之前）增加一张黑金风格小卡片「智能建议」，基于近期涨跌趋势 + 当前持仓盈亏动态生成买卖建议（持有/买入/止盈/减仓/补仓/观望/风险提醒/待积累），带 0-100 置信度评分与防频繁提醒冷却。

**Architecture:** 四层解耦——`TrendAnalyzer`（纯函数趋势判断）→ `SignalEngine`（纯函数评分 + 信号规则 + 冷却）→ `suggestionsProvider`（Riverpod FutureProvider 组合持仓汇总 + DB 行情序列）→ `TradeSuggestionCard`（首页顶部 UI）。UI 视觉遵循 App 黑金主题（`AppTheme`）。

**Tech Stack:** Flutter 3.44.8 / Dart 3.12.2 / Riverpod 2.x / sqflite / shared_preferences。测试用 `flutter test`。

## Global Constraints

- 项目根：`goldpulse/` 子目录是 Flutter 应用。测试命令在 `goldpulse/` 下运行：`flutter test test/<file>.dart`。
- 运行 `flutter test` 前先 `export PATH="$(printf '%s' "$PATH" | tail -n 1)"`（Windows PATH 污染规避），且**不要**在测试或构建前手动跑 `flutter pub get` 更新依赖——pubspec.yaml 已锁定 workmanager 0.9.0.x，跑 `flutter test` 会自动 pub get 且不改变锁定。
- 颜色使用 `AppTheme` 常量（`gold`/`up`/`down`/`textSecondary`/`divider`/`card`/`cardHighlight`）；红涨绿跌：涨用 `AppTheme.up`（红），跌用 `AppTheme.down`（绿）。卡片圆角 `AppTheme.cardRadius`。
- 克数格式化 `fmtGrams`（4 位小数），价格 `fmtPrice`（2 位小数），金额 `fmtAmount`。来自 `goldpulse/lib/utils/formatters.dart`。
- 涨跌幅箭头 `arrow(double)`（正→'▲'，负→'▼'）来自 `formatters.dart`；建议卡片可另用 ↗/↘/→ 文本箭头（不强制 arrow()）。
- 品种 kind → 行情 code 映射固定：`'au9999'`→`'SGE-Au(T+D)'`、`'accumulation'`→`'CZB-JCJ'`、`'icbc'`→`'ICBC-JCJ'`。
- 建议文案必须带免责小字：`基于近期涨跌趋势与持仓盈亏的参考提示，非投资建议`（或等价简短文案）。
- 置信度评分权重固定：今日涨跌 30% + 近期窗口 40% + 持仓状态(收益率) 30%。
- 数据不足判定：某品种近期价格点数 < 5 → `TradeTrend.insufficient`，信号显示"待积累"。
- 防频繁提醒：一次建议 24h 内不变更，除非价格波动 > 5% 或评分变化 > 20 分。
- 多品种：主建议取**信号紧急度最高**的品种，其余品种压缩为一行摘要。
- 禁止对无持仓品种生成买入建议；无任何持仓时卡片显示提示文案。
- 所有新增逻辑函数必须纯函数、可单测；提交信息用中文（如 `feat: 新增智能交易建议卡片`）。

---
---

### Task 1: TrendAnalyzer 趋势判断纯函数

**Files:**
- Create: `goldpulse/lib/services/trend_analyzer.dart`
- Test: `goldpulse/test/trend_analyzer_test.dart`

**Interfaces:**
- Consumes: 无（纯 Dart，不依赖任何项目文件）。
- Produces: `enum TradeTrend { up, down, flat, insufficient }`；`TradeTrend trendOf(List<double> prices, {double thresholdPercent = 0.5})`。`prices` 为**按时间升序**的价格列表（最新价在末尾）；返回趋势枚举。点数 < 5 返回 `insufficient`。

- [ ] **Step 1: 写失败测试**

创建 `goldpulse/test/trend_analyzer_test.dart`：

```dart
// test/trend_analyzer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/trend_analyzer.dart';

void main() {
  group('trendOf', () {
    test('点数少于 5 → insufficient', () {
      expect(trendOf(const []), TradeTrend.insufficient);
      expect(trendOf(const [800, 801, 802, 803]), TradeTrend.insufficient);
    });

    test('近期上涨超过阈值 → up', () {
      // 100 点到 103 点：+3%
      expect(trendOf([for (var i = 0; i < 100; i++) 100 + i * 0.03]),
          TradeTrend.up);
    });

    test('近期下跌超过阈值 → down', () {
      expect(trendOf([for (var i = 0; i < 100; i++) 100 - i * 0.03]),
          TradeTrend.down);
    });

    test('波动小于阈值 → flat', () {
      // 800 到 801：+0.125%，低于 0.5% 阈值
      expect(trendOf([800, 800.2, 800.5, 800.8, 801]), TradeTrend.flat);
    });

    test('自定义阈值生效', () {
      // +0.3% 用 0.2% 阈值判定为 up
      expect(trendOf([800, 800.5, 801, 801.5, 802.4],
          thresholdPercent: 0.2), TradeTrend.up);
    });

    test('首价非正数 → insufficient（防御）', () {
      expect(trendOf([0, 800, 801, 802, 803]), TradeTrend.insufficient);
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/trend_analyzer_test.dart`
Expected: 编译失败（`trend_analyzer.dart` 不存在），测试无法加载。

- [ ] **Step 3: 实现最小代码**

创建 `goldpulse/lib/services/trend_analyzer.dart`：

```dart
// lib/services/trend_analyzer.dart
// 智能建议-趋势判断：基于近期价格序列（按时间升序，最新在末尾）判断涨跌方向。
// 纯函数、无外部依赖，供 SignalEngine 与 suggestionsProvider 复用。
enum TradeTrend { up, down, flat, insufficient }

/// [prices] 按时间升序的价格列表。点数 < 5 或数据非法返回 [TradeTrend.insufficient]。
/// [thresholdPercent] 判定为涨/跌的最小变化率（%），默认 0.5%。
TradeTrend trendOf(List<double> prices, {double thresholdPercent = 0.5}) {
  if (prices.length < 5) return TradeTrend.insufficient;
  final first = prices.first;
  final last = prices.last;
  if (first <= 0 || last <= 0) return TradeTrend.insufficient;
  final change = (last - first) / first * 100;
  if (change > thresholdPercent) return TradeTrend.up;
  if (change < -thresholdPercent) return TradeTrend.down;
  return TradeTrend.flat;
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/trend_analyzer_test.dart`
Expected: All tests passed!（6 个用例）

- [ ] **Step 5: 提交**

```bash
cd goldpulse
git add lib/services/trend_analyzer.dart test/trend_analyzer_test.dart
git commit -m "feat: TrendAnalyzer 趋势判断纯函数（点数不足→insufficient）"
```

---
---

### Task 2: SignalEngine 评分/信号/冷却纯函数

**Files:**
- Create: `goldpulse/lib/services/signal_engine.dart`
- Test: `goldpulse/test/signal_engine_test.dart`

**Interfaces:**
- Consumes: `TradeTrend`（来自 `trend_analyzer.dart`）。
- Produces:
  - `enum TradeSignal { hold, buy, takeProfit, reduce, watch, riskAlert, insufficient }`
  - `class TradeSuggestion { final String kind; final String label; final TradeTrend trend; final TradeSignal signal; final double score; final List<String> reasons; final double profitRate; final DateTime updatedAt; const TradeSuggestion({...}); }`
  - `double scoreOf({required double todayPercent, required double windowPercent, required double profitRate})`
  - `TradeSignal signalOf({required double profitRate, required TradeTrend trend, required double todayPercent})`
  - `List<String> reasonsFor(TradeSuggestion s)`
  - `TradeSuggestion applyCooling({required TradeSuggestion current, required TradeSuggestion? last, required DateTime now, required double priceMovePercent})`

规则（严格按此，写进测试）：
- 评分：`today = 50 + todayPercent * 6`；`window = 50 + windowPercent * 6`；`profit = 50 + profitRate * 1.2`；`score = (0.3*today + 0.4*window + 0.3*profit).clamp(0, 100)`。
- 信号：
  - `trend == insufficient` → `insufficient`
  - `profitRate <= -15` → `riskAlert`
  - `profitRate <= -5`：`trend == up` → `buy`，否则 `watch`
  - `profitRate <= 5` → `hold`
  - `profitRate <= 20`：`trend == up` → `hold`，否则 `reduce`
  - `profitRate > 20`：`todayPercent >= 10` → `takeProfit`，否则 `hold`
- 冷却：`last == null` → 返回 `current`；`now - last.updatedAt > 24h` 或 `priceMovePercent > 5` 或 `(current.score - last.score).abs() > 20` → 返回 `current`；`current.signal != last.signal` → 返回 `current`；否则返回 `last`（沿用上次）。

- [ ] **Step 1: 写失败测试**

创建 `goldpulse/test/signal_engine_test.dart`：

```dart
// test/signal_engine_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/signal_engine.dart';
import 'package:goldpulse/services/trend_analyzer.dart';

void main() {
  group('scoreOf', () {
    test('权重 0.3/0.4/0.3：全部中性（0%）→ 50 分', () {
      expect(scoreOf(todayPercent: 0, windowPercent: 0, profitRate: 0), 50);
    });
    test('上涨加成：今日+1%、窗口+2%、盈利+10% → 高于 50', () {
      final s = scoreOf(todayPercent: 1, windowPercent: 2, profitRate: 10);
      expect(s, greaterThan(50));
    });
    test('下跌压制：今日-1%、窗口-2%、亏损-10% → 低于 50', () {
      final s = scoreOf(todayPercent: -1, windowPercent: -2, profitRate: -10);
      expect(s, lessThan(50));
    });
    test('极端值被 clamp 到 [0,100]', () {
      expect(scoreOf(todayPercent: 999, windowPercent: 999, profitRate: 999), 100);
      expect(scoreOf(todayPercent: -999, windowPercent: -999, profitRate: -999), 0);
    });
  });

  group('signalOf', () {
    test('数据不足 → insufficient', () {
      expect(signalOf(profitRate: 0, trend: TradeTrend.insufficient, todayPercent: 0),
          TradeSignal.insufficient);
    });
    test('深度亏损 ≤ -15% → riskAlert', () {
      expect(signalOf(profitRate: -16, trend: TradeTrend.down, todayPercent: -1),
          TradeSignal.riskAlert);
    });
    test('中亏 -15~-5%：趋势向上 → buy', () {
      expect(signalOf(profitRate: -10, trend: TradeTrend.up, todayPercent: 1),
          TradeSignal.buy);
    });
    test('中亏 -15~-5%：趋势向下 → watch', () {
      expect(signalOf(profitRate: -10, trend: TradeTrend.down, todayPercent: -1),
          TradeSignal.watch);
    });
    test('小幅盈亏 -5~5% → hold', () {
      expect(signalOf(profitRate: 3, trend: TradeTrend.up, todayPercent: 0.5),
          TradeSignal.hold);
      expect(signalOf(profitRate: -3, trend: TradeTrend.down, todayPercent: -0.5),
          TradeSignal.hold);
    });
    test('盈利 5~20%：趋势向上 → hold', () {
      expect(signalOf(profitRate: 12, trend: TradeTrend.up, todayPercent: 2),
          TradeSignal.hold);
    });
    test('盈利 5~20%：趋势向下 → reduce', () {
      expect(signalOf(profitRate: 12, trend: TradeTrend.down, todayPercent: -2),
          TradeSignal.reduce);
    });
    test('盈利 >20% 且短期涨幅 ≥10% → takeProfit', () {
      expect(signalOf(profitRate: 25, trend: TradeTrend.up, todayPercent: 11),
          TradeSignal.takeProfit);
    });
    test('盈利 >20% 但短期涨幅小 → hold', () {
      expect(signalOf(profitRate: 25, trend: TradeTrend.up, todayPercent: 2),
          TradeSignal.hold);
    });
  });

  group('reasonsFor', () {
    test('riskAlert 给出亏损重新评估文案', () {
      final s = TradeSuggestion(
          kind: 'accumulation', label: '浙商积存金',
          trend: TradeTrend.down, signal: TradeSignal.riskAlert,
          score: 30, reasons: const [], profitRate: -16,
          updatedAt: DateTime(2026, 8, 5));
      final r = reasonsFor(s);
      expect(r.join(), contains('亏损'));
      expect(r.join(), contains('重新评估'));
    });
    test('buy 给出分批补仓文案', () {
      final s = TradeSuggestion(
          kind: 'accumulation', label: '浙商积存金',
          trend: TradeTrend.up, signal: TradeSignal.buy,
          score: 60, reasons: const [], profitRate: -10,
          updatedAt: DateTime(2026, 8, 5));
      final r = reasonsFor(s);
      expect(r.join(), contains('补仓'));
    });
  });

  group('applyCooling', () {
    final current = TradeSuggestion(
        kind: 'a', label: '浙商积存金', trend: TradeTrend.up, signal: TradeSignal.hold,
        score: 70, reasons: const [], profitRate: 8,
        updatedAt: DateTime(2026, 8, 5, 10));
    final last = TradeSuggestion(
        kind: 'a', label: '浙商积存金', trend: TradeTrend.up, signal: TradeSignal.hold,
        score: 68, reasons: const [], profitRate: 8,
        updatedAt: DateTime(2026, 8, 5, 9));

    test('无上次建议 → 直接返回 current', () {
      expect(applyCooling(current: current, last: null,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 0), same(current));
    });
    test('距上次 <24h 且信号一致且未突破阈值 → 沿用 last', () {
      expect(applyCooling(current: current, last: last,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 1), same(last));
    });
    test('超过 24h → 返回 current', () {
      expect(applyCooling(current: current, last: last,
          now: DateTime(2026, 8, 6, 10), priceMovePercent: 0), same(current));
    });
    test('价格波动 >5% → 返回 current（打破冷却）', () {
      expect(applyCooling(current: current, last: last,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 6), same(current));
    });
    test('评分变化 >20 → 返回 current（打破冷却）', () {
      final bigMove = TradeSuggestion(
          kind: 'a', label: '浙商积存金', trend: TradeTrend.up, signal: TradeSignal.hold,
          score: 92, reasons: const [], profitRate: 8,
          updatedAt: DateTime(2026, 8, 5, 11));
      expect(applyCooling(current: bigMove, last: last,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 1), same(bigMove));
    });
    test('信号改变 → 返回 current', () {
      final changed = TradeSuggestion(
          kind: 'a', label: '浙商积存金', trend: TradeTrend.down, signal: TradeSignal.reduce,
          score: 40, reasons: const [], profitRate: 8,
          updatedAt: DateTime(2026, 8, 5, 11));
      expect(applyCooling(current: changed, last: last,
          now: DateTime(2026, 8, 5, 11), priceMovePercent: 1), same(changed));
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/signal_engine_test.dart`
Expected: 编译失败（`signal_engine.dart` 不存在）。

- [ ] **Step 3: 实现最小代码**

创建 `goldpulse/lib/services/signal_engine.dart`：

```dart
// lib/services/signal_engine.dart
// 智能建议-信号引擎：置信度评分 + 收益率×趋势信号规则 + 理由文案 + 防频繁提醒冷却。
// 全部为纯函数，供 suggestionsProvider 组合生成建议。
import 'trend_analyzer.dart';

/// 建议信号（紧急度由高到低：riskAlert > takeProfit > reduce > buy > watch > hold > insufficient）。
enum TradeSignal { riskAlert, takeProfit, reduce, buy, watch, hold, insufficient }

/// 单个品种的一条建议。
class TradeSuggestion {
  final String kind;
  final String label;
  final TradeTrend trend;
  final TradeSignal signal;
  final double score;       // 置信度 0-100
  final List<String> reasons;
  final double profitRate;  // 收益率 %（浮盈/成本）
  final DateTime updatedAt;
  const TradeSuggestion({
    required this.kind,
    required this.label,
    required this.trend,
    required this.signal,
    required this.score,
    required this.reasons,
    required this.profitRate,
    required this.updatedAt,
  });
}

/// 置信度评分 0-100：今日涨跌 30% + 近期窗口 40% + 持仓状态 30%。
double scoreOf({
  required double todayPercent,
  required double windowPercent,
  required double profitRate,
}) {
  final today = 50 + todayPercent * 6;
  final window = 50 + windowPercent * 6;
  final profit = 50 + profitRate * 1.2;
  final s = 0.3 * today + 0.4 * window + 0.3 * profit;
  return s.clamp(0, 100);
}

/// 信号规则：收益率分档 × 趋势（严格按方案口径）。
TradeSignal signalOf({
  required double profitRate,
  required TradeTrend trend,
  required double todayPercent,
}) {
  if (trend == TradeTrend.insufficient) return TradeSignal.insufficient;
  if (profitRate <= -15) return TradeSignal.riskAlert;
  if (profitRate <= -5) {
    return trend == TradeTrend.up ? TradeSignal.buy : TradeSignal.watch;
  }
  if (profitRate <= 5) return TradeSignal.hold;
  if (profitRate <= 20) {
    return trend == TradeTrend.up ? TradeSignal.hold : TradeSignal.reduce;
  }
  // 收益率 > 20%：短期涨幅 ≥10% 才提示止盈，否则持有。
  return todayPercent >= 10 ? TradeSignal.takeProfit : TradeSignal.hold;
}

String _pct(double v) => v.abs().toStringAsFixed(1);

/// 生成 2 条理由文案（第一条讲趋势/行情，第二条讲持仓收益）。
List<String> reasonsFor(TradeSuggestion s) {
  final pct = _pct(s.profitRate);
  final sign = s.profitRate >= 0 ? '+' : '-';
  switch (s.signal) {
    case TradeSignal.riskAlert:
      return [
        '今日及近期走势偏弱，趋势走低',
        '收益率 $sign$pct%，亏损较大，建议重新评估仓位',
      ];
    case TradeSignal.buy:
      return [
        '趋势回升，方向向好',
        '收益率 $sign$pct%，仍低于成本，可分批补仓摊薄',
      ];
    case TradeSignal.takeProfit:
      return [
        '短期涨幅较快，注意高位波动',
        '收益率 $sign$pct%，可分批止盈（卖出 20%-30% 锁定收益）',
      ];
    case TradeSignal.reduce:
      return [
        '近期趋势转弱',
        '收益率 $sign$pct%，可考虑减仓止盈部分',
      ];
    case TradeSignal.watch:
      return [
        '近期趋势走低',
        '收益率 $sign$pct%，谨慎观望，等待反弹确认',
      ];
    case TradeSignal.hold:
      return [
        '趋势平稳或向好，未出现明显破坏信号',
        '收益率 $sign$pct%，继续持有观望',
      ];
    case TradeSignal.insufficient:
      return ['行情数据积累中，打开 App 一段时间后自动生成建议'];
  }
}

/// 防频繁提醒：24h 内信号一致且未突破阈值（价格波动>5% 或 评分变化>20）则沿用上次建议。
TradeSuggestion applyCooling({
  required TradeSuggestion current,
  required TradeSuggestion? last,
  required DateTime now,
  required double priceMovePercent,
}) {
  if (last == null) return current;
  if (now.difference(last.updatedAt) > const Duration(hours: 24)) return current;
  if (priceMovePercent > 5) return current;
  if ((current.score - last.score).abs() > 20) return current;
  if (current.signal != last.signal) return current;
  return last;
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/signal_engine_test.dart`
Expected: All tests passed!

- [ ] **Step 5: 提交**

```bash
cd goldpulse
git add lib/services/signal_engine.dart test/signal_engine_test.dart
git commit -m "feat: SignalEngine 评分/信号/理由/冷却纯函数"
```

---
---

### Task 3: suggestionsProvider 数据组合

**Files:**
- Create: `goldpulse/lib/state/suggestion_provider.dart`
- Test: `goldpulse/test/suggestion_provider_test.dart`

**Interfaces:**
- Consumes:
  - `TradeTrend`/`trendOf`（`trend_analyzer.dart`）
  - `TradeSuggestion`/`TradeSignal`/`scoreOf`/`signalOf`/`reasonsFor`/`applyCooling`（`signal_engine.dart`）
  - `typeSummariesProvider`（`asset_provider.dart`，`FutureProvider<List<TypeAssetSummary>>`，字段：`kind/label/totalCost/floatingProfit/currentPrice/preClose`）
  - `priceDaoProvider`（`price_provider.dart`），`PriceDao.recent(String code, {int limit = 500})` → `List<GoldPrice>`，**time DESC**（新→旧）
  - `SharedPreferences`（存冷却上次建议）
- Produces: `final suggestionsProvider = FutureProvider<List<TradeSuggestion>>((ref) async {...})`。返回按紧急度排序的建议列表（主建议在首位）。无持仓返回空列表。

行为：
- 对每个 `TypeAssetSummary`（`currentPrice != null` 才有建议；否则跳过）：
  1. `code = kind=='au9999' ? 'SGE-Au(T+D)' : kind=='icbc' ? 'ICBC-JCJ' : 'CZB-JCJ'`
  2. `recent = await dao.recent(code, limit: 60)`（DESC）→ `prices = [for (gp in recent.reversed) gp.price]`，再附上 `t.currentPrice!` 作为最新点。若 `prices.length < 5` → 该品种 trend 为 insufficient（trendOf 会返回 insufficient，直接跳过评分用 0）。
  3. `trend = trendOf(prices)`
  4. `todayPercent = (preClose==null||preClose==0) ? 0 : (currentPrice - preClose) / preClose * 100`
  5. `profitRate = totalCost==0 ? 0 : floatingProfit / totalCost * 100`
  6. `windowPercent = trend==insufficient ? 0 : (prices.last - prices.first) / prices.first * 100`
  7. `priceMovePercent = max(todayPercent.abs(), windowPercent.abs())`
  8. `score = scoreOf(...)`；`signal = signalOf(...)`；构造 `current`（`updatedAt: DateTime.now()`）
  9. 冷却：`last` 从 SharedPreferences key `suggestion_last_<kind>` 读 JSON `{signal, score, at}`（`TradeSignal.values.byName` 还原；`at` 为毫秒）。`applied = applyCooling(current: current, last: last, now: now, priceMovePercent: priceMovePercent)`。若 `applied == current`（即本次生效），把 current 写入 prefs。
  10. `reasons = reasonsFor(applied)`；`score` 用 `applied.score`。
  11. 加入结果。
- 结果排序：紧急度 `riskAlert>takeProfit>reduce>buy>watch>hold>insufficient`（用 `TradeSignal.values.index` 即可，枚举顺序已定义）。

- [ ] **Step 1: 写失败测试**

创建 `goldpulse/test/suggestion_provider_test.dart`（widget 级 ProviderScope 测试，注入假 dao / summaries / prefs）：

```dart
// test/suggestion_provider_test.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/state/asset_provider.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/state/suggestion_provider.dart';
import 'package:goldpulse/services/signal_engine.dart';
import 'package:goldpulse/database/price_dao.dart';

/// 假 PriceDao：返回固定 recent 序列（time DESC）。
class _FakePriceDao extends PriceDao {
  final Map<String, List<GoldPrice>> byCode;
  _FakePriceDao(this.byCode);
  @override
  Future<List<GoldPrice>> recent(String code, {int limit = 500}) async =>
      byCode[code] ?? const [];
}

void main() {
  // 冷却存储用 SharedPreferences：widget 测试必须 mock 空初始值。
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 构造 60 个点（升序 880 → 899），recent 需 DESC。
  List<GoldPrice> asc(int n, double start, double step) => [
        for (var i = 0; i < n; i++)
          GoldPrice(code: 'CZB-JCJ', price: start + i * step,
              change: step, percent: step / (start + i * step) * 100,
              preClose: 880, time: 1000 + i)
      ];

  testWidgets('无持仓 → 空列表', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        typeSummariesProvider.overrideWith((ref) async => const []),
        priceDaoProvider.overrideWithValue(_FakePriceDao({})),
      ],
      child: const MaterialApp(home: Scaffold(body: SizedBox())),
    ));
    final list = await tester.context.read(suggestionsProvider.future);
    expect(list, isEmpty);
  });

  testWidgets('持仓且趋势数据充足 → 生成建议（浙商买入）', (tester) async {
    final summaries = [
      const TypeAssetSummary(
        kind: 'accumulation', label: '浙商积存金',
        totalGrams: 50, totalCost: 45000, avgCost: 900,
        currentPrice: 899, preClose: 895,
        floatingProfit: -50, todayProfit: 200, cumulativeProfit: -50,
        holdingCount: 1,
      ),
    ];
    final dao = _FakePriceDao({
      'CZB-JCJ': asc(60, 880, 0.3).reversed.toList(), // DESC
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        typeSummariesProvider.overrideWith((ref) async => summaries),
        priceDaoProvider.overrideWithValue(dao),
      ],
      child: const MaterialApp(home: Scaffold(body: SizedBox())),
    ));
    final list = await tester.context.read(suggestionsProvider.future);
    expect(list, hasLength(1));
    // 趋势向上（窗口 +2%），亏损 -0.11% → hold（-5~5% 档）。
    // 今天 percent = (899-895)/895 ≈ +0.45%。趋势 up，小幅盈亏 → hold。
    expect(list.single.signal, TradeSignal.hold);
  });

  testWidgets('深度亏损 → riskAlert', (tester) async {
    final summaries = [
      const TypeAssetSummary(
        kind: 'accumulation', label: '浙商积存金',
        totalGrams: 50, totalCost: 50000, avgCost: 1000,
        currentPrice: 820, preClose: 830,
        floatingProfit: -9000, todayProfit: -500, cumulativeProfit: -9000,
        holdingCount: 1,
      ),
    ];
    final dao = _FakePriceDao({
      'CZB-JCJ': asc(60, 900, -1.5).reversed.toList(), // 窗口下跌
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        typeSummariesProvider.overrideWith((ref) async => summaries),
        priceDaoProvider.overrideWithValue(dao),
      ],
      child: const MaterialApp(home: Scaffold(body: SizedBox())),
    ));
    final list = await tester.context.read(suggestionsProvider.future);
    expect(list.single.signal, TradeSignal.riskAlert);
  });
}
```

注意：`TradeSignal` 需 import 自 `signal_engine.dart`；`tester.context.read` 需 `WidgetTester`（flutter_test 提供）。测试需要 override `SharedPreferences.setMockInitialValues({})`（在 `setUp` 或测试开头）避免真实 prefs。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/suggestion_provider_test.dart`
Expected: 编译失败（`suggestion_provider.dart` 不存在）。

- [ ] **Step 3: 实现**

创建 `goldpulse/lib/state/suggestion_provider.dart`：

```dart
// lib/state/suggestion_provider.dart
// 智能建议-数据组合：汇总各品种持仓 + DB 行情序列 → 生成建议列表（按紧急度排序，主建议在首位）。
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gold_price.dart';
import '../services/signal_engine.dart';
import '../services/trend_analyzer.dart';
import 'asset_provider.dart';
import 'price_provider.dart';

/// 冷却存储前缀：`suggestion_last_<kind>` → JSON {signal, score, at(毫秒)}。
final suggestionsProvider = FutureProvider<List<TradeSuggestion>>((ref) async {
  final summaries = await ref.watch(typeSummariesProvider.future);
  if (summaries.isEmpty) return const [];
  final dao = ref.watch(priceDaoProvider);
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final result = <TradeSuggestion>[];

  for (final t in summaries) {
    if (t.currentPrice == null) continue; // 无行情 → 不生成建议
    final code = switch (t.kind) {
      'au9999' => 'SGE-Au(T+D)',
      'icbc' => 'ICBC-JCJ',
      _ => 'CZB-JCJ',
    };
    final recent = await dao.recent(code, limit: 60); // DESC
    final prices = <double>[
      for (final gp in recent.reversed) gp.price,
      t.currentPrice!,
    ];

    final trend = trendOf(prices);
    final todayPercent = t.preClose == null || t.preClose! <= 0
        ? 0.0
        : (t.currentPrice! - t.preClose!) / t.preClose! * 100;
    final profitRate =
        t.totalCost <= 0 ? 0.0 : t.floatingProfit / t.totalCost * 100;
    final windowPercent = trend == TradeTrend.insufficient || prices.first <= 0
        ? 0.0
        : (prices.last - prices.first) / prices.first * 100;
    final priceMovePercent =
        math.max(todayPercent.abs(), windowPercent.abs());

    final score = scoreOf(
        todayPercent: todayPercent,
        windowPercent: windowPercent,
        profitRate: profitRate);
    final signal = signalOf(
        profitRate: profitRate, trend: trend, todayPercent: todayPercent);
    final current = TradeSuggestion(
      kind: t.kind, label: t.label, trend: trend, signal: signal,
      score: score, reasons: const [], profitRate: profitRate,
      updatedAt: now,
    );

    // 冷却：读上次建议，applyCooling 决定本次是否沿用。
    final key = 'suggestion_last_${t.kind}';
    TradeSuggestion? last;
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        last = TradeSuggestion(
          kind: t.kind, label: t.label,
          trend: TradeTrend.values.byName(m['trend'] as String),
          signal: TradeSignal.values.byName(m['signal'] as String),
          score: (m['score'] as num).toDouble(),
          reasons: const [],
          profitRate: profitRate,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(m['at'] as int),
        );
      } catch (_) {
        last = null; // 旧数据损坏则忽略
      }
    }
    final applied = applyCooling(
        current: current, last: last, now: now,
        priceMovePercent: priceMovePercent);
    if (identical(applied, current)) {
      await prefs.setString(key, jsonEncode({
        'trend': current.trend.name,
        'signal': current.signal.name,
        'score': current.score,
        'at': current.updatedAt.millisecondsSinceEpoch,
      }));
    }
    result.add(TradeSuggestion(
      kind: applied.kind, label: applied.label,
      trend: applied.trend, signal: applied.signal,
      score: applied.score, reasons: reasonsFor(applied),
      profitRate: applied.profitRate, updatedAt: applied.updatedAt,
    ));
  }

  // 紧急度排序：riskAlert 最高，insufficient 最低（枚举声明顺序即紧急度顺序）。
  result.sort((a, b) => a.signal.index.compareTo(b.signal.index));
  return result;
});
```

- [ ] **Step 4: 测试通过 + 修测试**

运行 Step 1 测试，并在 `main()` 顶部加 `SharedPreferences.setMockInitialValues({});`（若未写），确保通过。

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/suggestion_provider_test.dart`
Expected: All tests passed!

- [ ] **Step 5: 提交**

```bash
cd goldpulse
git add lib/state/suggestion_provider.dart test/suggestion_provider_test.dart
git commit -m "feat: suggestionsProvider 组合持仓+行情生成建议（含冷却）"
```

---
---

### Task 4: TradeSuggestionCard UI + 首页接入

**Files:**
- Create: `goldpulse/lib/widgets/suggestion_card.dart`
- Modify: `goldpulse/lib/pages/home_page.dart`（顶部插入卡片）
- Test: `goldpulse/test/suggestion_card_test.dart`（widget）

**Interfaces:**
- Consumes: `List<TradeSuggestion>`（`signal_engine.dart`）；`AppTheme`；`fmtGrams`/`fmtPrice`/`fmtAmount`（`formatters.dart`）。
- Produces: `class TradeSuggestionCard extends StatelessWidget { const TradeSuggestionCard({super.key, required this.suggestions, this.loading = false}); final List<TradeSuggestion> suggestions; final bool loading; }`

行为：
- `loading == true` → 显示 18×18 金色转圈 + "正在分析行情…"。
- `suggestions.isEmpty` → 显示空态："录入持仓后，结合行情趋势动态生成买卖建议"。
- `suggestions` 非空 → 主建议取 `suggestions.first`（已按紧急度排序）。其余品种（`suggestions.skip(1)`）各渲染一行摘要。
- 主建议渲染：
  - 头部：📊 seal 图标（26×26 圆角金底）+ 标题"智能建议" + 右侧置信胶囊 `置信 <score.round()>`（金色描边）。
  - 主体：品种名（w600）+ 趋势（↗ 红 / ↘ 绿 / → 灰）+ 右侧信号标签 chip。
  - 理由：`suggestions.first.reasons` 每行一条（12px 灰字 + 金色小圆点）。
  - 其余品种摘要：`label + 信号动作词`（如 `工商积存金 → 减仓 30%`）。
  - 底部：`更新于 HH:mm · 仅供参考，非投资建议` + `24h 内不重复提醒`。
- 信号 → 标签映射（严格用这些词）：
  - hold→`持有`、buy→`买入`、takeProfit→`止盈`、reduce→`减仓`、watch→`观望`、riskAlert→`风险提醒`、insufficient→`待积累`
- 信号 → 颜色：buy→`AppTheme.down`（绿，买入偏多）、hold→`AppTheme.gold`、takeProfit/reduce/riskAlert→`AppTheme.up`（红，卖出/风险）、watch/insufficient→`AppTheme.textSecondary`。chip 背景用对应色 alpha 0.16。
- 趋势 → 箭头/颜色：up→`↗` `AppTheme.up`（红涨）、down→`↘` `AppTheme.down`（绿跌）、flat→`→` `AppTheme.textSecondary`、insufficient→`·`。
- 卡片容器：`LinearGradient(colors: [Color(0xFF26354F), AppTheme.cardHighlight])` 渐变、`borderRadius: 18`、`border: Border.all(color: AppTheme.divider)`、内边距 `EdgeInsets.all(14)`。
- 首页接入：`home_page.dart` 在 `ListView` children 的**第一项**（三行情卡 `if (price != null) GoldCard(...)` 之前）插入：
  ```dart
  TradeSuggestionCard(
    suggestions: ref.watch(suggestionsProvider).value ?? const [],
    loading: ref.watch(suggestionsProvider).isLoading,
  ),
  const SizedBox(height: 14),
  ```
  import `../widgets/suggestion_card.dart` 与 `../state/suggestion_provider.dart`。

- [ ] **Step 1: 写失败测试**

创建 `goldpulse/test/suggestion_card_test.dart`：

```dart
// test/suggestion_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/widgets/suggestion_card.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/services/signal_engine.dart';
import 'package:goldpulse/services/trend_analyzer.dart';

void main() {
  Widget wrap(Widget w) => MaterialApp(
      theme: AppTheme.theme(), home: Scaffold(body: Center(child: w)));

  final risk = TradeSuggestion(
      kind: 'accumulation', label: '浙商积存金',
      trend: TradeTrend.down, signal: TradeSignal.riskAlert,
      score: 30, reasons: const ['近期趋势走低', '亏损较大，建议重新评估仓位'],
      profitRate: -16, updatedAt: DateTime(2026, 8, 5, 10, 30));
  final hold = TradeSuggestion(
      kind: 'icbc', label: '工商积存金',
      trend: TradeTrend.up, signal: TradeSignal.hold,
      score: 70, reasons: const ['趋势向好', '收益率为正，继续持有'],
      profitRate: 8, updatedAt: DateTime(2026, 8, 5, 10, 30));

  testWidgets('加载态显示转圈', (tester) async {
    await tester.pumpWidget(wrap(const TradeSuggestionCard(
        suggestions: [], loading: true)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('空态提示录入持仓', (tester) async {
    await tester.pumpWidget(wrap(const TradeSuggestionCard(
        suggestions: [], loading: false)));
    expect(find.textContaining('录入持仓'), findsOneWidget);
  });

  testWidgets('渲染主建议：标题/品种/信号标签/置信度/理由', (tester) async {
    await tester.pumpWidget(wrap(TradeSuggestionCard(
        suggestions: [risk, hold])));
    expect(find.text('智能建议'), findsOneWidget);
    expect(find.text('浙商积存金'), findsOneWidget);
    expect(find.text('风险提醒'), findsOneWidget);
    expect(find.text('置信 30'), findsOneWidget);
    expect(find.text('近期趋势走低'), findsOneWidget);
    expect(find.text('亏损较大，建议重新评估仓位'), findsOneWidget);
    // 免责小字
    expect(find.textContaining('非投资建议'), findsOneWidget);
  });

  testWidgets('多品种：其余品种渲染一行摘要（含动作词）', (tester) async {
    await tester.pumpWidget(wrap(TradeSuggestionCard(
        suggestions: [risk, hold])));
    expect(find.text('工商积存金'), findsOneWidget);
    expect(find.textContaining('持有'), findsWidgets);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/suggestion_card_test.dart`
Expected: 编译失败（`suggestion_card.dart` 不存在）。

- [ ] **Step 3: 实现 UI**

创建 `goldpulse/lib/widgets/suggestion_card.dart`（完整代码）：

```dart
// lib/widgets/suggestion_card.dart
// 首页顶部「智能建议」小卡片：主建议 + 其余品种摘要 + 免责。
// 数据来自 suggestionsProvider（已按紧急度排序，首位为主建议）。
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/services/signal_engine.dart';
import 'package:goldpulse/services/trend_analyzer.dart';

/// 信号 → 展示动作词。
String signalLabel(TradeSignal s) => switch (s) {
      TradeSignal.hold => '持有',
      TradeSignal.buy => '买入',
      TradeSignal.takeProfit => '止盈',
      TradeSignal.reduce => '减仓',
      TradeSignal.watch => '观望',
      TradeSignal.riskAlert => '风险提醒',
      TradeSignal.insufficient => '待积累',
    };

/// 信号 → 主色（买入偏多/持有金/止盈减仓风险红/观望灰）。
Color signalColor(TradeSignal s) => switch (s) {
      TradeSignal.buy => AppTheme.down,
      TradeSignal.hold => AppTheme.gold,
      TradeSignal.takeProfit ||
      TradeSignal.reduce ||
      TradeSignal.riskAlert => AppTheme.up,
      TradeSignal.watch || TradeSignal.insufficient => AppTheme.textSecondary,
    };

/// 趋势 → 箭头与颜色（红涨绿跌）。
(String, Color) _trendArrow(TradeTrend t) => switch (t) {
      TradeTrend.up => ('↗', AppTheme.up),
      TradeTrend.down => ('↘', AppTheme.down),
      TradeTrend.flat => ('→', AppTheme.textSecondary),
      TradeTrend.insufficient => ('·', AppTheme.textSecondary),
    };

class TradeSuggestionCard extends StatelessWidget {
  final List<TradeSuggestion> suggestions;
  final bool loading;
  const TradeSuggestionCard({
    super.key,
    required this.suggestions,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF26354F), AppTheme.cardHighlight]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: loading
          ? const Row(children: [
              SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.gold)),
              SizedBox(width: 12),
              Text('正在分析行情…',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            ])
          : suggestions.isEmpty
              ? _empty()
              : _content(suggestions),
    );
  }

  Widget _empty() {
    return const Row(children: [
      Icon(Icons.balance_outlined, size: 20, color: AppTheme.goldSoft),
      SizedBox(width: 10),
      Expanded(
        child: Text('录入持仓后，结合行情趋势动态生成买卖建议',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
      ),
    ]);
  }

  Widget _content(List<TradeSuggestion> list) {
    final main = list.first;
    final rest = list.skip(1).toList();
    final (arrow, trendColor) = _trendArrow(main.trend);
    final c = signalColor(main.signal);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 头部：图标 + 标题 + 置信度
      Row(children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: AppTheme.gold.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.insights, size: 15, color: AppTheme.gold),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('智能建议',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('置信 ${main.score.round()}',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.gold)),
        ),
      ]),
      const SizedBox(height: 10),
      // 主建议：品种 + 趋势 + 信号 chip
      Row(children: [
        Text(main.label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(arrow, style: TextStyle(fontSize: 14, color: trendColor)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(signalLabel(main.signal),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ),
      ]),
      const SizedBox(height: 8),
      // 理由列表
      for (final r in main.reasons)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Container(
                width: 5, height: 5,
                decoration: const BoxDecoration(
                    color: AppTheme.goldSoft, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(r,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary, height: 1.5)),
            ),
          ]),
        ),
      // 其余品种摘要
      if (rest.isNotEmpty) ...[
        const SizedBox(height: 6),
        for (final s in rest)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: [
              Text(s.label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              const Text('→', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              const SizedBox(width: 6),
              Text(signalLabel(s.signal),
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: signalColor(s.signal))),
            ]),
          ),
      ],
      const SizedBox(height: 8),
      // 底部：免责 + 冷却
      const Row(children: [
        Expanded(
          child: Text('更新于 · 仅供参考，非投资建议',
              style: TextStyle(fontSize: 10, color: AppTheme.offline)),
        ),
        Text('24h 内不重复提醒',
            style: TextStyle(fontSize: 10, color: AppTheme.offline)),
      ]),
    ]);
  }
}
```

- [ ] **Step 4: 接入首页 + 跑测试**

在 `home_page.dart`：
1. import 顶部加 `import '../state/suggestion_provider.dart';` 与 `import '../widgets/suggestion_card.dart';`
2. `ListView` children 第一个元素前插入：

```dart
            TradeSuggestionCard(
              suggestions: ref.watch(suggestionsProvider).value ?? const [],
              loading: ref.watch(suggestionsProvider).isLoading,
            ),
            const SizedBox(height: 14),
```

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/suggestion_card_test.dart`
Expected: All tests passed!

再跑全量测试确认现有不破坏：`flutter test`

- [ ] **Step 5: 提交**

```bash
cd goldpulse
git add lib/widgets/suggestion_card.dart lib/pages/home_page.dart test/suggestion_card_test.dart
git commit -m "feat: 首页顶部智能交易建议卡片（主建议+摘要+免责）"
```
