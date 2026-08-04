# 金脉 GoldPulse

> 黄金积存金行情与持仓管理 App（Android · Flutter）

本地优先的黄金小助手：实时关注 **Au9999 / 浙商积存金 / 工商积存金** 三个品种的行情，录入持仓后自动计算**持仓收益 / 今日盈亏 / 累计收益**三口径盈亏，价格达标时本地通知提醒。

全部数据保存在本机 —— **无账号、无服务器、无广告**。

---

## ✨ 功能特性

### 行情
- **三品种实时价**：Au9999（上海金）、浙商积存金、工商积存金
- **行情页**：三品种一键切换 + 双轴走势图（折线 / K线）+ **当日统计**（当日最高 / 最低 / 开盘 / 昨收）
- **刷新频率可调**：1s / 5s / 10s / 30s / 1min / 2min / 5min / 15min，**收盘时段同样持续刷新**（银行积存金收盘后价格仍会变动）
- **多级数据源降级**：京东金融 → 东方财富 → 新浪 → 本地缓存，卡片实时标注当前数据源

### 持仓与收益
- 录入持仓（克重 + 买入单价），支持积存金 / Au9999 / 工商积存金 类型
- **三口径收益**：
  - 持仓收益 = 现价 × 克重 − 总成本
  - 今日盈亏 = (现价 − 昨收) × 克重
  - 累计收益 = 已实现（卖出净得）+ 当前浮盈
- 长按持仓：修改克重 / 加记生息 / 记一笔卖出（0.4% 手续费）/ 删除

### 提醒
- 价格上涨 / 价格下跌 / 收益目标 三类提醒，命中即本地通知
- 前台行情轮询即时判定；后台 WorkManager 定时检查

### 其他
- 首次引导页；数据导出 / 导入备份（JSON）
- 深色黑金主题（Dark Mode / OLED 友好），红涨绿跌（国内习惯）

---

## 🔌 数据源

| 品种 | 主源 | 备用降级 |
|---|---|---|
| Au9999 | 京东金融 `getGoldPrice?goldCode=SGE-Au(T+D)` | 东方财富 → 新浪 → 缓存 |
| 浙商积存金 | 京东金融 `getGoldPrice?goldCode=CZB-JCJ` | 东方财富参考 → 新浪 → 缓存 |
| 工商积存金 | 京东金融 `getGoldPrice?goldCode=ICBC-JCJ` | 东方财富参考 → 新浪 → 缓存 |

- 全部品种统一走京东金融免费接口 `api.jdjygold.com/gw2/generic/produTools/h5/m/getGoldPrice`（按 `uniqueCode`），一个接口自带当日最高/最低/开盘/昨收字段
- 免费接口稳定性有限：应用做了 **30 秒快速重试** + **本地缓存兜底**；新浪接口在该网络下无有效实时数据，仅作最后兜底

---

## 🛠 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.44 / Dart 3.12（Android targetSdk 36，适配 Android 15+ / 16KB 页） |
| 状态管理 | flutter_riverpod 2.x（StreamProvider 行情轮询 / FutureProvider 资产汇总） |
| 网络 | dio（超时 8s，多源降级链） |
| 本地存储 | sqflite（行情历史 / 持仓 / 交易 / 提醒）+ shared_preferences（偏好） |
| 通知 | flutter_local_notifications + workmanager（后台轮询） |
| 图表 | fl_chart（折线图）+ CustomPaint（K 线，红涨实心 / 绿跌空心） |
| 字体 | IBM Plex Sans（本地打包 4 字重） |

---

## 📁 项目结构

```
goldpulse/lib/
├── main.dart                  # 入口：通知初始化 + WorkManager 注册 + dio 注入
├── app.dart                   # MaterialApp + 启动门控（引导）+ 底部导航
├── constants/app_theme.dart   # 黑金主题 token（深海军蓝 + 高级金）
├── pages/                     # 首页 / 行情 / 资产 / 提醒 / 设置 / 引导
│   ├── home_page.dart         #   三行情卡 + 三口径收益卡 + 刷新倒计时
│   ├── market_page.dart       #   三品种切换 + 区间/当日统计 + 双轴图表
│   ├── asset_page.dart        #   持仓列表（三口径）+ 添加/编辑
│   ├── alert_page.dart        #   提醒列表 + 添加表单（内联校验）
│   ├── setting_page.dart      #   刷新频率 / 备份 / 关于
│   └── onboarding_page.dart   #   首次引导（图标 + 指示点）
├── widgets/                   # 行情卡 / 收益卡 / K线图 / 持仓项 / 空态
├── state/                     # Riverpod providers（行情 / 汇总 / 持仓 / 提醒 / 引导）
├── services/                  # 行情 API（多源降级）/ 交易时段 / 收益计算 / 提醒服务
├── models/                    # 数据模型（GoldPrice / Holding / TradeRecord / Alert）
├── database/                  # sqflite DAO（v2 schema：含日线字段）
└── utils/formatters.dart      # 金额 / 克重格式化，红涨绿跌
```

---

## 🔨 构建与运行

**前置**：Flutter 3.44+（Dart 3.12）、Android SDK 36。

```bash
# 国内镜像（可选，加速依赖下载）
export FLUTTER_STORAGE_BASE_URL=https://mirror.nju.edu.cn/flutter
export PUB_HOSTED_URL=https://pub.flutter-io.cn

# 调试
cd goldpulse && flutter run

# 发布构建（需签名 keystore 与口令环境变量 GOLDPULSE_KEY_PASS）
cd goldpulse && flutter build apk --release
```

APK 输出：`goldpulse/build/app/outputs/flutter-apk/app-release.apk`

---

## ⚠️ 已知事项

- **正式包必须声明 INTERNET 权限**：主 `AndroidManifest.xml` 需包含 `<uses-permission android:name="android.permission.INTERNET"/>`（曾因缺失导致 release 版完全无法联网，仅 debug 可用）。
- 免费行情接口为非官方源，可能间歇性不稳定；应用会自动降级并用本地缓存兜底，卡片会标注「数据源」。
- 银行积存金在 SGE 收盘后价格仍可能变动，因此应用按设定间隔**持续刷新**，不做交易时段门控；「已收盘」仅作状态提示。
- Windows 下若系统 PATH 被污染，`flutter` 命令可能报错（可用修正后的 PATH 运行，见 `goldpulse/analyze_run.bat` 思路）。

---

## 📎 相关文档

- 产品方案：`金脉_GoldPulse_App产品方案_v1.0.md`
- UI 设计稿（HTML 可视化）：`docs/ui-mockup.html`
- 界面重构方案：`docs/app-redesign-v2.md`、`docs/market-page-redesign-v2.md`

---

## 📄 许可

私人项目，仅供学习交流使用。行情数据来源于公开免费接口，请勿用于商业用途。
