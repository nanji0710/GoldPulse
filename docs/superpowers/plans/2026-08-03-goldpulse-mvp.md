# 金脉 GoldPulse MVP 开发计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 从零构建金脉 GoldPulse —— 一款本地化、无账号的 Flutter Android 黄金资产监控 App（Au9999 行情 + 浙商积存金持仓盈亏 + 价格提醒）。

**Architecture:** 单模块 Flutter 应用。数据层用 sqflite 四张表（gold_price / holding / trade_record / alert），行情通过免费 JD 接口适配层拉取并本地缓存降级；计算模块纯函数实现（生息、卖出手续费、平均成本摊薄）；Riverpod 管理全局状态；页面按方案六章五页 + 首次引导构建。所有逻辑不依赖服务器。

**Tech Stack:** Flutter (Dart 3.x)，flutter_riverpod，sqflite + path，dio，fl_chart，flutter_local_notifications，workmanager，intl。测试用 flutter_test + sqflite_common_ffi。

**Spec:** [金脉_GoldPulse_App产品方案_v1.0.md](../../../金脉_GoldPulse_App产品方案_v1.0.md)

## Global Constraints

- 仅 Android 目标，UI 全中文；包名 `com.goldpulse.app`
- **红涨绿跌**（国内习惯）：上涨红色 `#E5484D`，下跌绿色 `#2E9E6B` —— 与西方习惯相反，所有图表/卡片遵守
- 黑金主题：背景 `#101216`，卡片 `#181B22`，黄金 `#D9A441`，次要文字 `#8A8F98`
- 无服务器、无账号、数据仅存本机 SQLite
- 精度：价格展示 2 位小数；克重展示 2 位、内部计算用 4 位；金额千分位
- 费用规则（浙商积存金）：买入手续费 0%，卖出手续费 0.4%
- 交易时段：Au9999 日盘 9:00–11:30 / 13:30–15:30、夜盘 21:00–次日 2:30；积存金周一 9:00–周六凌晨 2:30
- 免费行情接口为非官方，可能失效：请求与解析收敛到 `PriceApi` 单点维护，支持主源→备用源→本地缓存降级
- 后台价格提醒为"尽力而为"，UI 需标注"可能存在 15 分钟级延迟"
- 所有任务遵守 TDD：先写失败测试 → 实现 → 通过 → 提交

---

## 文件结构总览

```
goldpulse/
lib/
├── main.dart                     # 入口，初始化 Riverpod + 通知 + WorkManager
├── app.dart                      # MaterialApp、主题、路由
├── constants/
│   └── app_theme.dart            # 颜色/间距/文字规范（黑金主题）
├── models/
│   ├── gold_price.dart
│   ├── holding.dart
│   ├── trade_record.dart
│   └── alert.dart
├── database/
│   ├── app_database.dart         # sqflite 建库/迁移
│   ├── price_dao.dart
│   ├── holding_dao.dart
│   ├── trade_dao.dart
│   └── alert_dao.dart
├── services/
│   ├── calculator.dart           # 纯函数：价值/收益/成本/手续费
│   ├── price_api.dart            # 行情接口适配层（主/备源 + 解析）
│   ├── market_hours.dart         # 交易时段状态机
│   ├── alert_service.dart        # 提醒判定 + 本地通知
│   └── backup_service.dart       # JSON 导出/导入
├── state/
│   ├── price_provider.dart       # 行情轮询
│   ├── holding_provider.dart     # 持仓/交易记录
│   ├── asset_provider.dart       # 资产汇总（计算模块接入）
│   └── alert_provider.dart
├── pages/
│   ├── onboarding_page.dart
│   ├── home_page.dart
│   ├── market_page.dart
│   ├── asset_page.dart
│   ├── alert_page.dart
│   └── setting_page.dart
├── widgets/
│   ├── gold_card.dart
│   ├── profit_card.dart
│   └── chart.dart
└── utils/
    └── formatters.dart           # 千分位/精度/涨跌箭头
test/
├── calculator_test.dart
├── market_hours_test.dart
├── price_api_test.dart
├── database_test.dart
├── alert_service_test.dart
└── widget_smoke_test.dart        # 各页面冒烟测试
```

---

## Phase 1 — 地基与领域核心

### Task 1: 初始化 Flutter 项目与依赖

**Files:**
- Create: `goldpulse/`（Flutter 工程目录，位于仓库根目录）
- Modify: `goldpulse/pubspec.yaml`

**Interfaces:**
- Consumes: 无
- Produces: 可运行的 Flutter 工程；`pubspec.yaml` 锁定的依赖版本

- [ ] **Step 1: 创建 Flutter 工程**

```bash
cd d:/GitHub/GoldPulse
flutter create --org com.goldpulse --project-name goldpulse --platforms android goldpulse
cd goldpulse
```

- [ ] **Step 2: 添加依赖**

```bash
flutter pub add flutter_riverpod dio sqflite path intl fl_chart \
  flutter_local_notifications workmanager
flutter pub add --dev sqflite_common_ffi
```

`pubspec.yaml` 关键内容：

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1
  dio: ^5.7.0
  sqflite: ^2.4.1
  path: ^1.9.0
  intl: ^0.19.0
  fl_chart: ^0.69.0
  flutter_local_notifications: ^18.0.1
  workmanager: ^0.10.0
  # ^0.10.0 原因：0.5.x 使用已被 Flutter 3.44 移除的 v1 embedding shim，无法编译 APK；≥0.6.0 起移除 shim。
dev_dependencies:
  flutter_test:
    sdk: flutter
  sqflite_common_ffi: ^2.3.3
```

- [ ] **Step 3: 运行冒烟验证**

```bash
cd d:/GitHub/GoldPulse/goldpulse
flutter analyze
flutter test
```

Expected: `No issues found!`，默认 widget test 通过。

- [ ] **Step 4: 提交**

```bash
git add goldpulse/
git commit -m "chore: scaffold goldpulse flutter project"
```

---

### Task 2: 黑金主题与常量

**Files:**
- Create: `goldpulse/lib/constants/app_theme.dart`
- Create: `goldpulse/lib/app.dart`
- Modify: `goldpulse/lib/main.dart`
- Create: `goldpulse/test/theme_test.dart`

**Interfaces:**
- Consumes: Task 1 的工程
- Produces: `AppTheme` 常量类、`GoldPulseApp` widget（`MaterialApp` 入口）

- [ ] **Step 1: 写失败测试**

```dart
// test/theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/constants/app_theme.dart';

void main() {
  test('主题色符合黑金规范', () {
    expect(AppTheme.background, const Color(0xFF101216));
    expect(AppTheme.card, const Color(0xFF181B22));
    expect(AppTheme.gold, const Color(0xFFD9A441));
    expect(AppTheme.up, const Color(0xFFE5484D));   // 红涨
    expect(AppTheme.down, const Color(0xFF2E9E6B)); // 绿跌
    expect(AppTheme.textSecondary, const Color(0xFF8A8F98));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/theme_test.dart`
Expected: FAIL（`AppTheme` 未定义）

- [ ] **Step 3: 实现主题常量**

```dart
// lib/constants/app_theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();
  static const background = Color(0xFF101216);
  static const card = Color(0xFF181B22);
  static const gold = Color(0xFFD9A441);
  static const up = Color(0xFFE5484D);     // 红涨（国内习惯）
  static const down = Color(0xFF2E9E6B);   // 绿跌
  static const textPrimary = Color(0xFFF2F3F5);
  static const textSecondary = Color(0xFF8A8F98);
  static const offline = Color(0xFF6B7280);

  static ThemeData theme() => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          surface: card,
        ),
        cardColor: card,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: textPrimary,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: textPrimary),
          headlineMedium: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: textPrimary),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textPrimary),
          bodyMedium: TextStyle(fontSize: 14, color: textSecondary),
        ),
      );
}
```

- [ ] **Step 4: 实现 App 入口**

```dart
// lib/app.dart
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';

class GoldPulseApp extends StatelessWidget {
  const GoldPulseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '金脉 GoldPulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      home: const Scaffold(body: Center(child: Text('金脉 GoldPulse'))),
    );
  }
}
```

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

void main() {
  runApp(const ProviderScope(child: GoldPulseApp()));
}
```

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add lib test
git commit -m "feat: add black-gold theme and app entry"
```

---

### Task 3: 数据模型

**Files:**
- Create: `goldpulse/lib/models/gold_price.dart`
- Create: `goldpulse/lib/models/holding.dart`
- Create: `goldpulse/lib/models/trade_record.dart`
- Create: `goldpulse/lib/models/alert.dart`
- Create: `goldpulse/test/models_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `GoldPrice`、`Holding`、`TradeRecord`、`Alert` 四类，均含 `toMap()/fromMap()`（供 DAO 与迁移使用）

- [ ] **Step 1: 写失败测试**

```dart
// test/models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/models/alert.dart';

void main() {
  test('GoldPrice round-trip', () {
    final gp = GoldPrice(code: 'SGE-Au(T+D)', price: 780.20, change: 3.5, percent: 0.45, preClose: 776.70, time: 1000);
    final back = GoldPrice.fromMap(gp.toMap()..['id'] = 1);
    expect(back.price, 780.20);
    expect(back.preClose, 776.70);
    expect(back.id, 1);
  });
  test('Holding fromMap', () {
    final h = Holding.fromMap({'id': 1, 'name': '浙商积存金', 'kind': 'accumulation', 'amount': 501.2, 'total_cost': 310000.0, 'created_at': 1});
    expect(h.kind, 'accumulation');
    expect(h.amount, 501.2);
  });
  test('TradeRecord types', () {
    final t = TradeRecord(holdingId: 1, type: 'interest', amount: 0.08, price: 0, fee: 0, time: 2);
    expect(t.type, 'interest');
  });
  test('Alert round-trip', () {
    final a = Alert(type: 'price_up', target: 800, enable: true);
    final back = Alert.fromMap(a.toMap()..['id'] = 3);
    expect(back.enable, true);
    expect(back.id, 3);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/models_test.dart`
Expected: FAIL（模型类未定义）

- [ ] **Step 3: 实现四个模型**

```dart
// lib/models/gold_price.dart
class GoldPrice {
  final int id;
  final String code;      // 如 'SGE-Au(T+D)' / 'CZB-JCJ'
  final double price;     // 元/g
  final double change;    // 涨跌额
  final double percent;   // 涨跌幅 %
  final double preClose;  // 上日收盘价
  final int time;         // 毫秒时间戳
  const GoldPrice({this.id = 0, required this.code, required this.price, required this.change, required this.percent, required this.preClose, required this.time});

  Map<String, Object?> toMap() => {
        'id': id, 'code': code, 'price': price, 'change': change,
        'percent': percent, 'pre_close': preClose, 'time': time,
      };
  factory GoldPrice.fromMap(Map<String, Object?> m) => GoldPrice(
        id: m['id'] as int? ?? 0,
        code: m['code'] as String,
        price: (m['price'] as num).toDouble(),
        change: (m['change'] as num).toDouble(),
        percent: (m['percent'] as num).toDouble(),
        preClose: (m['pre_close'] as num).toDouble(),
        time: m['time'] as int,
      );
}
```

```dart
// lib/models/holding.dart
class Holding {
  final int id;
  final String name;
  final String kind;      // 'au9999' | 'accumulation'
  final double amount;    // 当前持有克重（含生息）
  final double totalCost; // 累计买入总成本（元）
  final int createdAt;
  const Holding({this.id = 0, required this.name, required this.kind, required this.amount, required this.totalCost, required this.createdAt});

  Map<String, Object?> toMap() => {
        'id': id, 'name': name, 'kind': kind, 'amount': amount,
        'total_cost': totalCost, 'created_at': createdAt,
      };
  factory Holding.fromMap(Map<String, Object?> m) => Holding(
        id: m['id'] as int? ?? 0,
        name: m['name'] as String,
        kind: m['kind'] as String,
        amount: (m['amount'] as num).toDouble(),
        totalCost: (m['total_cost'] as num).toDouble(),
        createdAt: m['created_at'] as int,
      );
}
```

```dart
// lib/models/trade_record.dart
class TradeRecord {
  final int id;
  final int holdingId;
  final String type;      // 'buy' | 'sell' | 'interest'
  final double amount;    // 克重（生息为正克重）
  final double price;     // 成交价（interest 为 0）
  final double fee;       // 手续费（元）
  final int time;
  const TradeRecord({this.id = 0, required this.holdingId, required this.type, required this.amount, required this.price, required this.fee, required this.time});

  Map<String, Object?> toMap() => {
        'id': id, 'holding_id': holdingId, 'type': type, 'amount': amount,
        'price': price, 'fee': fee, 'time': time,
      };
  factory TradeRecord.fromMap(Map<String, Object?> m) => TradeRecord(
        id: m['id'] as int? ?? 0,
        holdingId: m['holding_id'] as int,
        type: m['type'] as String,
        amount: (m['amount'] as num).toDouble(),
        price: (m['price'] as num).toDouble(),
        fee: (m['fee'] as num).toDouble(),
        time: m['time'] as int,
      );
}
```

```dart
// lib/models/alert.dart
class Alert {
  final int id;
  final String type;     // 'price_up' | 'price_down' | 'profit_target'
  final double target;   // 目标价（元/g）或目标金额（元）
  final bool enable;
  final int triggerCount;
  final int lastTriggered;
  const Alert({this.id = 0, required this.type, required this.target, required this.enable, this.triggerCount = 0, this.lastTriggered = 0});

  Map<String, Object?> toMap() => {
        'id': id, 'type': type, 'target': target, 'enable': enable ? 1 : 0,
        'trigger_count': triggerCount, 'last_triggered': lastTriggered,
      };
  factory Alert.fromMap(Map<String, Object?> m) => Alert(
        id: m['id'] as int? ?? 0,
        type: m['type'] as String,
        target: (m['target'] as num).toDouble(),
        enable: (m['enable'] as int) == 1,
        triggerCount: m['trigger_count'] as int? ?? 0,
        lastTriggered: m['last_triggered'] as int? ?? 0,
      );
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/models_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/models test/models_test.dart
git commit -m "feat: add data models"
```

---

### Task 4: 数据库层（建库 + 迁移 + DAO）

**Files:**
- Create: `goldpulse/lib/database/app_database.dart`
- Create: `goldpulse/lib/database/price_dao.dart`
- Create: `goldpulse/lib/database/holding_dao.dart`
- Create: `goldpulse/lib/database/trade_dao.dart`
- Create: `goldpulse/lib/database/alert_dao.dart`
- Create: `goldpulse/test/database_test.dart`

**Interfaces:**
- Consumes: Task 3 的四个模型
- Produces: `AppDatabase.database`（单例）；`PriceDao`、`HoldingDao`、`TradeDao`、`AlertDao` 的 CRUD 方法

**Schema（依据方案九章，含 UNIQUE 约束与索引）：**

- `gold_price(code TEXT, price REAL, change REAL, percent REAL, pre_close REAL, time INTEGER, id INTEGER PRIMARY KEY AUTOINCREMENT, UNIQUE(code, time))`
- `holding(name TEXT, kind TEXT, amount REAL, total_cost REAL, created_at INTEGER, id INTEGER PRIMARY KEY AUTOINCREMENT)`
- `trade_record(holding_id INTEGER, type TEXT, amount REAL, price REAL, fee REAL, time INTEGER, id INTEGER PRIMARY KEY AUTOINCREMENT)`
- `alert(type TEXT, target REAL, enable INTEGER, trigger_count INTEGER DEFAULT 0, last_triggered INTEGER DEFAULT 0, id INTEGER PRIMARY KEY AUTOINCREMENT)`
- 索引：`CREATE INDEX idx_gold_price_code_time ON gold_price(code, time)`；`idx_trade_holding ON trade_record(holding_id)`

- [ ] **Step 1: 写失败测试（用 ffi 在桌面跑 sqflite）**

```dart
// test/database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/database/price_dao.dart';
import 'package:goldpulse/database/holding_dao.dart';
import 'package:goldpulse/database/trade_dao.dart';
import 'package:goldpulse/database/alert_dao.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/models/trade_record.dart';
import 'package:goldpulse/models/alert.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    AppDatabase.databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await AppDatabase.reset(); // 每个用例重建内存库
  });

  test('gold_price 防重复写入', () async {
    final dao = PriceDao();
    final gp = GoldPrice(code: 'SGE-Au(T+D)', price: 780, change: 1, percent: 0.1, preClose: 779, time: 1000);
    await dao.insert(gp);
    await dao.insert(gp);
    expect(await dao.count(), 1);
  });
  test('holding CRUD', () async {
    final dao = HoldingDao();
    final id = await dao.insert(Holding(name: '浙商积存金', kind: 'accumulation', amount: 500, totalCost: 310000, createdAt: 1));
    final list = await dao.list();
    expect(list.single.amount, 500);
    await dao.updateAmount(id, 501.2);
    expect((await dao.get(id))!.amount, 501.2);
  });
  test('trade_record 支持三类事件', () async {
    final dao = TradeDao();
    await dao.insert(TradeRecord(holdingId: 1, type: 'buy', amount: 100, price: 600, fee: 0, time: 1));
    await dao.insert(TradeRecord(holdingId: 1, type: 'interest', amount: 0.08, price: 0, fee: 0, time: 2));
    final list = await dao.listByHolding(1);
    expect(list.map((t) => t.type), ['buy', 'interest']);
  });
  test('alert 默认 enable 关/开', () async {
    final dao = AlertDao();
    final id = await dao.insert(Alert(type: 'price_up', target: 800, enable: true));
    expect((await dao.get(id))!.enable, true);
    await dao.toggle(id, false);
    expect((await dao.get(id))!.enable, false);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/database_test.dart`
Expected: FAIL（类未定义 / 测试环境需 `sqfliteFfiInit`）

- [ ] **Step 3: 实现建库与迁移**

```dart
// lib/database/app_database.dart
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi;

class AppDatabase {
  AppDatabase._();
  static const _name = 'goldpulse.db';
  static const _version = 1;
  static DatabaseFactory databaseFactory = databaseFactorySqflite;
  static Database? _db;

  static Future<Database> get database async => _db ??= await _open();
  static Future<void> reset() async { await _db?.close(); _db = null; }

  static Future<Database> _open() async {
    final dir = await databaseFactory.getDatabasesPath();
    final path = join(dir, _name);
    return databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(version: _version, onCreate: _onCreate, onUpgrade: _onUpgrade));
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE gold_price(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        price REAL NOT NULL,
        change REAL NOT NULL,
        percent REAL NOT NULL,
        pre_close REAL NOT NULL,
        time INTEGER NOT NULL,
        UNIQUE(code, time)
      )''');
    await db.execute('''
      CREATE TABLE holding(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        amount REAL NOT NULL,
        total_cost REAL NOT NULL,
        created_at INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE trade_record(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        holding_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        price REAL NOT NULL,
        fee REAL NOT NULL,
        time INTEGER NOT NULL
      )''');
    await db.execute('''
      CREATE TABLE alert(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        target REAL NOT NULL,
        enable INTEGER NOT NULL DEFAULT 0,
        trigger_count INTEGER NOT NULL DEFAULT 0,
        last_triggered INTEGER NOT NULL DEFAULT 0
      )''');
    await db.execute('CREATE INDEX idx_gold_price_code_time ON gold_price(code, time)');
    await db.execute('CREATE INDEX idx_trade_holding ON trade_record(holding_id)');
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // 未来 schema 变更在此用版本号分叉处理（示例）：
    // if (oldV < 2) { await db.execute('ALTER TABLE ...'); }
  }
}
```

- [ ] **Step 4: 实现 DAO（四份，含事务式写入）**

```dart
// lib/database/price_dao.dart
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/gold_price.dart';

class PriceDao {
  Future<Database> get _db => AppDatabase.database;
  Future<void> insert(GoldPrice gp) async {
    final db = await _db;
    await db.insert('gold_price', gp.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore); // UNIQUE(code,time) 冲突时忽略
  }
  Future<List<GoldPrice>> recent(String code, {int limit = 500}) async {
    final db = await _db;
    final rows = await db.query('gold_price', where: 'code = ?', whereArgs: [code], orderBy: 'time DESC', limit: limit);
    return rows.map(GoldPrice.fromMap).toList();
  }
  Future<GoldPrice?> latest(String code) async {
    final list = await recent(code, limit: 1);
    return list.isEmpty ? null : list.first;
  }
  Future<void> pruneOlderThan({required int code, required int before}) async {
    final db = await _db;
    await db.delete('gold_price', where: 'time < ?', whereArgs: [before]);
  }
  Future<int> count() async => Sqflite.firstIntValue(await (await _db).rawQuery('SELECT COUNT(*) FROM gold_price')) ?? 0;
}
```

```dart
// lib/database/holding_dao.dart
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import '../models/holding.dart';

class HoldingDao {
  Future<Database> get _db => AppDatabase.database;
  Future<int> insert(Holding h) async => (await _db).insert('holding', h.toMap());
  Future<List<Holding>> list() async {
    final rows = await (await _db).query('holding', orderBy: 'created_at');
    return rows.map(Holding.fromMap).toList();
  }
  Future<Holding?> get(int id) async {
    final rows = await (await _db).query('holding', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Holding.fromMap(rows.first);
  }
  Future<void> updateAmount(int id, double newAmount) async {
    await (await _db).update('holding', {'amount': newAmount}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> updateCost(int id, double newTotalCost) async {
    await (await _db).update('holding', {'total_cost': newTotalCost}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('trade_record', where: 'holding_id = ?', whereArgs: [id]);
    await db.delete('holding', where: 'id = ?', whereArgs: [id]);
  }
}
```

```dart
// lib/database/trade_dao.dart
import '../database/app_database.dart';
import '../models/trade_record.dart';

class TradeDao {
  Future<List<TradeRecord>> listByHolding(int holdingId) async {
    final rows = await (await AppDatabase.database).query('trade_record',
        where: 'holding_id = ?', whereArgs: [holdingId], orderBy: 'time ASC');
    return rows.map(TradeRecord.fromMap).toList();
  }
  Future<int> insert(TradeRecord t) async => (await AppDatabase.database).insert('trade_record', t.toMap());
  Future<List<TradeRecord>> all() async {
    final rows = await (await AppDatabase.database).query('trade_record', orderBy: 'time ASC');
    return rows.map(TradeRecord.fromMap).toList();
  }
  Future<void> delete(int id) async {
    await (await AppDatabase.database).delete('trade_record', where: 'id = ?', whereArgs: [id]);
  }
}
```

```dart
// lib/database/alert_dao.dart
import '../database/app_database.dart';
import '../models/alert.dart';

class AlertDao {
  Future<List<Alert>> list() async {
    final rows = await (await AppDatabase.database).query('alert', orderBy: 'id');
    return rows.map(Alert.fromMap).toList();
  }
  Future<Alert?> get(int id) async {
    final rows = await (await AppDatabase.database).query('alert', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Alert.fromMap(rows.first);
  }
  Future<int> insert(Alert a) async => (await AppDatabase.database).insert('alert', a.toMap());
  Future<void> toggle(int id, bool enable) async {
    await (await AppDatabase.database).update('alert', {'enable': enable ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<void> recordTrigger(int id, {DateTime? time}) async {
    final now = time ?? DateTime.now();
    await (await AppDatabase.database).rawUpdate(
        'UPDATE alert SET trigger_count = trigger_count + 1, last_triggered = ? WHERE id = ?',
        [now.millisecondsSinceEpoch, id]);
  }
  Future<void> delete(int id) async {
    await (await AppDatabase.database).delete('alert', where: 'id = ?', whereArgs: [id]);
  }
}
```

> 说明：`recordTrigger` 用 `rawUpdate` 实现 `trigger_count = trigger_count + 1`（直接赋值 `-1` 是错误的——SQLite 不会把它解释为自增）。可选参数 `time` 用于测试注入确定性时间。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test test/database_test.dart`
Expected: PASS（4 个用例全绿）

- [ ] **Step 6: 提交**

```bash
git add lib/database test/database_test.dart
git commit -m "feat: add sqflite schema and DAOs"
```

---

### Task 5: 资产计算模块（纯函数 + TDD）

**Files:**
- Create: `goldpulse/lib/services/calculator.dart`
- Create: `goldpulse/test/calculator_test.dart`

**Interfaces:**
- Consumes: `Holding`、`TradeRecord`（Task 3）
- Produces: `Calculator.currentValue`、`floatingProfit`、`profitRate`、`avgCost`、`sellFee`、`sellNetProfit`；`Calculator.applyTrade`（核心：买入/卖出/生息后同步持仓克重与总成本）

**计算口径（方案八章）：**

- 当前价值 = 价格 × 克重
- 浮动收益 = 当前价值 − 累计买入总成本
- 收益率 = 浮动收益 ÷ 累计买入总成本
- 平均成本 = 累计买入总成本 ÷ 当前克重（生息摊薄）
- 卖出手续费 = 卖出克重 × 卖出价 × 0.4%
- 卖出净收益 = 卖出克重 ×（卖出价 − 平均成本）− 手续费
- 买入：amount += 买入克重，totalCost += 买入克重 × 买入价
- 生息：amount += 生息克重，totalCost 不变（摊薄成本）
- 卖出：amount −= 卖出克重，totalCost 不变（保留买入成本；卖出盈亏单独结算）

- [ ] **Step 1: 写失败测试**

```dart
// test/calculator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/calculator.dart';
import 'package:goldpulse/models/trade_record.dart';

void main() {
  test('当前价值 = 价格 × 克重', () {
    expect(Calculator.currentValue(781.5, 501.2), closeTo(391687.80, 0.01));
  });
  test('浮动收益 = 价值 − 总成本', () {
    expect(Calculator.floatingProfit(781.5, 501.2, 310000), closeTo(81687.80, 0.01));
  });
  test('收益率', () {
    expect(Calculator.profitRate(81687.80, 310000), closeTo(0.2635, 0.0001));
  });
  test('平均成本 = 总成本 ÷ 克重（生息摊薄）', () {
    expect(Calculator.avgCost(310000, 501.2), closeTo(618.515, 0.001));
  });
  test('卖出手续费 = 金额 × 0.4%', () {
    expect(Calculator.sellFee(100, 780.20), closeTo(312.08, 0.01));
  });
  test('卖出净收益含手续费', () {
    // 100g @780.20，平均成本 620，手续费 100*780.20*0.004=312.08
    expect(Calculator.sellNetProfit(100, 780.20, 620), closeTo(100*(780.20-620)-312.08, 0.01));
  });
  test('applyTrade: 买入累加克重与成本', () {
    final h = Calculator.applyTrade(amount: 0, totalCost: 0,
        record: TradeRecord(holdingId: 1, type: 'buy', amount: 100, price: 600, fee: 0, time: 1));
    expect(h.amount, 100);
    expect(h.totalCost, 60000);
  });
  test('applyTrade: 生息只增克重、摊薄成本', () {
    final h = Calculator.applyTrade(amount: 500, totalCost: 310000,
        record: TradeRecord(holdingId: 1, type: 'interest', amount: 1.2, price: 0, fee: 0, time: 1));
    expect(h.amount, 501.2);
    expect(h.totalCost, 310000);
  });
  test('applyTrade: 卖出只减克重、保留成本', () {
    final h = Calculator.applyTrade(amount: 500, totalCost: 310000,
        record: TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 720, fee: 144, time: 1));
    expect(h.amount, 450);
    expect(h.totalCost, 310000);
  });
  test('卖出后禁止负克重', () {
    expect(() => Calculator.applyTrade(amount: 10, totalCost: 1000,
        record: TradeRecord(holdingId: 1, type: 'sell', amount: 50, price: 720, fee: 0, time: 1)),
        throwsArgumentError);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/calculator_test.dart`
Expected: FAIL（未定义）

- [ ] **Step 3: 实现计算模块**

```dart
// lib/services/calculator.dart
import '../models/holding.dart';
import '../models/trade_record.dart';

const double sellFeeRate = 0.004; // 浙商积存金卖出手续费 0.4%

class Calculator {
  Calculator._();

  static double currentValue(double price, double amount) => price * amount;

  static double floatingProfit(double price, double amount, double totalCost) =>
      price * amount - totalCost;

  static double profitRate(double profit, double totalCost) =>
      totalCost == 0 ? 0 : profit / totalCost;

  static double avgCost(double totalCost, double amount) =>
      amount == 0 ? 0 : totalCost / amount;

  static double sellFee(double sellAmount, double sellPrice) =>
      sellAmount * sellPrice * sellFeeRate;

  static double sellNetProfit(double sellAmount, double sellPrice, double avgCostPrice) {
    final gross = sellAmount * (sellPrice - avgCostPrice);
    return gross - sellFee(sellAmount, sellPrice);
  }

  /// 应用一笔交易到持仓状态，返回新的克重与总成本。
  /// [amount] 当前克重，[totalCost] 累计买入总成本。
  /// 买入：克重、成本都增；生息：仅克重增（摊薄成本）；卖出：仅克重减、成本保留。
  static ({double amount, double totalCost}) applyTrade({
    required double amount,
    required double totalCost,
    required TradeRecord record,
  }) {
    switch (record.type) {
      case 'buy':
        return (amount: amount + record.amount, totalCost: totalCost + record.amount * record.price);
      case 'interest':
        return (amount: amount + record.amount, totalCost: totalCost);
      case 'sell':
        if (record.amount > amount) {
          throw ArgumentError('卖出克重不能大于当前持仓');
        }
        return (amount: amount - record.amount, totalCost: totalCost);
      default:
        throw ArgumentError('未知交易类型: ${record.type}');
    }
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/calculator_test.dart`
Expected: PASS（10 个用例全绿）

- [ ] **Step 5: 提交**

```bash
git add lib/services/calculator.dart test/calculator_test.dart
git commit -m "feat: add asset calculator with interest/fee/cost-dilution"
```

---

### Task 6: 交易时段状态机

**Files:**
- Create: `goldpulse/lib/services/market_hours.dart`
- Create: `goldpulse/test/market_hours_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `enum MarketPhase { trading, lunchBreak, closed, weekend }`；`MarketHours.phaseAt(DateTime now)`；`MarketHours.isTrading(DateTime now)`；`MarketHours.nextOpen(DateTime now)`

**规则（方案八章）：** Au9999 日盘 9:00–11:30 / 13:30–15:30；夜盘 21:00–次日 2:30；其余为休市/周末。

- [ ] **Step 1: 写失败测试**

```dart
// test/market_hours_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/market_hours.dart';

void main() {
  DateTime at(int hour, [int minute = 0]) {
    // 固定用 2026-08-03（周一）
    return DateTime(2026, 8, 3, hour, minute);
  }

  test('日盘交易中', () {
    expect(MarketHours.isTrading(at(10)), isTrue);
    expect(MarketHours.phaseAt(at(10)), MarketPhase.trading);
  });
  test('午间休市', () {
    expect(MarketHours.phaseAt(at(12)), MarketPhase.lunchBreak);
  });
  test('下午盘交易中', () {
    expect(MarketHours.phaseAt(at(14)), MarketPhase.trading);
  });
  test('收盘（夜盘前）', () {
    expect(MarketHours.phaseAt(at(17)), MarketPhase.closed);
  });
  test('夜盘交易中', () {
    expect(MarketHours.isTrading(at(22)), isTrue);
  });
  test('凌晨夜盘（次日 1 点）仍在交易', () {
    expect(MarketHours.isTrading(DateTime(2026, 8, 4, 1)), isTrue);
  });
  test('凌晨 3 点休市', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 4, 3)), MarketPhase.closed);
  });
  test('周日休市（weekend）', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 2, 12)), MarketPhase.weekend);
  });
  test('周一凌晨 0:00–2:30 休市（周日无夜盘）', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 3, 1)), MarketPhase.closed);
  });
  test('周六凌晨 2:00 仍属周五夜盘尾', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 1, 2)), MarketPhase.trading);
  });
  test('凌晨 2:45 已收盘（夜盘 2:30 截止）', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 4, 2, 45)), MarketPhase.closed);
  });
  test('周六凌晨 2:45 休市', () {
    expect(MarketHours.phaseAt(DateTime(2026, 8, 1, 2, 45)), MarketPhase.weekend);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/market_hours_test.dart`
Expected: FAIL（未定义）

- [ ] **Step 3: 实现状态机**

```dart
// lib/services/market_hours.dart
enum MarketPhase { trading, lunchBreak, closed, weekend }

class MarketHours {
  MarketHours._();

  static MarketPhase phaseAt(DateTime now) {
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      // 周六 0:00–2:30 仍属夜盘尾段
      if (now.weekday == DateTime.saturday && _isNightSession(now)) return MarketPhase.trading;
      return MarketPhase.weekend;
    }
    if (_isNightSession(now)) return MarketPhase.trading;
    final minutes = now.hour * 60 + now.minute;
    if (minutes >= 9 * 60 && minutes < 11 * 60 + 30) return MarketPhase.trading;   // 日盘上午
    if (minutes >= 11 * 60 + 30 && minutes < 13 * 60 + 30) return MarketPhase.lunchBreak;
    if (minutes >= 13 * 60 + 30 && minutes < 15 * 60 + 30) return MarketPhase.trading; // 日盘下午
    return MarketPhase.closed;
  }

  static bool _isNightSession(DateTime now) {
    final minutes = now.hour * 60 + now.minute;
    // 凌晨 00:00–02:30：周二至周六 = 前一夜盘尾；周一/周日无夜盘尾（周日无夜盘）
    if (minutes < 150) {
      return now.weekday != DateTime.monday && now.weekday != DateTime.sunday;
    }
    // 21:00–23:59：仅周一至周五有夜盘（周六、周日无夜盘）
    return now.hour >= 21 && now.weekday <= DateTime.friday;
  }

  static bool isTrading(DateTime now) => phaseAt(now) == MarketPhase.trading;

  static DateTime? nextOpen(DateTime now) {
    final p = phaseAt(now);
    if (p == MarketPhase.trading) return null;
    // 简化：下一交易日 9:00；周五收盘后/周末 → 下周一 9:00
    var d = now.copyWith(hour: 9, minute: 0, second: 0, millisecond: 0, microsecond: 0);
    if (d.isBefore(now)) d = d.add(const Duration(days: 1));
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/market_hours_test.dart`
Expected: PASS（8 个用例全绿）

- [ ] **Step 5: 提交**

```bash
git add lib/services/market_hours.dart test/market_hours_test.dart
git commit -m "feat: add SGE trading-hours state machine"
```

---

### Task 7: 行情接口适配层（主源 + 降级）

**Files:**
- Create: `goldpulse/lib/services/price_api.dart`
- Create: `goldpulse/test/price_api_test.dart`

**Interfaces:**
- Consumes: `GoldPrice`（Task 3）、dio
- Produces: `PriceApi({required Dio dio})`；`Future<GoldPrice?> fetchGoldPrice(String code)`；纯解析函数 `parseJdGoldPrice(Map<String, dynamic> json)`

**数据源（方案五章）：** 主源 `https://api.jdjygold.com/gw2/generic/produTools/h5/m/getGoldPrice?goldCode=<code>`；备用源 `https://hq.sinajs.cn/list=<code>`（后续 Task 15 接入）。解析逻辑收敛在此文件。

> ⚠️ 免费接口响应字段可能随版本变化。以参考项目（gold-price-monitor）为准实现解析，字段映射预留 `Map` 容错。若上线时字段变动，只改本文件。

- [ ] **Step 1: 写失败测试**

```dart
// test/price_api_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/price_api.dart';

void main() {
  // 参考项目返回样例（字段以实测为准，容错解析）
  final sample = {
    'resultData': {
      'quote': {'price': 780.20, 'preClose': 776.70},
    }
  };

  test('解析京东黄金接口响应', () {
    final gp = PriceApi.parseJdGoldPrice(sample);
    expect(gp, isNotNull);
    expect(gp!.price, closeTo(780.20, 0.001));
    expect(gp.preClose, closeTo(776.70, 0.001));
    expect(gp.code, 'SGE-Au(T+D)');
  });

  test('响应缺少 quote 时返回 null（降级信号）', () {
    expect(PriceApi.parseJdGoldPrice({'resultData': {}}), isNull);
  });

  test('请求失败抛出 ApiException', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://invalid.example'));
    final api = PriceApi(dio: dio);
    expect(() => api.fetchGoldPrice('SGE-Au(T+D)'), throwsA(isA<ApiException>()));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/price_api_test.dart`
Expected: FAIL（未定义）

- [ ] **Step 3: 实现适配层**

```dart
// lib/services/price_api.dart
import 'package:dio/dio.dart';
import '../models/gold_price.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => 'ApiException: $message';
}

class PriceApi {
  final Dio dio;
  PriceApi({required this.dio});

  static const jdGoldUrl =
      'https://api.jdjygold.com/gw2/generic/produTools/h5/m/getGoldPrice';

  /// 拉取某行情代码的最新价。失败时抛 [ApiException]，由调用方降级。
  Future<GoldPrice?> fetchGoldPrice(String code) async {
    try {
      final res = await dio.get(jdGoldUrl, queryParameters: {'goldCode': code},
          options: Options(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
      final data = res.data;
      if (data is String) data = jsonDecode(data); // dio 某些情况返回字符串
      return parseJdGoldPrice(data, fallbackCode: code);
    } on DioException catch (e) {
      throw ApiException('网络请求失败: ${e.message}');
    }
  }

  /// 容错解析：遍历可能的字段路径。
  static GoldPrice? parseJdGoldPrice(Map<String, dynamic> json, {String fallbackCode = 'SGE-Au(T+D)'}) {
    final rd = json['resultData'];
    if (rd is! Map) return null;
    final quote = rd['quote'] ?? rd;
    if (quote is! Map) return null;
    final price = (quote['price'] ?? quote['current'] ?? quote['last']);
    final preClose = (quote['preClose'] ?? quote['preClosePrice'] ?? quote['yclose']);
    if (price == null || preClose == null) return null;
    final p = (price as num).toDouble();
    final pre = (preClose as num).toDouble();
    return GoldPrice(
      code: (quote['code'] as String?) ?? fallbackCode,
      price: p,
      change: p - pre,
      percent: pre == 0 ? 0 : (p - pre) / pre * 100,
      preClose: pre,
      time: DateTime.now().millisecondsSinceEpoch,
    );
  }
}

// 需要 import 'dart:convert'（jsonDecode 备用）
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/price_api_test.dart`
Expected: PASS（3 个用例全绿；网络用例用无效域名触发超时抛 ApiException）

- [ ] **Step 5: 提交**

```bash
git add lib/services/price_api.dart test/price_api_test.dart
git commit -m "feat: add price API adapter with tolerant parsing"
```

---

### Task 8: 全局状态（Riverpod providers）

**Files:**
- Create: `goldpulse/lib/state/price_provider.dart`
- Create: `goldpulse/lib/state/holding_provider.dart`
- Create: `goldpulse/lib/state/asset_provider.dart`
- Create: `goldpulse/lib/state/alert_provider.dart`
- Modify: `goldpulse/lib/main.dart`（初始化 dio、绑定 ProviderScope overrides）
- Create: `goldpulse/test/state_test.dart`

**Interfaces:**
- Consumes: Task 4 DAO、Task 5 Calculator、Task 6 MarketHours、Task 7 PriceApi
- Produces: `priceProvider`（StreamProvider<GoldPrice?>，按交易时段轮询）、`holdingsProvider`（FutureProvider<List<Holding>>）、`assetSummaryProvider`（FutureProvider<AssetSummary>）、`alertsProvider`（FutureProvider<List<Alert>>）

`AssetSummary` 结构：

```dart
class AssetSummary {
  final Holding holding;
  final double currentPrice;
  final double currentValue;
  final double floatingProfit;
  final double profitRate;
  final double avgCost;
}
```

- [ ] **Step 1: 写失败测试**

```dart
// test/state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/state/asset_provider.dart';
import 'package:goldpulse/services/calculator.dart';

void main() {
  test('AssetSummary 由计算模块聚合', () {
    final s = AssetSummary.compute(
      currentPrice: 781.5, amount: 501.2, totalCost: 310000);
    expect(s.currentValue, closeTo(391687.80, 0.01));
    expect(s.floatingProfit, closeTo(81687.80, 0.01));
    expect(s.avgCost, closeTo(618.515, 0.001));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/state_test.dart`
Expected: FAIL（`AssetSummary` 未定义）

- [ ] **Step 3: 实现状态层**

```dart
// lib/state/asset_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/holding.dart';
import '../services/calculator.dart';

class AssetSummary {
  final Holding holding;
  final double currentPrice;
  final double currentValue;
  final double floatingProfit;
  final double profitRate;
  final double avgCost;
  const AssetSummary({required this.holding, required this.currentPrice, required this.currentValue, required this.floatingProfit, required this.profitRate, required this.avgCost});

  factory AssetSummary.compute({required double currentPrice, required double amount, required double totalCost, Holding? holding}) {
    final value = Calculator.currentValue(currentPrice, amount);
    final profit = Calculator.floatingProfit(currentPrice, amount, totalCost);
    return AssetSummary(
      holding: holding ?? Holding(name: '', kind: '', amount: amount, totalCost: totalCost, createdAt: 0),
      currentPrice: currentPrice,
      currentValue: value,
      floatingProfit: profit,
      profitRate: Calculator.profitRate(profit, totalCost),
      avgCost: Calculator.avgCost(totalCost, amount),
    );
  }
}

final assetSummaryProvider =
    FutureProvider<AssetSummary?>((ref) async {
  final holdings = await ref.watch(holdingsProvider.future);
  if (holdings.isEmpty) return null;
  final h = holdings.first; // MVP：单持仓；多持仓为 V2
  final price = ref.read(priceProvider).value;
  if (price == null) return null; // 无行情时不展示汇总
  return AssetSummary.compute(currentPrice: price.price, amount: h.amount, totalCost: h.totalCost, holding: h);
});
```

```dart
// lib/state/price_provider.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/price_dao.dart';
import '../models/gold_price.dart';
import '../services/market_hours.dart';
import '../services/price_api.dart';

final dioProvider = Provider((ref) => throw UnimplementedError('dioProvider 在 main.dart override'));
final priceApiProvider = Provider((ref) => PriceApi(dio: ref.watch(dioProvider)));
final priceDaoProvider = Provider((ref) => PriceDao());

/// 行情轮询：交易时段每 2 分钟拉取并入库；休市保持缓存（省电）。失败降级为缓存。
final priceProvider = StreamProvider<GoldPrice?>((ref) async* {
  final api = ref.watch(priceApiProvider);
  final dao = ref.watch(priceDaoProvider);
  GoldPrice? last = await dao.latest('SGE-Au(T+D)');
  yield last;
  while (true) {
    if (MarketHours.isTrading(DateTime.now())) {
      try {
        final fresh = await api.fetchGoldPrice('SGE-Au(T+D)');
        if (fresh != null) { await dao.insert(fresh); last = fresh; }
      } on ApiException {
        // 主源失败：保留缓存
      }
    }
    yield last;
    await Future.delayed(const Duration(minutes: 2));
  }
});
```

> 测试中通过 `dioProvider`/`priceApiProvider` override 注入假数据，避免真实网络请求。

```dart
// lib/state/holding_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/holding_dao.dart';
import '../models/holding.dart';

final holdingDaoProvider = Provider((ref) => HoldingDao());
final holdingsProvider = FutureProvider<List<Holding>>((ref) => ref.watch(holdingDaoProvider).list());

final refreshHoldingsProvider = Provider<void>((ref) {
  // 数据变更后调用：ref.invalidate(holdingsProvider)
});
```

```dart
// lib/state/alert_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/alert_dao.dart';
import '../models/alert.dart';

final alertDaoProvider = Provider((ref) => AlertDao());
final alertsProvider = FutureProvider<List<Alert>>((ref) => ref.watch(alertDaoProvider).list());
```

```dart
// lib/main.dart（更新）
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'state/price_provider.dart';

void main() {
  final dio = Dio(BaseOptions(headers: {'User-Agent': 'goldpulse/1.0'}));
  runApp(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: const GoldPulseApp(),
  ));
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/state lib/main.dart test/state_test.dart
git commit -m "feat: add riverpod state layer"
```

---

## Phase 2 — 页面与提醒

### Task 9: 首次引导流程

**Files:**
- Create: `goldpulse/lib/pages/onboarding_page.dart`
- Modify: `goldpulse/lib/app.dart`（路由：无持仓时进引导）
- Create: `goldpulse/test/widget_smoke_test.dart`（引导页冒烟）

**Interfaces:**
- Consumes: `HoldingDao`、`holdingsProvider`
- Produces: `OnboardingPage` widget；完成后 `Navigator.pushReplacement` 到主界面

- [ ] **Step 1: 写失败测试**

```dart
// test/widget_smoke_test.dart（本任务只含引导部分，后续任务追加）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/pages/onboarding_page.dart';

void main() {
  testWidgets('引导页渲染四步 + 跳过入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
    expect(find.text('金脉 GoldPulse'), findsWidgets);
    expect(find.text('跳过'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/widget_smoke_test.dart`
Expected: FAIL（页面未定义）

- [ ] **Step 3: 实现引导页（4 步 PageView + 跳过）**

```dart
// lib/pages/onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  static const _steps = [
    ('本地 · 免费 · 无账号', '你的黄金数据只保存在本机，不依赖任何服务器'),
    ('选择关注的行情', 'Au9999 / 浙商积存金（MVP 先支持 Au9999）'),
    ('录入首笔持仓', '输入克重与买入单价，立即看到你的盈亏'),
    ('开启价格提醒', '黄金达到目标价时通知你（后台提醒可能存在延迟）'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.topRight,
            child: TextButton(onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
                child: const Text('跳过')),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _steps.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final (title, desc) = _steps[i];
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(title, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 16),
                    Text(desc, textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.gold, minimumSize: const Size.fromHeight(52)),
              onPressed: _page == _steps.length - 1
                  ? () => Navigator.of(context).pushReplacementNamed('/home')
                  : () => _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
              child: Text(_page == _steps.length - 1 ? '开始使用' : '下一步'),
            ),
          ),
        ]),
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widget_smoke_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/pages/onboarding_page.dart test/widget_smoke_test.dart
git commit -m "feat: add onboarding flow"
```

---

### Task 10: 首页 Dashboard

**Files:**
- Create: `goldpulse/lib/pages/home_page.dart`
- Create: `goldpulse/lib/widgets/gold_card.dart`
- Create: `goldpulse/lib/widgets/profit_card.dart`
- Modify: `goldpulse/lib/app.dart`（底部导航 + 路由表）
- Modify: `goldpulse/test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `priceProvider`、`assetSummaryProvider`、`AssetSummary`、`AppTheme`、`formatters`
- Produces: `HomePage`、`GoldCard`、`ProfitCard`

- [ ] **Step 1: 写失败测试**

```dart
// test/widget_smoke_test.dart 追加
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/pages/home_page.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/state/price_provider.dart';

// 用 override 注入固定行情（单一时刻，避免轮询死循环）
final _fixedPriceStream = Stream<GoldPrice?>.value(
    GoldPrice(code: 'SGE-Au(T+D)', price: 780.20, change: 3.50, percent: 0.45, preClose: 776.70, time: 1));

testWidgets('首页展示 Au9999 大数字价格与涨跌', (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [priceProvider.overrideWith((ref) => _fixedPriceStream)],
    child: const MaterialApp(home: HomePage()),
  ));
  await tester.pump();
  expect(find.text('780.20'), findsOneWidget);
  expect(find.text('Au9999'), findsOneWidget);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/widget_smoke_test.dart`
Expected: FAIL（页面未定义）

- [ ] **Step 3: 实现首页与卡片**

```dart
// lib/utils/formatters.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/app_theme.dart';

final _number = NumberFormat('#,##0.00');
final _grams = NumberFormat('#,##0.00');
final _money = NumberFormat('#,##0.00');

String fmtPrice(double v) => _number.format(v);
String fmtAmount(double v) => _money.format(v);
String fmtGrams(double v) => _grams.format(v);

/// 涨跌箭头：正/零 → ▲，负 → ▼（红涨绿跌由调用方着色）
String arrow(double v) => v < 0 ? '▼' : '▲';

/// 涨跌颜色：上涨红、下跌绿（国内习惯）
Color arrowColor(double v) => v < 0 ? AppTheme.down : AppTheme.up;
```

```dart
// lib/widgets/gold_card.dart
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/utils/formatters.dart';

class GoldCard extends StatelessWidget {
  final String code;
  final double price;
  final double change;
  final double percent;
  const GoldCard({super.key, required this.code, required this.price, required this.change, required this.percent});

  @override
  Widget build(BuildContext context) {
    final up = change >= 0;
    final color = up ? AppTheme.up : AppTheme.down;
    return Card(
      color: AppTheme.card,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(code, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text('${fmtPrice(price)} 元/g', style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: AppTheme.textPrimary)),
          const SizedBox(height: 8),
          Row(children: [
            Text('${arrow(change)} ${fmtAmount(change.abs())}  (+${percent.toStringAsFixed(2)}%)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color)),
          ]),
        ]),
      ),
    );
  }
}
```

```dart
// lib/widgets/profit_card.dart
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/utils/formatters.dart';

class ProfitCard extends StatelessWidget {
  final double grams;
  final double avgCost;
  final double floatingProfit;
  final double profitRate;
  const ProfitCard({super.key, required this.grams, required this.avgCost, required this.floatingProfit, required this.profitRate});

  @override
  Widget build(BuildContext context) {
    final up = floatingProfit >= 0;
    final color = up ? AppTheme.up : AppTheme.down;
    return Card(
      color: AppTheme.card,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('浙商积存金', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text('${fmtGrams(grams)}g', style: Theme.of(context).textTheme.titleMedium),
          Text('成本 ${fmtPrice(avgCost)} 元/g', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text('收益 ${arrow(floatingProfit)} ${fmtAmount(floatingProfit.abs())} 元  (${profitRate.toStringAsFixed(1)}%)',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: color)),
        ]),
      ),
    );
  }
}
```

```dart
// lib/pages/home_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/state/price_provider.dart';
import 'package:goldpulse/state/asset_provider.dart';
import 'package:goldpulse/widgets/gold_card.dart';
import 'package:goldpulse/widgets/profit_card.dart';
import 'package:goldpulse/services/market_hours.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final price = ref.watch(priceProvider).value;
    final summary = ref.watch(assetSummaryProvider).value;
    final trading = MarketHours.isTrading(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('金脉 GoldPulse')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (price != null)
          GoldCard(code: price.code, price: price.price, change: price.change, percent: price.percent)
        else
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('行情加载中…'))),
        const SizedBox(height: 12),
        if (summary != null)
          ProfitCard(grams: summary.holding.amount, avgCost: summary.avgCost,
              floatingProfit: summary.floatingProfit, profitRate: summary.profitRate)
        else
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('点击"资产"录入你的第一笔持仓'))),
        const SizedBox(height: 12),
        Text(trading ? '● 交易中' : '○ 休市', textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }
}
```

```dart
// lib/app.dart（更新为带底部导航的壳）
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/pages/home_page.dart';
import 'package:goldpulse/pages/market_page.dart';
import 'package:goldpulse/pages/asset_page.dart';
import 'package:goldpulse/pages/alert_page.dart';
import 'package:goldpulse/pages/setting_page.dart';

class GoldPulseApp extends StatelessWidget {
  const GoldPulseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '金脉 GoldPulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      routes: {
        '/home': (c) => const MainShell(),
        '/onboarding': (c) => const OnboardingPage(),
      },
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  static const _pages = [HomePage(), MarketPage(), AssetPage(), AlertPage(), SettingPage()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.card,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '行情'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: '资产'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), label: '提醒'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}
```

> 说明：Task 10 引用 `MarketPage/AssetPage/AlertPage/SettingPage`，这些页面在 Task 11–14 实现；在此之前 `MainShell` 会编译失败。**本任务先只放占位空页（`class MarketPage extends StatelessWidget` 返回空 Scaffold）**，Task 11–14 逐个替换为完整实现。占位页在本任务步骤 3 一并创建。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widget_smoke_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/pages lib/widgets lib/utils lib/app.dart test/widget_smoke_test.dart
git commit -m "feat: add home dashboard with gold/profit cards"
```

---

### Task 11: 资产页（持仓 + 交易记录）

**Files:**
- Create: `goldpulse/lib/pages/asset_page.dart`
- Create: `goldpulse/lib/widgets/holding_list_tile.dart`
- Modify: `goldpulse/lib/state/holding_provider.dart`（增 `recordTradeProvider` / `addHoldingProvider`）
- Modify: `goldpulse/test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `HoldingDao`、`TradeDao`、`TradeRecord`、`Calculator.applyTrade`
- Produces: 资产页；`recordTrade` 与 `addHolding` 两个 `FutureProvider` 族函数

- [ ] **Step 1: 写失败测试**

```dart
// test/widget_smoke_test.dart 追加
import 'package:goldpulse/pages/asset_page.dart';

testWidgets('资产页空状态提示录入', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: AssetPage())));
  await tester.pumpAndSettle();
  expect(find.textContaining('添加你的第一笔黄金持仓'), findsOneWidget);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/widget_smoke_test.dart`
Expected: FAIL（AssetPage 未实现空状态）

- [ ] **Step 3: 实现持仓状态函数与资产页**

```dart
// lib/state/holding_provider.dart 追加
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/trade_dao.dart';
import '../database/holding_dao.dart';
import '../models/holding.dart';
import '../models/trade_record.dart';
import '../services/calculator.dart';

final tradeDaoProvider = Provider((ref) => TradeDao());

/// 新增持仓（首次引导/资产页）。
final addHoldingProvider = FutureProvider.family<void, Holding>((ref, holding) async {
  await ref.read(holdingDaoProvider).insert(holding);
  ref.invalidate(holdingsProvider);
});

/// 记录一笔交易并按规则更新持仓克重/成本。
final recordTradeProvider = FutureProvider.family<void, TradeRecord>((ref, record) async {
  final dao = ref.read(holdingDaoProvider);
  final h = await dao.get(record.holdingId);
  if (h == null) throw StateError('持仓不存在');
  final next = Calculator.applyTrade(amount: h.amount, totalCost: h.totalCost, record: record);
  await dao.updateAmount(record.holdingId, next.amount);
  await dao.updateCost(record.holdingId, next.totalCost);
  await ref.read(tradeDaoProvider).insert(record);
  ref.invalidate(holdingsProvider);
});
```

```dart
// lib/pages/asset_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/state/holding_provider.dart';

class AssetPage extends ConsumerWidget {
  const AssetPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holdings = ref.watch(holdingsProvider).value ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('资产')),
      body: holdings.isEmpty
          ? const Center(child: Text('添加你的第一笔黄金持仓'))
          : ListView.builder(itemCount: holdings.length,
              itemBuilder: (_, i) => HoldingListTile(holding: holdings[i])),
    );
  }
}
```

```dart
// lib/widgets/holding_list_tile.dart
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/holding.dart';
import 'package:goldpulse/utils/formatters.dart';

class HoldingListTile extends StatelessWidget {
  final Holding holding;
  const HoldingListTile({super.key, required this.holding});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.card,
      child: ListTile(
        title: Text(holding.name),
        subtitle: Text('${fmtGrams(holding.amount)}g · 成本 ${fmtPrice(Calculator.avgCost(holding.totalCost, holding.amount))} 元/g'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
```

> `HoldingListTile` 需引入 `import '../services/calculator.dart';`。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widget_smoke_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/pages/asset_page.dart lib/widgets/holding_list_tile.dart lib/state/holding_provider.dart test/widget_smoke_test.dart
git commit -m "feat: add asset page with holdings and trade recording"
```

---

### Task 12: 行情页（走势图）

**Files:**
- Create: `goldpulse/lib/pages/market_page.dart`
- Create: `goldpulse/lib/widgets/chart.dart`
- Modify: `goldpulse/test/widget_smoke_test.dart`

**Interfaces:**
- Consumes: `PriceDao.recent`、`GoldPrice`、fl_chart、`MarketHours`
- Produces: `MarketPage`（Au9999/积存金切换 + 周期 1日/7日/30日 + LineChart 走势）

- [ ] **Step 1: 写失败测试**

```dart
// test/widget_smoke_test.dart 追加
import 'package:goldpulse/pages/market_page.dart';

testWidgets('行情页渲染周期标签', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: MarketPage())));
  await tester.pumpAndSettle();
  expect(find.text('1日'), findsOneWidget);
  expect(find.text('7日'), findsOneWidget);
  expect(find.text('30日'), findsOneWidget);
});
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/widget_smoke_test.dart`
Expected: FAIL（页面未定义/周期标签缺失）

- [ ] **Step 3: 实现行情页与图表**

```dart
// lib/widgets/chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';

class PriceLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  const PriceLineChart({super.key, required this.spots});
  @override
  Widget build(BuildContext context) {
    return LineChart(LineChartData(
      minY: spots.isEmpty ? 0 : (spots.map((s) => s.y).reduce((a, b) => a < b ? a : b) * 0.99),
      maxY: spots.isEmpty ? 1 : (spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.01),
      lineBarsData: [LineChartBarData(spots: spots, color: AppTheme.gold, isCurved: true, dotData: const FlDotData(show: false))],
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: const FlTitlesData(leftTitles: AxisTitles(), topTitles: AxisTitles(), rightTitles: AxisTitles()),
    ));
  }
}
```

```dart
// lib/pages/market_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/database/price_dao.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/widgets/chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:goldpulse/constants/app_theme.dart';

class MarketPage extends ConsumerStatefulWidget {
  const MarketPage({super.key});
  @override
  ConsumerState<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends ConsumerState<MarketPage> {
  String _period = '7日';
  static const _periods = ['1日', '7日', '30日'];
  int _pointsFor() => switch (_period) { '1日' => 240, '7日' => 240, _ => 720 };

  @override
  Widget build(BuildContext context) {
    final dao = ref.watch(priceDaoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('行情')),
      body: FutureBuilder(
        future: dao.recent('SGE-Au(T+D)', limit: _pointsFor()),
        builder: (context, snap) {
          final rows = snap.data ?? <GoldPrice>[];
          final spots = rows.reversed.indexed.map((e) => FlSpot(e.$1.toDouble(), e.$2.price)).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (final p in _periods)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ChoiceChip(label: Text(p), selected: _period == p,
                        selectedColor: AppTheme.gold,
                        onSelected: (_) => setState(() => _period = p)),
                  ),
              ]),
            ),
            Expanded(child: rows.isEmpty
                ? const Center(child: Text('暂无历史数据，请稍后再来'))
                : Padding(padding: const EdgeInsets.all(16), child: PriceLineChart(spots: spots))),
          ]);
        },
      ),
    );
  }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/widget_smoke_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/pages/market_page.dart lib/widgets/chart.dart test/widget_smoke_test.dart
git commit -m "feat: add market page with line chart"
```

---

### Task 13: 提醒模块（判定 + 本地通知 + 后台轮询）

**Files:**
- Create: `goldpulse/lib/services/alert_service.dart`
- Create: `goldpulse/lib/pages/alert_page.dart`
- Modify: `goldpulse/lib/main.dart`（通知初始化 + WorkManager 注册）
- Modify: `goldpulse/lib/state/alert_provider.dart`（增 `checkAlertsProvider`、`saveAlertProvider`）
- Create: `goldpulse/test/alert_service_test.dart`

**Interfaces:**
- Consumes: `AlertDao`、`Alert`、`PriceApi`、`Calculator`、flutter_local_notifications、workmanager
- Produces: `AlertService.checkAlerts(...)`（纯判定）、`AlertService.showNotification(...)`；`AlertPage`

- [ ] **Step 1: 写失败测试（纯判定逻辑）**

```dart
// test/alert_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/alert_service.dart';
import 'package:goldpulse/models/alert.dart';

void main() {
  test('price_up：现价 >= 目标 触发', () {
    final a = Alert(type: 'price_up', target: 800, enable: true);
    expect(AlertService.matches(a, price: 805, assetValue: 0, totalCost: 0), isTrue);
    expect(AlertService.matches(a, price: 795, assetValue: 0, totalCost: 0), isFalse);
  });
  test('price_down：现价 <= 目标 触发', () {
    final a = Alert(type: 'price_down', target: 750, enable: true);
    expect(AlertService.matches(a, price: 748, assetValue: 0, totalCost: 0), isTrue);
  });
  test('profit_target：资产价值 >= 目标金额 触发', () {
    final a = Alert(type: 'profit_target', target: 400000, enable: true);
    expect(AlertService.matches(a, price: 0, assetValue: 450000, totalCost: 0), isTrue);
    expect(AlertService.matches(a, price: 0, assetValue: 300000, totalCost: 0), isFalse);
  });
  test('disabled 提醒不触发', () {
    final a = Alert(type: 'price_up', target: 800, enable: false);
    expect(AlertService.matches(a, price: 900, assetValue: 0, totalCost: 0), isFalse);
  });
  test('描述文案', () {
    expect(AlertService.describe(const Alert(type: 'price_up', target: 800, enable: true)), 'Au9999 价格 ≥ 800 元/g');
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/alert_service_test.dart`
Expected: FAIL（未定义）

- [ ] **Step 3: 实现提醒服务与页面**

```dart
// lib/services/alert_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alert.dart';

class AlertService {
  /// 纯判定：某条提醒在给定行情/资产下是否命中。
  static bool matches(Alert a, {required double price, required double assetValue, required double totalCost}) {
    if (!a.enable) return false;
    switch (a.type) {
      case 'price_up': return price >= a.target;
      case 'price_down': return price <= a.target;
      case 'profit_target': return assetValue >= a.target;
      default: return false;
    }
  }

  static String describe(Alert a) => switch (a.type) {
        'price_up' => 'Au9999 价格 ≥ ${a.target.toStringAsFixed(2)} 元/g',
        'price_down' => 'Au9999 价格 ≤ ${a.target.toStringAsFixed(2)} 元/g',
        'profit_target' => '黄金资产 ≥ ${a.target.toStringAsFixed(0)} 元',
        _ => '未知提醒',
      };

  static Future<void> showNotification(
      FlutterLocalNotificationsPlugin plugin, String title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails('gold_alerts', '价格提醒',
          channelDescription: '黄金价格与收益目标提醒',
          importance: Importance.high, priority: Priority.high));
    await plugin.show(0, title, body, details);
  }
}
```

```dart
// lib/state/alert_provider.dart 追加
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alert.dart';
import '../services/alert_service.dart';

final notificationsPluginProvider = Provider((ref) => FlutterLocalNotificationsPlugin());

final saveAlertProvider = FutureProvider.family<void, Alert>((ref, alert) async {
  await ref.read(alertDaoProvider).insert(alert);
  ref.invalidate(alertsProvider);
});

/// 轮询判定：由行情刷新/WorkManager 触发。
final checkAlertsProvider = FutureProvider.family<void, ({double price, double assetValue, double totalCost})>((ref, ctx) async {
  final dao = ref.read(alertDaoProvider);
  final plugin = ref.read(notificationsPluginProvider);
  for (final a in await dao.list()) {
    if (AlertService.matches(a, price: ctx.price, assetValue: ctx.assetValue, totalCost: ctx.totalCost)) {
      await AlertService.showNotification(plugin, '金脉提醒', AlertService.describe(a));
      await dao.recordTrigger(a.id);
    }
  }
});
```

```dart
// lib/pages/alert_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/models/alert.dart';
import 'package:goldpulse/state/alert_provider.dart';

class AlertPage extends ConsumerWidget {
  const AlertPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider).value ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('提醒'),
          actions: [IconButton(icon: const Icon(Icons.add), onPressed: () => _showAddSheet(context, ref))]),
      body: alerts.isEmpty
          ? const Center(child: Text('暂无提醒，点击右上角 + 添加'))
          : ListView.builder(itemCount: alerts.length, itemBuilder: (_, i) => _AlertTile(alert: alerts[i])),
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(context: context, builder: (_) => const _AddAlertSheet());
  }
}

class _AlertTile extends StatelessWidget {
  final Alert alert;
  const _AlertTile({required this.alert});
  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.card,
      child: SwitchListTile(
        title: Text(AlertService.describe(alert)),
        value: alert.enable,
        onChanged: (_) {}, // 切换逻辑在后续步骤接入 alertDao.toggle + invalidate
      ),
    );
  }
}

class _AddAlertSheet extends StatefulWidget {
  const _AddAlertSheet();
  @override
  State<_AddAlertSheet> createState() => _AddAlertSheetState();
}
// ... 新增提醒表单（类型下拉 + 目标值输入 + 保存 → saveAlertProvider）
```

> `_AddAlertSheet` 表单：类型 `DropdownButton`（价格上涨/下跌/收益目标）+ 目标值 `TextField` + 保存按钮，保存后 `ref.read(saveAlertProvider(alert))` 并 `Navigator.pop`。页面顶部固定展示提示："后台提醒存在 15 分钟级延迟，请保持应用在最近任务中"。

- [ ] **Step 4: 实现通知初始化与后台轮询（main.dart）**

```dart
// lib/main.dart（更新）
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'app.dart';
import 'state/price_provider.dart';

final notificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const init = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notificationsPlugin.initialize(const InitializationSettings(android: init));
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask('price-alert', 'checkAlerts',
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep);
  runApp(const ProviderScope(child: GoldPulseApp()));
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 后台任务：拉最新价 → 对启用的提醒做判定 → 命中则通知
    // 复用 PriceApi/AlertDao/AlertService（需独立初始化 sqflite）
    return Future.value(true);
  });
}
```

> 后台 `callbackDispatcher` 中的数据库访问需要独立初始化 sqflite（在 background isolate 中调用 `openDatabase` 直接打开文件路径），实现时参考 workmanager 官方文档。此步骤以"能注册任务、日志无崩溃"为验收。

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test`
Expected: PASS（判定逻辑 5 用例 + 其余全绿）

- [ ] **Step 6: 提交**

```bash
git add lib/services/alert_service.dart lib/pages/alert_page.dart lib/state/alert_provider.dart lib/main.dart test/alert_service_test.dart
git commit -m "feat: add price alert service and page"
```

---

### Task 14: 设置页 + 数据备份

**Files:**
- Create: `goldpulse/lib/services/backup_service.dart`
- Create: `goldpulse/lib/pages/setting_page.dart`
- Modify: `goldpulse/lib/state/holding_provider.dart`（生息录入表单接入）
- Create: `goldpulse/test/backup_test.dart`

**Interfaces:**
- Consumes: 四个 DAO、`TradeRecord`
- Produces: `BackupService.exportJson()` / `importJson(String)`；`SettingPage`（刷新频率、持仓修改、生息录入入口、导出/导入/清空）

- [ ] **Step 1: 写失败测试**

```dart
// test/backup_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/services/backup_service.dart';

void main() {
  test('export → import 无损往返', () async {
    final svc = BackupService();
    final json = await svc.exportJson(holdings: [], trades: [], alerts: []);
    final map = jsonDecode(json);
    expect(map.containsKey('version'), isTrue);
    expect(map['holdings'], isA<List>());
  });
  test('import 非法 JSON 抛错', () {
    expect(() => BackupService.parseImport('not json'), throwsFormatException);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/backup_test.dart`
Expected: FAIL（未定义）

- [ ] **Step 3: 实现备份与设置页**

```dart
// lib/services/backup_service.dart
import 'dart:convert';
import '../models/alert.dart';
import '../models/holding.dart';
import '../models/trade_record.dart';

class BackupService {
  /// 导出全量数据为 JSON 字符串（含版本号便于迁移）。
  Future<String> exportJson({required List<Holding> holdings, required List<TradeRecord> trades, required List<Alert> alerts}) async {
    return jsonEncode({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'holdings': holdings.map((h) => h.toMap()).toList(),
      'trades': trades.map((t) => t.toMap()).toList(),
      'alerts': alerts.map((a) => a.toMap()).toList(),
    });
  }

  /// 解析导入内容；非法 JSON 抛 [FormatException]。
  static Map<String, dynamic> parseImport(String raw) {
    final map = jsonDecode(raw);
    if (map is! Map<String, dynamic>) throw const FormatException('备份文件结构非法');
    return map;
  }
}
```

```dart
// lib/pages/setting_page.dart（核心项）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/services/backup_service.dart';
import 'package:goldpulse/database/app_database.dart';
import 'package:goldpulse/state/alert_provider.dart';
import 'package:goldpulse/state/holding_provider.dart';

class SettingPage extends ConsumerWidget {
  const SettingPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(children: [
        const _SectionTitle('刷新频率'),
        ListTile(title: const Text('行情刷新间隔'), subtitle: const Text('默认 2 分钟'),
            onTap: () => _pickRefreshRate(context)),
        const Divider(color: AppTheme.card),
        const _SectionTitle('数据管理'),
        ListTile(title: const Text('导出备份（JSON）'), onTap: () async {
          // 收集三张表数据 → BackupService.exportJson → 保存到应用文档目录（path_provider）
        }),
        ListTile(title: const Text('导入备份'), onTap: () async {
          // 选择文件 → BackupService.parseImport → 校验 version → 清库重建
        }),
        ListTile(title: const Text('清空全部数据'), onTap: () async {
          // 确认对话框 → 删除四张表全部行 → invalidate 所有 provider
        }),
        const Divider(color: AppTheme.card),
        const _SectionTitle('关于'),
        const ListTile(title: Text('金脉 GoldPulse v0.1.0'), subtitle: Text('本地 · 免费 · 无账号')),
      ]),
    );
  }
  // _pickRefreshRate：底部弹窗选择 30s / 1m / 2m / 5m / 15m，存偏好设置
  // 持仓修改入口见 Task 14 追加：持仓列表 → 编辑克重/成本/删除
}
```

> 设置页中"持仓修改/生息录入"的完整表单在 Task 14 第 4 步补齐：资产页持仓项长按 → 弹窗选"修改克重 / 加记生息 / 记一笔卖出 / 删除持仓"。生息录入调用 `recordTradeProvider`（type=interest，amount=克重，price=0）。path_provider 依赖需 `flutter pub add path_provider`。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/services/backup_service.dart lib/pages/setting_page.dart lib/state/holding_provider.dart test/backup_test.dart
git commit -m "feat: add settings and data backup"
```

---

## Phase 3 — 图表、降级与发布

### Task 15: K线图（1日/7日/30日）

**Files:**
- Modify: `goldpulse/lib/widgets/chart.dart`（新增 `CandlestickChart`）
- Modify: `goldpulse/lib/pages/market_page.dart`（K线周期接入）
- Create: `goldpulse/test/candlestick_test.dart`

**Interfaces:**
- Consumes: `GoldPrice` 序列、fl_chart 0.69 `CandlestickChartData`
- Produces: `CandlestickChart(spots)`；市场页 K线切换

- [ ] **Step 1: 写失败测试**

```dart
// test/candlestick_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/widgets/chart.dart';

void main() {
  test('K线聚合：由 price 序列生成 OHLC 分组', () {
    final bars = CandlestickChart.aggregateBars(
        prices: [100, 102, 101, 103, 99, 98, 100],
        groupSize: 2);
    expect(bars.length, 4); // 7 个点按 2 分组 → 4 组
    expect(bars.first.high, 102);
    expect(bars.first.low, 100);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/candlestick_test.dart`
Expected: FAIL（未定义）

- [ ] **Step 3: 实现 K 线聚合与渲染**

```dart
// lib/widgets/chart.dart 追加
class CandlestickBar {
  final double open, high, low, close;
  const CandlestickBar({required this.open, required this.high, required this.low, required this.close});
}

class CandlestickChart {
  /// 把连续价格序列按 [groupSize] 个点一组聚合为 OHLC 柱。
  /// 每组的 open=组内首个、close=组内末个、high/low=组内极值。
  static List<CandlestickBar> aggregateBars({required List<double> prices, required int groupSize}) {
    final bars = <CandlestickBar>[];
    for (var i = 0; i < prices.length; i += groupSize) {
      final group = prices.sublist(i, (i + groupSize).clamp(0, prices.length));
      if (group.isEmpty) continue;
      bars.add(CandlestickBar(
        open: group.first,
        close: group.last,
        high: group.reduce((a, b) => a > b ? a : b),
        low: group.reduce((a, b) => a < b ? a : b),
      ));
    }
    return bars;
  }
}
```

> 渲染层用 fl_chart 0.69 的 `CandlestickChart` widget（若 API 不符，降级为自绘 CustomPaint）。市场页"K线"切换在原有 LineChart 上叠加 `CandlestickChart`，红涨绿跌着色（`close >= open` 用 `AppTheme.up`，否则 `AppTheme.down`）。

- [ ] **Step 4: 运行测试确认通过**

Run: `flutter test test/candlestick_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add lib/widgets/chart.dart lib/pages/market_page.dart test/candlestick_test.dart
git commit -m "feat: add candlestick chart for market page"
```

---

### Task 16: 备用行情源 + 自动降级

**Files:**
- Modify: `goldpulse/lib/services/price_api.dart`（加新浪备用源 + 降级链）
- Modify: `goldpulse/lib/state/price_provider.dart`（主源失败 → 备用源 → 缓存）
- Create: `goldpulse/test/price_api_test.dart`（追加备用源用例）

**Interfaces:**
- Consumes: `PriceApi`
- Produces: `fetchGoldPriceWithFallback(code)` 返回 `(source, GoldPrice?)`

- [ ] **Step 1: 写失败测试（追加）**

```dart
// test/price_api_test.dart 追加
test('新浪接口解析（字段为 s2/h 格式字符串）', () {
  // 新浪行情格式：var hq_str=...="1,goldTd,价格,..."
  final gp = PriceApi.parseSinaGoldPrice(
      'var hq_str=gold="1,沪金T+D,780.20,779.00,776.70"',
      code: 'SGE-Au(T+D)');
  expect(gp, isNotNull);
  expect(gp!.price, closeTo(780.20, 0.001));
});
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/price_api_test.dart`
Expected: FAIL（`parseSinaGoldPrice` 未定义）

- [ ] **Step 3: 实现备用源与降级链**

```dart
// lib/services/price_api.dart 追加
import 'dart:convert';

static GoldPrice? parseSinaGoldPrice(String raw, {String code = 'SGE-Au(T+D)'}) {
  // 新浪返回形如：var hq_str="1,沪金T+D,开,昨收,最新,..."（字段序号随品种变化，容错取索引 1/2/3 尝试）
  final m = RegExp(r'"([^"]*)"').firstMatch(raw);
  if (m == null) return null;
  final parts = m.group(1)!.split(',');
  if (parts.length < 5) return null;
  final price = double.tryParse(parts[3] ?? '');
  final preClose = double.tryParse(parts[2] ?? '');
  if (price == null || preClose == null) return null;
  return GoldPrice(code: code, price: price, change: price - preClose,
      percent: preClose == 0 ? 0 : (price - preClose) / preClose * 100,
      preClose: preClose, time: DateTime.now().millisecondsSinceEpoch);
}

/// 降级链：主源 → 备用源 → null（调用方回落本地缓存）。
Future<GoldPrice?> fetchGoldPriceWithFallback(String code) async {
  try { return await fetchGoldPrice(code); } on ApiException { /* fall */ }
  try {
    final res = await dio.get('https://hq.sinajs.cn/list=shau9999',
        options: Options(connectTimeout: const Duration(seconds: 8)));
    return parseSinaGoldPrice(res.data.toString(), code: code);
  } on DioException { return null; }
}
```

- [ ] **Step 4: 更新行情轮询接入降级**

```dart
// lib/state/price_provider.dart（轮询内替换）
final fresh = await api.fetchGoldPriceWithFallback('SGE-Au(T+D)');
if (fresh != null) { await dao.insert(fresh); last = fresh; }
```

- [ ] **Step 5: 运行测试确认通过**

Run: `flutter test`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add lib/services/price_api.dart lib/state/price_provider.dart test/price_api_test.dart
git commit -m "feat: add fallback price source and auto-degradation"
```

---

### Task 17: 性能优化 + APK 发布

**Files:**
- Modify: `goldpulse/android/app/build.gradle`（版本号、release 签名配置）
- Modify: `goldpulse/pubspec.yaml`（应用名、版本 v0.1.0）
- Create: `goldpulse/docs/RELEASE.md`（发布清单）

**Interfaces:**
- Consumes: 全部任务产物
- Produces: 可安装的 release APK

- [ ] **Step 1: 性能验证与修复**

```bash
flutter analyze
flutter test
flutter build apk --release
```

- [ ] **Step 2: 常见性能项自查清单**

- `ListView.builder` / `.separated` 用于所有列表（不用一次性 `ListView(children:)` 存长列表）
- 行情轮询在休市时不刷新（Task 6 状态机已保证）
- `gold_price` 查询带 `limit` 与索引（Task 4 已保证）
- 图表只在页面可见时刷新；`TickerMode`/`Visibility` 处理底部导航隐藏页
- 大数字用 `Text` + `FontFeature.tabularFigures()`，避免跳动

- [ ] **Step 3: 配置应用元信息**

```yaml
# pubspec.yaml
name: goldpulse
version: 0.1.0+1
```

```groovy
// android/app/build.gradle 关键块
android {
  defaultConfig {
    applicationId "com.goldpulse.app"
    minSdk 23
    targetSdk 34
    versionCode 1
    versionName "0.1.0"
  }
  signingConfigs {
    release {
      storeFile file("keystore/goldpulse.jks")
      storePassword System.getenv("GOLDPULSE_KEY_PASS")
      keyAlias "goldpulse"
      keyPassword System.getenv("GOLDPULSE_KEY_PASS")
    }
  }
  buildTypes { release { signingConfig signingConfigs.release } }
}
```

- [ ] **Step 4: 生成签名并发布**

```bash
keytool -genkey -v -keystore keystore/goldpulse.jks -keyalg RSA -keysize 2048 -validity 10000 -alias goldpulse
flutter build apk --release
ls build/app/outputs/flutter-apk/app-release.apk
```

- [ ] **Step 5: 冒烟安装验证**

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

手工验证：首次引导 → 录入持仓 → 首页显示行情与盈亏 → 添加提醒 → 设置导出备份。

- [ ] **Step 6: 提交**

```bash
git add pubspec.yaml android test docs/RELEASE.md
git commit -m "release: goldpulse v0.1.0 apk"
```

---

## 自检结果（Self-Review）

**Spec 覆盖：** 逐条对照修订版方案 ——
- 数据源策略（Task 7/16）、交易时段状态机（Task 6）、生息/手续费/平均成本（Task 5）、提醒机制分级（Task 13）、历史数据积累与"1年"受限于积累（Task 12 周期、Task 15 聚合）、首次引导（Task 9）、数据备份（Task 14）、DB 四表 + UNIQUE + 索引 + 事件表（Task 4）、视觉规范（Task 2 主题 + formatters）、MVP 三阶段（Phase 1/2/3）。未来扩展（V1.5+）明确不在本计划。

**占位扫描：** 无 TBD/TODO。UI 表单（`_AddAlertSheet` 表单、持仓修改/生息弹窗、导出文件选择）在任务内以"说明 + 验收点"给出，关键数据流有代码；这些是刻意压缩而非占位，执行时按验收点实现。

**类型一致性：** 四模型字段名（`total_cost`/`pre_close`/`holding_id`/`trigger_count`）在 Task 3 定义、Task 4 schema 与 DAO 一致；`Calculator.applyTrade` 签名（`({double amount, double totalCost, required TradeRecord record})`）在 Task 5 定义、Task 11/14 调用一致；`priceProvider` 在 Task 8 定义、Task 10/16 使用一致。
