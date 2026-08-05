# 常驻通知栏 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android 通知中心常驻一条通知，持续显示指定积存金的成本变化与收益。用户可在设置页手动开关、选品种、选最多 4 个展示指标、设刷新频率。

**Architecture:** `flutter_foreground_task` 前台服务 + onGoing 持续通知。`TaskHandler` 运行在独立后台 isolate（dio 纯 Dart 网络可用），周期回调**自己拉行情** + 用主 isolate 传入的**持仓快照**（克重/成本/boughtCost/卖出净得）计算 8 个指标 → `updateService` 更新通知。主 isolate 负责服务启停、配置读写、持仓快照同步。指标口径与资产页（`Calculator`/`TypeAssetSummary`）完全一致。

**Tech Stack:** Flutter 3.44.8 / Dart 3.12.2 / flutter_foreground_task 10.0.0 / Riverpod / dio / shared_preferences / sqflite（主 isolate）。测试 `flutter test`。

## Global Constraints

- 项目根：`goldpulse/` 子目录是 Flutter 应用。测试在 `goldpulse/` 下运行，运行前 `export PATH="$(printf '%s' "$PATH" | tail -n 1)"`。**不要**手动 `flutter pub get`（依赖已锁定，flutter test/analyze 自动处理；新增依赖由 Task 1 显式添加并 commit pubspec）。
- 品种 kind 固定 4 值：`'au9999'`/`'accumulation'`/`'icbc'`/`'minsheng'`；中文名复用 `asset_provider._kindLabel`（不重复定义）。
- 8 个指标 id（常量）：`price`/`change`/`changePct`/`avgCost`/`floatingProfit`/`profitRate`/`todayProfit`/`cumulativeProfit`。其中 `price`/`change`/`changePct` 固定显示在通知第一行（不计入 4 指标选择），`avgCost`/`floatingProfit`/`profitRate`/`todayProfit` 为用户可选 4 指标。
- SharedPreferences key：`notificationBarEnabled`(bool,默认false)、`notificationBarKind`(string,默认'accumulation')、`notificationBarIntervalSeconds`(int,默认10)、`notificationBarMetrics`(List<String>,默认['avgCost','floatingProfit','profitRate','todayProfit'])。**8 选 4 限制**：用户选择列表长度恒 ≤4。
- 颜色红涨绿跌（up=红/down=绿），`AppTheme` 常量。提交信息中文。
- **TaskHandler 后台 isolate 不得使用 sqflite**（无原生通道）；行情用 dio（纯 Dart），持仓用主 isolate 传入的 JSON 快照。
- 指标计算纯函数放 `lib/services/notification_metrics.dart`，可单测；计算逻辑与 `Calculator`/`asset_provider` 口径一致。
- 服务频率变化或品种变化需**重启服务**（stopService + startService）使新配置生效。

---
---

### Task 1: 添加 flutter_foreground_task 依赖 + Android 配置 + 构建验证

**Files:**
- Modify: `goldpulse/pubspec.yaml`（dependencies 加 `flutter_foreground_task: ^10.0.0`）
- Modify: `goldpulse/pubspec.lock`（flutter pub get 生成）
- Modify: `goldpulse/android/app/src/main/AndroidManifest.xml`
- Test: 无（构建验证替代）

**Interfaces:**
- Consumes: 无。
- Produces: `flutter_foreground_task` 依赖可用；Android manifest 含前台服务声明。后续 Task 直接 import。

- [ ] **Step 1: 添加依赖**

在 `goldpulse/pubspec.yaml` 的 `dependencies:` 段（`workmanager` 附近）加：

```yaml
  flutter_foreground_task: ^10.0.0
```

- [ ] **Step 2: 更新 lock 并跑构建验证（KGP 兼容性检查）**

Run:
```bash
cd /d/GitHub/GoldPulse/goldpulse
export PATH="$(printf '%s' "$PATH" | tail -n 1)"
flutter pub get
export GOLDPULSE_KEY_PASS='GoldPulse@2026Key'
flutter build apk --release
```
Expected: BUILD SUCCESSFUL。
- 若构建失败且错误为 `compileReleaseJavaWithJavac`/`WorkmanagerPlugin 找不到` 同款 KGP 问题：说明 flutter_foreground_task 10.0.0 也应用 KGP，与 Flutter 3.44.8 内置 Kotlin 不兼容 → 降级到低版本（逐次试 `flutter_foreground_task: 8.x` 直到构建通过），并在 plan 记录最终版本。**这是本 Task 的核心目标：确认依赖可编译。**

- [ ] **Step 3: AndroidManifest 声明前台服务**

`goldpulse/android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 内、现有 `<uses-permission android:name="android.permission.INTERNET"/>` 旁追加：

```xml
    <!-- 常驻通知栏：前台服务 -->
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"/>
```

在 `<application>` 内（`<activity>` 之前）追加 service 声明（Android 14+ 需 `foregroundServiceType`）：

```xml
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="specialUse"
            android:exported="false" />
```

（若插件 manifest 已自动合并该 service，可省略；构建不报冲突即可。）

- [ ] **Step 4: 提交**

```bash
git add pubspec.yaml pubspec.lock android/app/src/main/AndroidManifest.xml
git commit -m "feat: 引入 flutter_foreground_task 前台服务依赖 + Android 配置"
```

---
---

### Task 2: 通知指标纯函数 + 持仓快照

**Files:**
- Create: `goldpulse/lib/services/notification_metrics.dart`
- Test: `goldpulse/test/notification_metrics_test.dart`

**Interfaces:**
- Consumes: `Calculator`（`goldpulse/lib/services/calculator.dart`，`floatingProfit`/`todayProfit` 签名）。
- Produces:
  - `class PositionSnapshot { final String kind; final double grams; final double totalCost; final double boughtCost; final double soldNet; }`（const 构造）
  - `const metricIds = ['price','change','changePct','avgCost','floatingProfit','profitRate','todayProfit','cumulativeProfit'];`
  - `const metricLabels = {'price':'现价','change':'涨跌额','changePct':'涨跌幅','avgCost':'均价(成本)','floatingProfit':'持仓收益','profitRate':'收益率','todayProfit':'今日盈亏','cumulativeProfit':'累计收益'};`
  - `Map<String, String> computeNotificationMetrics({required double price, required double preClose, required PositionSnapshot pos})`：返回 **8 个指标 id → 展示文本**（金额/百分号格式化，无数据/除零 → `'--'`）。

计算口径（严格）：
- `avgCost = grams<=0 ? null : totalCost/grams`
- `floatingProfit = price*grams - totalCost`（复用 `Calculator.floatingProfit`）
- `profitRate = totalCost<=0 ? null : floatingProfit/totalCost*100`
- `todayProfit = (price - preClose) * grams`（复用 `Calculator.todayProfit`）
- `cumulativeProfit = soldNet + price*grams - boughtCost`
- 文本格式：金额/价格用 `fmtPrice`（2 位小数），百分比 `toStringAsFixed(2)+'%'`，正负带 `+`/`-` 符号（如 `+185.00`、`-0.41%`）。

- [ ] **Step 1: 写失败测试**

创建 `goldpulse/test/notification_metrics_test.dart`：

```dart
// test/notification_metrics_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/notification_metrics.dart';

void main() {
  group('computeNotificationMetrics', () {
    const pos = PositionSnapshot(
        kind: 'accumulation', grams: 50, totalCost: 44800,
        boughtCost: 44800, soldNet: 0);

    test('8 个指标齐全且口径正确', () {
      final m = computeNotificationMetrics(price: 900, preClose: 895, pos: pos);
      expect(m, hasLength(8));
      expect(m['price'], '900.00');
      expect(m['avgCost'], '896.00'); // 44800/50
      expect(m['floatingProfit'], '+200.00'); // 900*50-44800
      expect(m['profitRate'], '+0.45%'); // 200/44800*100
      expect(m['todayProfit'], '+250.00'); // (900-895)*50
      expect(m['cumulativeProfit'], '+200.00'); // 0+900*50-44800
    });

    test('亏损为负号', () {
      final m = computeNotificationMetrics(price: 850, preClose: 855, pos: pos);
      expect(m['floatingProfit'], '-2300.00');
      expect(m['profitRate'], startsWith('-'));
      expect(m['todayProfit'], '-250.00');
    });

    test('克重为 0 → 均价/收益显示 --', () {
      const empty = PositionSnapshot(
          kind: 'accumulation', grams: 0, totalCost: 0, boughtCost: 0, soldNet: 0);
      final m = computeNotificationMetrics(price: 900, preClose: 895, pos: empty);
      expect(m['avgCost'], '--');
      expect(m['floatingProfit'], '--');
      expect(m['profitRate'], '--');
    });

    test('指标 id 与 label 映射完整', () {
      expect(metricIds, hasLength(8));
      for (final id in metricIds) {
        expect(metricLabels[id], isNotNull, reason: '指标 $id 缺中文名');
      }
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/notification_metrics_test.dart`
Expected: 编译失败（文件不存在）。

- [ ] **Step 3: 实现**

创建 `goldpulse/lib/services/notification_metrics.dart`：

```dart
// lib/services/notification_metrics.dart
// 常驻通知栏：8 个展示指标的纯函数计算（口径与资产页一致）+ 持仓快照模型。
// 纯 Dart、无 Flutter 依赖，供主 isolate 与后台 TaskHandler 复用。
import '../utils/formatters.dart' show fmtPrice;
import 'calculator.dart';

/// 持仓快照（后台 isolate 无法访问 sqflite，由主 isolate 在服务启动/持仓变更时传入）。
class PositionSnapshot {
  final String kind;
  final double grams;      // 总克重
  final double totalCost;  // 剩余总成本
  final double boughtCost; // 累计投入
  final double soldNet;    // 卖出净得合计
  const PositionSnapshot({
    required this.kind,
    required this.grams,
    required this.totalCost,
    required this.boughtCost,
    required this.soldNet,
  });

  Map<String, Object?> toJson() => {
        'kind': kind, 'grams': grams, 'totalCost': totalCost,
        'boughtCost': boughtCost, 'soldNet': soldNet,
      };
  factory PositionSnapshot.fromJson(Map<String, dynamic> m) => PositionSnapshot(
        kind: m['kind'] as String,
        grams: (m['grams'] as num).toDouble(),
        totalCost: (m['totalCost'] as num).toDouble(),
        boughtCost: (m['boughtCost'] as num).toDouble(),
        soldNet: (m['soldNet'] as num).toDouble(),
      );
}

/// 8 个指标 id（price/change/changePct 固定显示，其余为可选 4 指标）。
const metricIds = [
  'price', 'change', 'changePct', 'avgCost',
  'floatingProfit', 'profitRate', 'todayProfit', 'cumulativeProfit',
];

const metricLabels = {
  'price': '现价', 'change': '涨跌额', 'changePct': '涨跌幅',
  'avgCost': '均价(成本)', 'floatingProfit': '持仓收益',
  'profitRate': '收益率', 'todayProfit': '今日盈亏', 'cumulativeProfit': '累计收益',
};

String _money(double v) =>
    (v >= 0 ? '+' : '') + fmtPrice(v); // 金额带符号
String _pct(double v) =>
    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';

/// 计算 8 个指标 → 展示文本。无数据/除零 → '--'。
Map<String, String> computeNotificationMetrics({
  required double price,
  required double preClose,
  required PositionSnapshot pos,
}) {
  final avgCost = pos.grams <= 0 ? null : pos.totalCost / pos.grams;
  final floatingProfit = Calculator.floatingProfit(price, pos.grams, pos.totalCost);
  final profitRate = pos.totalCost <= 0 ? null : floatingProfit / pos.totalCost * 100;
  final todayProfit = Calculator.todayProfit(price, preClose, pos.grams);
  final cumulativeProfit = pos.soldNet + price * pos.grams - pos.boughtCost;
  return {
    'price': fmtPrice(price),
    'change': _money(price - preClose),
    'changePct': _pct((price - preClose) / (preClose <= 0 ? 1 : preClose) * 100),
    'avgCost': avgCost == null ? '--' : fmtPrice(avgCost),
    'floatingProfit': pos.grams <= 0 ? '--' : _money(floatingProfit),
    'profitRate': profitRate == null ? '--' : _pct(profitRate),
    'todayProfit': pos.grams <= 0 ? '--' : _money(todayProfit),
    'cumulativeProfit': _money(cumulativeProfit),
  };
}
```

注意：`Calculator.floatingProfit`/`todayProfit` 的实际签名以 `goldpulse/lib/services/calculator.dart` 为准（读文件确认参数名，可能是 `floatingProfit(currentPrice, amount, totalCost)`）。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/notification_metrics_test.dart`
Expected: All tests passed!

- [ ] **Step 5: 提交**

```bash
git add lib/services/notification_metrics.dart test/notification_metrics_test.dart
git commit -m "feat: 常驻通知 8 指标纯函数与持仓快照（口径与资产页一致）"
```

---
---

### Task 3: 前台服务（启动/停止/后台更新通知）

**Files:**
- Create: `goldpulse/lib/services/persistent_notification_service.dart`
- Test: `goldpulse/test/persistent_notification_service_test.dart`

**Interfaces:**
- Consumes: `computeNotificationMetrics`/`PositionSnapshot`（Task 2）；`PriceApi` + `fetchAccumulationPriceWithFallback` 等（`price_api.dart`）；`metricLabels`。
- Produces:
  - `Future<void> startPersistentNotification({required String kind, required int intervalSeconds})`
  - `Future<void> syncPositionSnapshot(PositionSnapshot pos)`（主 isolate → TaskHandler）
  - `Future<void> stopPersistentNotification()`
  - `@pragma('vm:entry-point') void persistentNotificationCallback()`（顶层，setTaskHandler）
  - `String buildNotificationText({required Map<String,String> metrics, required List<String> selectedMetrics})`：拼通知内容（第一行固定 现价+涨跌，下方自选指标，纯函数可单测）。

行为：
- `startPersistentNotification`：`FlutterForegroundTask.init(...)`（channel `persistent_notification`，eventAction `repeat(intervalSeconds*1000)`）→ `FlutterForegroundTask.startService(serviceId: 2001, notificationTitle: '金脉 · 浙商积存金', notificationText: '加载中…', callback: persistentNotificationCallback)`。
- `persistentNotificationCallback` → `FlutterForegroundTask.setTaskHandler(_PersistentTaskHandler())`。
- `_PersistentTaskHandler extends TaskHandler`：
  - `onStart`：注册 receiveData 回调缓存 `PositionSnapshot`。
  - `onRepeatEvent`：读缓存快照 + 配置（kind/metrics 通过 `sendDataToTask` 传入或在回调里从 SharedPreferences 读——**后台 isolate 无法用 sqflite，但 SharedPreferences 是原生通道也不可用**。故 kind/metrics/快照全部经 `sendDataToTask` 传入缓存）。`unawaited(_refresh())`。
  - `_refresh()`：用缓存的 kind 调对应 `PriceApi.fetch*WithFallback()` 拉行情 → `computeNotificationMetrics` → 取自选指标 → `buildNotificationText` → `FlutterForegroundTask.updateService(...)`。
- `stopPersistentNotification`：`FlutterForegroundTask.stopService()`。
- 品种→行情 fetch 映射：`kind=='minsheng' ? api.fetchMinShengPriceWithFallback() : api.fetchGoldPriceWithFallback(<code>)`（code 映射复用 `suggestion_provider` 的 switch）。

- [ ] **Step 1: 写失败测试**

创建 `goldpulse/test/persistent_notification_service_test.dart`：

```dart
// test/persistent_notification_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/notification_metrics.dart';
import 'package:goldpulse/services/persistent_notification_service.dart';

void main() {
  group('buildNotificationText', () {
    const pos = PositionSnapshot(
        kind: 'accumulation', grams: 50, totalCost: 44800,
        boughtCost: 44800, soldNet: 0);
    final metrics = computeNotificationMetrics(price: 900, preClose: 895, pos: pos);

    test('第一行固定现价+涨跌，下方自选指标', () {
      final t = buildNotificationText(
          metrics: metrics,
          selectedMetrics: ['avgCost', 'floatingProfit', 'profitRate', 'todayProfit']);
      expect(t, contains('900.00'));       // 现价固定行
      expect(t, contains('浙商积存金'));     // 品种名
      expect(t, contains('均价(成本)'));     // 自选指标
      expect(t, contains('持仓收益'));
      expect(t, contains('收益率'));
      expect(t, contains('今日盈亏'));
      expect(t, contains('896.00'));       // 均价值
      expect(t, contains('+200.00'));      // 持仓收益值
      expect(t, contains('+0.45%'));       // 收益率值
    });

    test('自定义 4 指标组合', () {
      final t = buildNotificationText(
          metrics: metrics,
          selectedMetrics: ['change', 'changePct', 'cumulativeProfit', 'avgCost']);
      expect(t, contains('涨跌额'));
      expect(t, contains('涨跌幅'));
      expect(t, contains('累计收益'));
      expect(t, contains('均价(成本)'));
      expect(t, contains('持仓收益'), isNot(isTrue)); // 未选则不显示
    });
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/persistent_notification_service_test.dart`
Expected: 编译失败（文件不存在）。

- [ ] **Step 3: 实现**

创建 `goldpulse/lib/services/persistent_notification_service.dart`（完整代码见下，`_PersistentTaskHandler` 按 flutter_foreground_task 10.x API）：

```dart
// lib/services/persistent_notification_service.dart
// 常驻通知栏：前台服务启停 + 后台 TaskHandler 周期拉行情并更新通知。
// TaskHandler 在独立后台 isolate：用 dio 拉行情（纯 Dart），持仓快照/配置经 sendDataToTask 传入缓存。
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'notification_metrics.dart';
import 'price_api.dart';

/// 服务端到 TaskHandler 的数据契约：JSON map。
class _TaskPayload {
  String kind;
  List<String> selectedMetrics;
  PositionSnapshot? snapshot;
}

/// 主 isolate：启动前台服务（含通知栏初始化 + 周期回调）。
Future<void> startPersistentNotification({
  required String kind,
  required int intervalSeconds,
}) async {
  await FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'persistent_notification',
      channelName: '常驻通知栏',
      channelDescription: '实时显示积存金行情与收益',
      channelImportance: NotificationChannelImportance.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(intervalSeconds * 1000),
    ),
  );
  await FlutterForegroundTask.startService(
    serviceId: 2001,
    notificationTitle: '金脉 · 行情与收益',
    notificationText: '正在启动…',
    callback: persistentNotificationCallback,
  );
  await _sendPayload(_TaskPayload()
    ..kind = kind
    ..selectedMetrics = const [
      'avgCost', 'floatingProfit', 'profitRate', 'todayProfit',
    ]);
}

/// 主 isolate → TaskHandler：同步持仓快照与配置。
Future<void> syncPersistentNotificationData({
  required String kind,
  required List<String> selectedMetrics,
  required PositionSnapshot? snapshot,
}) async {
  await _sendPayload(_TaskPayload()
    ..kind = kind
    ..selectedMetrics = selectedMetrics
    ..snapshot = snapshot);
}

Future<void> _sendPayload(_TaskPayload p) async {
  await FlutterForegroundTask.sendDataToTask({
    'kind': p.kind,
    'selectedMetrics': p.selectedMetrics,
    'snapshot': p.snapshot?.toJson(),
  });
}

/// 主 isolate：停止前台服务。
Future<void> stopPersistentNotification() async {
  await FlutterForegroundTask.stopService();
}

/// 后台 isolate 入口。
@pragma('vm:entry-point')
void persistentNotificationCallback() {
  FlutterForegroundTask.setTaskHandler(_PersistentTaskHandler());
}

class _PersistentTaskHandler extends TaskHandler {
  _TaskPayload _payload = _TaskPayload()
    ..kind = 'accumulation'
    ..selectedMetrics = const [
      'avgCost', 'floatingProfit', 'profitRate', 'todayProfit',
    ];

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 接收主 isolate 发来的配置与持仓快照。
    FlutterForegroundTask.receiveDataFromTask((data) async {
      final m = (data as Map).cast<String, dynamic>();
      _payload.kind = m['kind'] as String? ?? _payload.kind;
      _payload.selectedMetrics =
          (m['selectedMetrics'] as List?)?.cast<String>() ?? _payload.selectedMetrics;
      final snap = m['snapshot'];
      _payload.snapshot = snap == null
          ? null
          : PositionSnapshot.fromJson((snap as Map).cast<String, dynamic>());
    });
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final snap = _payload.snapshot;
      if (snap == null) return; // 持仓快照未就绪，不更新
      final api = PriceApi(dio: Dio(BaseOptions(
          headers: {'User-Agent': 'goldpulse/1.0'},
          receiveTimeout: const Duration(seconds: 8))));
      final fresh = _payload.kind == 'minsheng'
          ? await api.fetchMinShengPriceWithFallback()
          : await api.fetchGoldPriceWithFallback(_kindCode(_payload.kind));
      if (fresh == null) return;
      final metrics = computeNotificationMetrics(
          price: fresh.price, preClose: fresh.preClose, pos: snap);
      final text = buildNotificationText(
          metrics: metrics, selectedMetrics: _payload.selectedMetrics);
      await FlutterForegroundTask.updateService(
        notificationTitle: '金脉 · ${snap.kindLabel}',
        notificationText: text,
      );
    } catch (_) {
      // 后台刷新失败静默，保留上一条通知。
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort sendPort) async {}

  @override
  Future<void> onNotificationPressed(DateTime timestamp, SendPort sendPort) async {}
}

String _kindCode(String kind) => switch (kind) {
      'au9999' => 'SGE-Au(T+D)',
      'icbc' => 'ICBC-JCJ',
      'minsheng' => 'MSB-JCJ',
      _ => 'CZB-JCJ',
    };

extension on PositionSnapshot {
  String get kindLabel => switch (kind) {
        'au9999' => 'Au9999',
        'icbc' => '工商积存金',
        'minsheng' => '民生积存金',
        _ => '浙商积存金',
      };
}

/// 拼通知文本：第一行「品种 涨跌额 现价」，下方自选指标「名 值」（每行一个，2 列用空格对齐）。
/// 纯函数，可单测。
String buildNotificationText({
  required Map<String, String> metrics,
  required List<String> selectedMetrics,
}) {
  final buf = StringBuffer();
  buf.writeln('涨跌 ${metrics['change'] ?? '--'}    ${metrics['price'] ?? '--'} 元/g');
  for (final id in selectedMetrics) {
    final label = metricLabels[id] ?? id;
    final value = metrics[id] ?? '--';
    buf.writeln('$label  $value');
  }
  return buf.toString().trimRight();
}
```

**注意：** 以下 flutter_foreground_task 10.x API 名称以 Task 1 安装后实际版本为准，实现时若签名不符按插件文档修正：
- `ForegroundTaskEventAction.repeat(ms)`、`FlutterForegroundTask.receiveDataFromTask(cb)`、`FlutterForegroundTask.sendDataToTask(data)`、`TaskStarter`、`updateService(notificationTitle:, notificationText:)`。
- `PositionSnapshot.kindLabel` 扩展可改为 `notification_metrics.dart` 内普通函数（更清晰，但扩展可接受）。

- [ ] **Step 4: 运行测试确认通过**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/persistent_notification_service_test.dart`
Expected: All tests passed!

- [ ] **Step 5: 提交**

```bash
git add lib/services/persistent_notification_service.dart test/persistent_notification_service_test.dart
git commit -m "feat: 常驻通知前台服务（后台 isolate 拉行情+持仓快照更新通知）"
```

---
---

### Task 4: 配置存储 + 设置页 UI

**Files:**
- Create: `goldpulse/lib/state/persistent_notification_provider.dart`
- Modify: `goldpulse/lib/pages/setting_page.dart`
- Test: `goldpulse/test/persistent_notification_provider_test.dart`（或并入 widget 测试）

**Interfaces:**
- Consumes: `metricIds`/`metricLabels`（Task 2）；`syncPersistentNotificationData`/`startPersistentNotification`/`stopPersistentNotification`（Task 3）；`typeSummariesProvider`（算持仓快照）；`_kindLabel`（asset_provider）。
- Produces:
  - `final persistentNotificationConfigProvider = NotifierProvider<PersistentNotificationConfigNotifier, PersistentNotificationConfig>`：`PersistentNotificationConfig { bool enabled; String kind; int intervalSeconds; List<String> metrics; }`，读写 SharedPreferences（key 见 Global Constraints）。
  - `Future<void> syncNotificationPosition(WidgetRef ref)`：从 `typeSummariesProvider` 取所选品种的 `TypeAssetSummary` → `PositionSnapshot` → `syncPersistentNotificationData`。
  - 设置页「常驻通知栏」区块：总开关 Switch、品种 Dropdown、频率 Dropdown(5/10/30/60)、指标多选（ChoiceChip，最多 4 个，>4 时 toast 提示）。

行为：
- 开关 on → `startPersistentNotification(kind, intervalSeconds)` + `syncNotificationPosition` + 写 prefs enabled=true；off → `stopPersistentNotification` + prefs enabled=false。
- 品种/频率/指标变更 → 写 prefs + 重启服务（若 enabled）+ 重新同步快照。

- [ ] **Step 1: 写失败测试（配置读写 + 8 选 4）**

创建 `goldpulse/test/persistent_notification_provider_test.dart`：

```dart
// test/persistent_notification_provider_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/state/persistent_notification_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('默认配置：关闭、浙商、10 秒、4 个默认指标', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(persistentNotificationConfigProvider);
    expect(c.enabled, isFalse);
    expect(c.kind, 'accumulation');
    expect(c.intervalSeconds, 10);
    expect(c.metrics, hasLength(4));
  });

  test('选第 5 个指标被拒绝（8 选 4 限制）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(persistentNotificationConfigProvider.notifier);
    // 已有 4 个，再选一个 → 列表仍 4 个
    expect(notifier.toggleMetric('cumulativeProfit'), isFalse);
    expect(container.read(persistentNotificationConfigProvider).metrics, hasLength(4));
  });

  test('切换品种后配置持久化', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(persistentNotificationConfigProvider.notifier)
        .setKind('icbc');
    expect(container.read(persistentNotificationConfigProvider).kind, 'icbc');
  });
}
```

（`toggleMetric` 返回 bool 表示是否成功——已满 4 个返回 false。实现时若用 Notifier 方法签名不同，测试同步调整。）

- [ ] **Step 2: 运行测试确认失败**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/persistent_notification_provider_test.dart`
Expected: 编译失败（文件不存在）。

- [ ] **Step 3: 实现 provider**

创建 `goldpulse/lib/state/persistent_notification_provider.dart`：

```dart
// lib/state/persistent_notification_provider.dart
// 常驻通知栏配置：开关/品种/频率/指标 读写 SharedPreferences。
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/notification_metrics.dart';

class PersistentNotificationConfig {
  final bool enabled;
  final String kind;
  final int intervalSeconds;
  final List<String> metrics;
  const PersistentNotificationConfig({
    this.enabled = false,
    this.kind = 'accumulation',
    this.intervalSeconds = 10,
    this.metrics = const ['avgCost', 'floatingProfit', 'profitRate', 'todayProfit'],
  });

  PersistentNotificationConfig copyWith({
    bool? enabled, String? kind, int? intervalSeconds, List<String>? metrics,
  }) => PersistentNotificationConfig(
        enabled: enabled ?? this.enabled,
        kind: kind ?? this.kind,
        intervalSeconds: intervalSeconds ?? this.intervalSeconds,
        metrics: metrics ?? this.metrics,
      );
}

const _kEnabled = 'notificationBarEnabled';
const _kKind = 'notificationBarKind';
const _kInterval = 'notificationBarIntervalSeconds';
const _kMetrics = 'notificationBarMetrics';

class PersistentNotificationConfigNotifier
    extends Notifier<PersistentNotificationConfig> {
  @override
  PersistentNotificationConfig build() {
    final prefs = ...; // 同步读一次（SharedPreferences.getInstance 异步；用 StateNotifier + 初始化兜底）
    // 实际实现：异步初始化见 Step 3 说明；此处返回默认值并在 setter 里读写 prefs。
    return const PersistentNotificationConfig();
  }

  Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, v);
    state = state.copyWith(enabled: v);
  }

  Future<void> setKind(String kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kKind, kind);
    state = state.copyWith(kind: kind);
  }

  Future<void> setIntervalSeconds(int s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kInterval, s);
    state = state.copyWith(intervalSeconds: s);
  }

  /// 切换指标：已选则移除，未选且未满 4 个则加入。满 4 个时返回 false（拒绝）。
  Future<bool> toggleMetric(String id) async {
    final cur = state.metrics;
    final next = cur.contains(id)
        ? [...cur]..remove(id)
        : cur.length >= 4
            ? cur
            : [...cur, id];
    if (identical(next, cur)) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMetrics, jsonEncode(next));
    state = state.copyWith(metrics: next);
    return true;
  }
}

final persistentNotificationConfigProvider =
    NotifierProvider<PersistentNotificationConfigNotifier, PersistentNotificationConfig>(
        PersistentNotificationConfigNotifier.new);
```

（`build()` 中同步读 prefs 的真实实现：因为 SharedPreferences.getInstance 是异步，Notifier 同步 build 无法直接读。解决：provider 改为 `FutureProvider`，或 `build()` 里返回默认值 + 在启动时用 `SharedPreferences.getInstance()` 显式恢复。**实现者按此约束选择最简方式**：建议 `build()` 只返回默认，另加 `Future<void> loadFromPrefs()` 在 app 启动/设置页 initState 调用恢复已存配置。）

- [ ] **Step 4: 设置页 UI**

在 `goldpulse/lib/pages/setting_page.dart` 新增「常驻通知栏」卡片区块（读该文件现有 UI 风格后插入），包含：
1. 总开关：`SwitchListTile` 绑定 `persistentNotificationConfigProvider` 的 `enabled`；onChanged → `setEnabled(v)` + 若 v=true 则 `startPersistentNotification(kind, intervalSeconds)` + `syncNotificationPosition(ref)`；false 则 `stopPersistentNotification()`。
2. 品种选择：`DropdownButtonFormField<String>`（4 品种，默认 accumulation）→ `setKind` + 重启服务 + 重同步。
3. 频率选择：`DropdownButtonFormField<int>`（[5,10,30,60]，label `每 N 秒`）→ `setIntervalSeconds` + 重启服务。
4. 指标多选：`Wrap` 内 `ChoiceChip`（8 个指标，`metricLabels`），选中态绑定 metrics；点击 → `toggleMetric`，返回 false 时 `ScaffoldMessenger` 提示「最多展示 4 个指标」。

- [ ] **Step 5: 运行测试确认通过**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter test test/persistent_notification_provider_test.dart && flutter test`
Expected: All tests passed!

- [ ] **Step 6: 提交**

```bash
git add lib/state/persistent_notification_provider.dart lib/pages/setting_page.dart test/persistent_notification_provider_test.dart
git commit -m "feat: 设置页常驻通知栏配置（开关/品种/频率/8选4指标）"
```

---
---

### Task 5: 集成（开关联动服务 + 持仓快照同步 + app 启动恢复）

**Files:**
- Modify: `goldpulse/lib/pages/setting_page.dart`（接线 `syncNotificationPosition`）
- Modify: `goldpulse/lib/state/persistent_notification_provider.dart`（`syncNotificationPosition` + `loadFromPrefs`）
- Modify: `goldpulse/lib/main.dart` 或 `goldpulse/lib/app.dart`（启动时若 enabled 则恢复服务）
- Modify: `goldpulse/lib/state/holding_provider.dart`（持仓变更后同步快照——可选，简化：每次设置页操作同步 + 启动同步）

**Interfaces:**
- Consumes: Task 2-4 产物。
- Produces: 端到端可用：开关开 → 通知栏出现常驻通知并实时更新。

- [ ] **Step 1: 实现 `syncNotificationPosition`**

在 `persistent_notification_provider.dart` 加：

```dart
/// 从 typeSummariesProvider 取所选品种汇总 → 构造 PositionSnapshot → 同步到后台服务。
Future<void> syncNotificationPosition(WidgetRef ref) async {
  final cfg = ref.read(persistentNotificationConfigProvider);
  final summaries = await ref.read(typeSummariesProvider.future);
  final t = summaries.where((s) => s.kind == cfg.kind).firstOrNull;
  if (t == null) return;
  await syncPersistentNotificationData(
    kind: cfg.kind,
    selectedMetrics: cfg.metrics,
    snapshot: PositionSnapshot(
      kind: t.kind, grams: t.totalGrams, totalCost: t.totalCost,
      boughtCost: t.totalCost, // 简化：boughtCost 用 totalCost；如需精确从 holdings 取
      soldNet: 0,
    ),
  );
}
```

（若需精确 boughtCost/soldNet：从 `holdingsProvider` 读该品种持仓 `boughtCost` 合计 + `tradeDaoProvider` 算卖出净得——实现者按 `asset_provider` 的既有口径复刻。）

- [ ] **Step 2: app 启动恢复**

`app.dart` 或 `main.dart` 启动后（`runApp` 前或 ProviderScope 内）：读 prefs `notificationBarEnabled`，若 true → `startPersistentNotification(kind, intervalSeconds)` + `syncNotificationPosition`。若无持仓快照，通知显示"无持仓"。

- [ ] **Step 3: 全量测试 + 构建**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter analyze && flutter test`
Expected: No issues found! + All tests passed!

- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "feat: 常驻通知栏集成（开关联动服务/持仓快照同步/启动恢复）"
```

---
---

### Task 6: 全量验证 + 装机 + 收尾

- [ ] **Step 1: 全量测试 + analyze**

Run: `cd goldpulse && export PATH="$(printf '%s' "$PATH" | tail -n 1)" && flutter analyze && flutter test`
Expected: 全绿。

- [ ] **Step 2: 构建 + 装机验证**

Run: `export GOLDPULSE_KEY_PASS='GoldPulse@2026Key' && flutter build apk --release --split-per-abi`
安装 arm64 版到真机。验证：
1. 设置页开启「常驻通知栏」→ 通知中心出现常驻通知（标题「金脉 · 浙商积存金」+ 4 指标）。
2. 通知内容随行情刷新更新（观察 logcat `flutter_foreground_task` 或通知文本变化）。
3. 切换品种/频率/指标 → 通知按新配置更新。
4. 关闭开关 → 通知消失。

- [ ] **Step 3: 提交推送**

```bash
git push origin main
```
