# 民生积存金接入 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增第四个黄金品种「民生积存金」（京东数据源），接入所有涉及位置：行情轮询、行情页、首页价格卡、资产/持仓/提醒的品种映射、后台提醒、智能建议。

**Architecture:** 民生走京东独立接口 `ms.jr.jd.com/gw/generic/hj/h5/m/latestPrice`（非 `getGoldPrice`）。内部统一约定：`kind='minsheng'`、中文名「民生积存金」、DB 历史库 code=`'MSB-JCJ'`。新增 `minshengPriceProvider` 轮询 + `fetchMinShengPriceWithFallback` 降级链；其余页面通过 kind/provider/code 三处映射接入。民生接口**无当日日线字段**（open/high/low），当日统计卡对民生自动显示 `'--'`（`_dayVal` 对 0 已兜底）。

**Tech Stack:** Flutter 3.44.8 / Dart 3.12.2 / Riverpod 2.x / sqflite / dio。测试用 `flutter test`。

## Global Constraints

- 项目根：`goldpulse/` 子目录是 Flutter 应用。测试命令在 `goldpulse/` 下运行，运行前 `export PATH="$(printf '%s' "$PATH" | tail -n 1)"`。
- **不要**手动跑 `flutter pub get`（依赖已锁定，flutter test 自动处理）。
- 民生统一约定（全局唯一）：kind 字符串 `'minsheng'`、中文名 `民生积存金`、行情 code `'MSB-JCJ'`。
- 民生行情接口：`https://ms.jr.jd.com/gw/generic/hj/h5/m/latestPrice`（无参数，GET）。响应结构 `resultData.datas.{price, yesterdayPrice, upAndDownAmt, upAndDownRate, time, productSku}`。可用 `parseJdGoldPrice` 解析（datas 分支已支持 price/yesterdayPrice）。
- 民生降级链：主源 `latestPrice` → 东方财富 Au9999 参考 → 新浪。与现有 `_fetchWithFallback` 一致，仅主源函数不同。
- 民生无 open/high/low 日线 → `GoldPrice.openPrice/highPrice/lowPrice` 保持 0；当日统计卡 `_dayVal` 自动显示 `'--'`（无需改）。
- 颜色严格用 `AppTheme`；红涨绿跌（up=红/down=绿）。提交信息中文。
- 所有 kind→provider 映射与 kind→label 映射必须覆盖 4 品种：`au9999`/`accumulation`/`icbc`/`minsheng`。
- 所有渲染 HomePage / MarketPage / AssetPage 的 widget 测试，必须额外 override `minshengPriceProvider` 为 `Stream<GoldPrice?>.value(null)`，否则触发真 dio `UnimplementedError`。
- 禁止改动建议卡片与智能建议算法逻辑（仅 code 映射加民生）。

---
---

### Task 1: PriceApi 民生接口 + 降级链 + 测试

**Files:**
- Modify: `goldpulse/lib/services/price_api.dart`
- Test: `goldpulse/test/price_api_test.dart`

**Interfaces:**
- Consumes: 既有 `_fetchWithFallback` 模式、`parseJdGoldPrice`、`_eastmoneyPrice`、`_sinaPrice`、`ApiException`。
- Produces: `Future<GoldPrice?> fetchMinShengPrice()`（主源 latestPrice）；`Future<GoldPrice?> fetchMinShengPriceWithFallback()`（民生→东财→新浪）。

- [ ] **Step 1: 写失败测试**

在 `goldpulse/test/price_api_test.dart` 追加（先读该文件了解既有测试的假 dio 构造方式 `MockAdapter`/`dioAdapter`）：

```dart
  group('民生积存金', () {
    final minShengSample = {
      'resultData': {
        'datas': {
          'upAndDownRate': '+1.23%',
          'productSku': '21001001000001',
          'price': '898.25',
          'yesterdayPrice': '887.30',
          'upAndDownAmt': '+10.95',
          'time': '1785902867000',
        },
        'status': 'SUCCESS',
      },
      'success': true,
      'resultCode': 0,
    };

    test('解析民生响应：price/yesterdayPrice/涨跌幅', () {
      final gp = PriceApi.parseJdGoldPrice(minShengSample, fallbackCode: 'MSB-JCJ');
      expect(gp, isNotNull);
      expect(gp!.price, closeTo(898.25, 0.001));
      expect(gp.preClose, closeTo(887.30, 0.001));
      expect(gp.percent, closeTo(898.25 / 887.30 * 100 - 100, 0.001));
      expect(gp.code, 'MSB-JCJ');
    });

    test('fetchMinShengPrice 请求 latestPrice 且主源成功返回', () async {
      final adapter = /* 该文件既有假 dio 方式 */;
      adapter.response = Response(requestOptions: ..., data: minShengSample);
      final api = PriceApi(dio: Dio()..httpClientAdapter = adapter);
      final gp = await api.fetchMinShengPrice();
      expect(gp, isNotNull);
      expect(gp!.price, closeTo(898.25, 0.001));
    });
  });
```

（Step 1 的具体假 dio 写法以 `price_api_test.dart` 既有测试为模板照抄；若文件用 `MockAdapter` 类则复用。）

- [ ] **Step 2: 运行测试确认失败**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/price_api_test.dart`
Expected: 编译失败（`fetchMinShengPrice` 不存在）。

- [ ] **Step 3: 实现**

在 `goldpulse/lib/services/price_api.dart` 追加：

```dart
  /// 民生积存金主源：ms.jr.jd.com latestPrice（独立于 getGoldPrice，无当日日线字段）。
  static const minShengUrl =
      'https://ms.jr.jd.com/gw/generic/hj/h5/m/latestPrice';

  Future<GoldPrice?> fetchMinShengPrice() async {
    try {
      final res = await dio.get(minShengUrl,
          options: Options(receiveTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8)));
      var data = res.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } on FormatException {
          throw ApiException('响应非合法 JSON');
        }
      }
      if (data is! Map<String, dynamic>) throw ApiException('响应结构非法');
      return parseJdGoldPrice(data, fallbackCode: 'MSB-JCJ', source: '京东民生');
    } on DioException catch (e) {
      throw ApiException('网络请求失败: ${e.message}');
    }
  }

  /// 民生积存金降级链：主源 latestPrice → 东方财富 Au9999 参考 → 新浪。
  Future<GoldPrice?> fetchMinShengPriceWithFallback() async {
    try {
      final gp = await fetchMinShengPrice();
      if (gp != null) {
        _log('民生 主源京东(latestPrice)成功: ${gp.price} 元/g @${gp.time}');
        return gp;
      }
      _log('民生 京东返回空数据，继续降级');
    } on ApiException catch (e) {
      _log('民生 京东失败: ${e.message}');
    }
    try {
      final gp = await _eastmoneyPrice(code: 'MSB-JCJ', source: 'Au9999 参考');
      if (gp != null) {
        _log('民生 备用东方财富(Au9999 参考)成功: ${gp.price} 元/g');
        return gp;
      }
      _log('民生 东方财富返回空数据，继续降级');
    } on DioException catch (e) {
      _log('民生 东方财富失败: ${e.message}');
    }
    try {
      final gp = await _sinaPrice(code: 'MSB-JCJ', source: '新浪');
      if (gp != null) {
        _log('民生 兜底新浪成功: ${gp.price} 元/g');
        return gp;
      }
      _log('民生 新浪返回空数据');
    } on DioException catch (e) {
      _log('民生 新浪失败: ${e.message}');
    }
    _log('民生 全部行情源失败');
    return null;
  }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/price_api_test.dart`
Expected: All tests passed!

- [ ] **Step 5: 提交**

```bash
cd goldpulse
git add lib/services/price_api.dart test/price_api_test.dart
git commit -m "feat: 民生积存金行情接口与降级链（latestPrice→东财→新浪）"
```

---
---

### Task 2: minshengPriceProvider 轮询 + 后台提醒 + 建议 code 映射

**Files:**
- Modify: `goldpulse/lib/state/price_provider.dart`
- Modify: `goldpulse/lib/services/background_alert.dart`
- Modify: `goldpulse/lib/state/suggestion_provider.dart`
- Test: `goldpulse/test/price_provider_test.dart`（若存在）或追加至 `widget_smoke_test.dart`

**Interfaces:**
- Consumes: `fetchMinShengPriceWithFallback`（Task 1）；既有 `accumulationPriceProvider` 模式。
- Produces: `final minshengPriceProvider = StreamProvider<GoldPrice?>`（DB code `'MSB-JCJ'`，前台告警判定 kind='minsheng'）。

- [ ] **Step 1: 写失败测试**

在 `goldpulse/test/widget_smoke_test.dart` 追加一个测试，或对 `price_provider.dart` 做 provider 级测试：断言 `minshengPriceProvider` 存在且首值来自 DB（注入假 dao 可略——先做最小测试：用 override 注入 `Stream<GoldPrice?>.value(...)`，断言 `ref.read(minshengPriceProvider.future)` 能取到值）。

```dart
  testWidgets('minshengPriceProvider 可被注入并取到值', (tester) async {
    final stream = Stream<GoldPrice?>.value(GoldPrice(
        code: 'MSB-JCJ', price: 898.25, change: 10.95,
        percent: 1.23, preClose: 887.30, time: 1));
    final container = ProviderContainer(overrides: [
      minshengPriceProvider.overrideWith((ref) => stream),
      priceDaoProvider.overrideWithValue(_FakePriceDao({})),
    ]);
    addTearDown(container.dispose);
    final gp = await container.read(minshengPriceProvider.future);
    expect(gp!.price, closeTo(898.25, 0.001));
    expect(gp.code, 'MSB-JCJ');
  });
```

（若 `widget_smoke_test.dart` 无 `_FakePriceDao`，用该文件既有 `overrideWith` 模式构造；`minshengPriceProvider` 依赖 `priceDaoProvider` 需注入假 dao，或用 overrideWith 直接给流。）

- [ ] **Step 2: 运行测试确认失败**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/widget_smoke_test.dart`
Expected: 编译失败（`minshengPriceProvider` 不存在）。

- [ ] **Step 3: 实现**

**`lib/state/price_provider.dart`** 在 `icbcPriceProvider` 之后追加（复制 icbc 模式，逐字替换 kind/code/tag/日志前缀）：

```dart
/// 民生积存金行情轮询（主源 ms.jr.jd.com latestPrice，DB code='MSB-JCJ'）。
/// 模式与 [icbcPriceProvider] 完全一致：按设定间隔持续轮询；失败降级；无数据 30s 快速重试。
final minshengPriceProvider = StreamProvider<GoldPrice?>((ref) async* {
  final api = ref.watch(priceApiProvider);
  final dao = ref.watch(priceDaoProvider);
  final interval = ref.watch(refreshIntervalProvider).valueOrNull ?? const Duration(minutes: 2);
  final nextRefresh = ref.watch(nextRefreshProvider.notifier);
  final holdingDao = ref.watch(holdingDaoProvider);
  final alertDao = ref.watch(alertDaoProvider);
  final notifications = ref.watch(notificationsPluginProvider);
  GoldPrice? last = await dao.latest('MSB-JCJ');
  debugPrint('[金脉行情] 民生积存金 轮询启动，DB缓存: ${last?.price ?? "无"} @ ${last?.time ?? "-"}');
  yield last;
  while (true) {
    try {
      final fresh = await api.fetchMinShengPriceWithFallback();
      if (fresh != null) {
        debugPrint('[金脉行情] 民生积存金 入库: ${fresh.source} ${fresh.price} @${fresh.time}');
        await dao.insert(fresh);
        last = fresh;
        try {
          var assetValue = 0.0;
          var totalCost = 0.0;
          for (final h in await holdingDao.list()) {
            if (h.kind != 'minsheng') continue;
            assetValue += fresh.price * h.amount;
            totalCost += h.totalCost;
          }
          await runAlertChecks(
              dao: alertDao,
              plugin: notifications,
              price: fresh.price,
              assetValue: assetValue,
              totalCost: totalCost,
              kind: 'minsheng');
        } catch (_) {
        }
      }
    } catch (_) {
    }
    yield last;
    final delay = last == null ? const Duration(seconds: 30) : interval;
    debugPrint('[金脉行情] 民生积存金 下次调度 ${delay.inSeconds}s'
        ' (${last == null ? "快速重试" : "正常间隔"})');
    nextRefresh.set(DateTime.now().add(delay), delay, retrying: last == null);
    await Future.delayed(delay);
  }
});
```

**`lib/services/background_alert.dart`**：kindCodes 加 `'minsheng': 'MSB-JCJ'`，拉价时民生走独立函数：

```dart
    const kindCodes = {
      'au9999': 'SGE-Au(T+D)',
      'accumulation': 'CZB-JCJ',
      'icbc': 'ICBC-JCJ',
      'minsheng': 'MSB-JCJ',
    };
    ...
    for (final entry in kindCodes.entries) {
      final kind = entry.key;
      // 民生走独立 latestPrice 接口，其余走统一 getGoldPrice。
      final price = kind == 'minsheng'
          ? await api.fetchMinShengPriceWithFallback()
          : await api.fetchGoldPriceWithFallback(entry.value);
      ...
```

**`lib/state/suggestion_provider.dart`**：kind→code 映射加 `'minsheng' => 'MSB-JCJ'`：

```dart
    final code = switch (t.kind) {
      'au9999' => 'SGE-Au(T+D)',
      'icbc' => 'ICBC-JCJ',
      'minsheng' => 'MSB-JCJ',
      _ => 'CZB-JCJ',
    };
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/widget_smoke_test.dart`
Expected: All tests passed!

- [ ] **Step 5: 提交**

```bash
cd goldpulse
git add lib/state/price_provider.dart lib/services/background_alert.dart lib/state/suggestion_provider.dart test/widget_smoke_test.dart
git commit -m "feat: 民生积存金行情轮询 + 后台提醒 + 建议 code 映射"
```

---
---

### Task 3: 资产/持仓/提醒层 kind 映射（4 品种全覆盖）

**Files:**
- Modify: `goldpulse/lib/models/holding.dart`（注释）
- Modify: `goldpulse/lib/models/alert.dart`（注释）
- Modify: `goldpulse/lib/state/asset_provider.dart`
- Modify: `goldpulse/lib/widgets/holding_list_tile.dart`
- Modify: `goldpulse/lib/pages/holding_detail_page.dart`
- Modify: `goldpulse/lib/services/alert_service.dart`
- Modify: `goldpulse/lib/pages/alert_page.dart`
- Modify: `goldpulse/lib/pages/asset_page.dart`
- Test: 更新 `goldpulse/test/widget_smoke_test.dart` 资产相关断言（如需）

**Interfaces:**
- Consumes: `minshengPriceProvider`（Task 2）。
- Produces: 各 kind→provider / kind→label 映射覆盖 4 品种。

- [ ] **Step 1: 写失败测试（若适用）**

`widget_smoke_test.dart` 的「首页收益区」与「资产页汇总卡」测试目前只构造 2 品种 summaries；追加一个含 `kind: 'minsheng'` 的 TypeAssetSummary 断言 label「民生积存金」出现（沿用既有 override 模式）。若既有测试不依赖品种枚举，此步可为最小。

- [ ] **Step 2: 实现（逐文件，改完一起跑测试）**

1. **`models/holding.dart:5`**：注释改 `// 'au9999' | 'accumulation' | 'icbc' | 'minsheng'`
2. **`models/alert.dart:5`**：注释改 `// 目标品种 'au9999' | 'accumulation' | 'icbc' | 'minsheng'`
3. **`state/asset_provider.dart`**：
   - 第 66 行注释：`'minsheng'(民生)`
   - `_kindLabel` 加 `'minsheng' => '民生积存金'`
   - `const order = ['accumulation', 'icbc', 'minsheng', 'au9999'];`
   - price 选择：`final price = kind == 'icbc' ? ... : kind == 'accumulation' ? ... : kind == 'minsheng' ? ref.watch(minshengPriceProvider).valueOrNull : ref.watch(priceProvider).valueOrNull;`
4. **`widgets/holding_list_tile.dart`**：第 27-29 行与 196-198 行的 provider 选择加 `holding.kind == 'minsheng' ? minshengPriceProvider : ...`（注释同步「民生积存金 → minsheng」）
5. **`pages/holding_detail_page.dart`**：`_kindPriceProvider` 加 `kind == 'minsheng' ? minshengPriceProvider`；`_kindLabel` 加 `'minsheng' => '民生积存金'`
6. **`services/alert_service.dart`**：`kindLabel` 加 `'minsheng' => '民生积存金'`
7. **`pages/alert_page.dart`**：`_kindLabels` 加 `'minsheng': '民生积存金'`
8. **`pages/asset_page.dart`**：录入持仓下拉（第 269-270 行）加 `DropdownMenuItem(value: 'minsheng', child: Text('民生积存金'))`

- [ ] **Step 3: 运行测试确认通过**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test`
Expected: All tests passed!（若既有测试因 3→4 品种断言失败，调整断言但**不得弱化**）

- [ ] **Step 4: 提交**

```bash
cd goldpulse
git add -A
git commit -m "feat: 民生积存金接入资产/持仓/提醒/录入（4品种全覆盖）"
```

---
---

### Task 4: 行情页 GoldType.minsheng

**Files:**
- Modify: `goldpulse/lib/pages/market_page.dart`
- Test: `goldpulse/test/widget_smoke_test.dart`（行情页相关 override）

**Interfaces:**
- Consumes: `minshengPriceProvider`。
- Produces: `GoldType.minsheng('民生积存金', 'MSB-JCJ', '民生积存金')`；`goldPriceProviderOf` 覆盖 4 类型；`_refresh`/`_load` 覆盖民生。

- [ ] **Step 1: 修改枚举与映射**

1. 枚举加成员：`minsheng('民生积存金', 'MSB-JCJ', '民生积存金'),`
2. `goldPriceProviderOf` 加 `GoldType.minsheng => minshengPriceProvider,`
3. `_refresh()`（第 119-124 行）加 `ref.invalidate(minshengPriceProvider);`
4. 第 164-172 行的 `ref.listen` 行情分支加 `if (_type != GoldType.minsheng) return;` 对应分支（读该段确认结构后照抄 icbc 分支模式）。

（当日统计：民生 open/high/low=0 → `_dayVal` 自动显示 '--'，无需改。区间统计/折线：`_load` 已用 `_type.code` 读 DB recentSince，民生 code `'MSB-JCJ'` 自动生效，无需改。）

- [ ] **Step 2: 更新测试 override**

`widget_smoke_test.dart` 中所有 `MarketPage` 测试的 `ProviderScope` overrides 追加 `minshengPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null))`。

- [ ] **Step 3: 运行测试**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/widget_smoke_test.dart`
Expected: All tests passed!

- [ ] **Step 4: 提交**

```bash
cd goldpulse
git add lib/pages/market_page.dart test/widget_smoke_test.dart
git commit -m "feat: 行情页新增民生积存金类型（tab/曲线/当日统计自动适配）"
```

---
---

### Task 5: 首页民生价格卡 + 全局刷新

**Files:**
- Modify: `goldpulse/lib/pages/home_page.dart`
- Test: `goldpulse/test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `minshengPriceProvider`。
- Produces: 首页第四个 GoldCard（民生积存金），位于工商卡之后；`refreshAllQuotes` 覆盖 4 流。

- [ ] **Step 1: 实现**

1. `home_page.dart` 顶部：`final msPrice = ref.watch(minshengPriceProvider).value;`（工商卡之后）
2. 第 96 行工商 GoldCard 之后、`SizedBox(height: 14)` 处插入：

```dart
            if (msPrice != null)
              GoldCard(
                code: '民生积存金',
                price: msPrice.price,
                change: msPrice.change,
                percent: msPrice.percent,
                time: msPrice.time,
                source: msPrice.source,
                statusLabel: phaseLabel,
                statusHint: resumeHint,
                isTrading: trading,
              )
            else
              _loadingCard(context, onRetry: () => refreshAllQuotes(ref)),
            const SizedBox(height: 14),
```

3. `refreshAllQuotes`（第 18-27 行）：`ref.invalidate(minshengPriceProvider);` 加入 invalidate 列表，`Future.wait` 加入 `ref.refresh(minshengPriceProvider.future)`。

- [ ] **Step 2: 更新测试 override**

`widget_smoke_test.dart` 所有 `HomePage` 测试的 overrides 追加 `minshengPriceProvider.overrideWith((ref) => Stream<GoldPrice?>.value(null))`。

- [ ] **Step 3: 运行测试**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test`
Expected: All tests passed!

- [ ] **Step 4: 提交**

```bash
cd goldpulse
git add lib/pages/home_page.dart test/widget_smoke_test.dart
git commit -m "feat: 首页新增民生积存金价格卡 + 全局刷新覆盖4流"
```

---
---

### Task 6: 全量验证 + 装机 + 收尾

- [ ] **Step 1: 全量测试 + analyze**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter analyze && flutter test`
Expected: No issues found! + All tests passed!

- [ ] **Step 2: 构建 + 装机验证**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" GOLDPULSE_KEY_PASS='GoldPulse@2026Key' && flutter build apk --release`
然后 `adb install -r build/app/outputs/flutter-apk/app-release.apk`，启动 app，`adb logcat -d | grep '金脉行情'` 确认「民生积存金 主源京东(latestPrice)成功」日志出现。

- [ ] **Step 3: 提交推送**

```bash
git push origin main
```
