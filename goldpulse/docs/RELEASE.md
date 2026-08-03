# 金脉 GoldPulse 发布清单（Release Checklist）

本文档面向 MVP v0.1.0 的 APK 发布与重新构建。所有命令在 `goldpulse/` 项目根目录执行。

## 0. 前提（Prerequisites）

- Flutter stable（本项目锁定 3.44.x，Dart 3.12.x）
- JDK 17（构建/签名用；keytool 随 JDK 提供）
- Android SDK（`android/local.properties` 的 `sdk.dir` 指向本机 SDK）
- 中国网络环境：每个用到 `flutter` / `pub` 的终端先导出镜像源

```bash
export FLUTTER_STORAGE_BASE_URL=https://mirror.nju.edu.cn/flutter
export PUB_HOSTED_URL=https://pub.flutter-io.cn
```

## 1. 版本号

版本单一来源：`pubspec.yaml`

```yaml
name: goldpulse
version: 0.1.0+1   # versionCode 1 / versionName "0.1.0"
```

`android/app/build.gradle.kts` 通过 `flutter.versionCode` / `flutter.versionName` 读取该值，勿在 gradle 里单独改版本号。

## 2. 发布签名密钥库（keystore）

密钥库路径：`android/keystore/goldpulse.jks`（**已被 `.gitignore` 忽略，禁止入库**，请自行备份）。

生成（首次或重建密钥库时执行一次）：

```bash
mkdir -p android/keystore
keytool -genkeypair -v -keystore android/keystore/goldpulse.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias goldpulse \
  -storepass "$GOLDPULSE_KEY_PASS" -keypass "$GOLDPULSE_KEY_PASS" \
  -dname "CN=GoldPulse, OU=Dev, O=GoldPulse, L=Hangzhou, ST=Zhejiang, C=CN"
```

### 环境变量 `GOLDPULSE_KEY_PASS`（必须）

`android/app/build.gradle.kts` 的 release `signingConfig` 通过
`System.getenv("GOLDPULSE_KEY_PASS")` 读取 storePassword/keyPassword。

**构建 release APK 前必须在同一终端导出该变量，否则 release 构建会失败：**

```bash
export GOLDPULSE_KEY_PASS='<你选定的密码>'
```

注意：
- 该变量只是终端会话级，不写进任何提交到 git 的文件。
- 忘记密码 = 无法用同一密钥库再次签名发布。请把密钥库文件 + 密码备份到安全位置。
- 升级密钥库到标准格式（可选）：`keytool -importkeystore -srckeystore android/keystore/goldpulse.jks -destkeystore android/keystore/goldpulse.jks -deststoretype pkcs12`

## 3. 构建

```bash
# 0) 环境（必做）
export FLUTTER_STORAGE_BASE_URL=https://mirror.nju.edu.cn/flutter
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export GOLDPULSE_KEY_PASS='<你选定的密码>'

# 1) 静态检查 + 测试
flutter analyze
flutter test            # 期望 58+ 全部通过

# 2) Debug（日常）
flutter build apk --debug

# 3) Release（发布产物）
flutter build apk --release
ls -la build/app/outputs/flutter-apk/app-release.apk
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

### 中国大陆网络镜像说明

- Dart/Flutter 依赖走 `mirror.nju.edu.cn` / `pub.flutter-io.cn`（上面的导出）。
- Gradle 分发（`gradle-9.1.0-all.zip`）首次会从 `services.gradle.org` 下载，
  本机已缓存于 `~/.gradle/wrapper/dists`。若在新机器上首次构建卡在 Gradle/Maven
  下载，可：
  1. 把 `android/gradle/wrapper/gradle-wrapper.properties` 的
     `distributionUrl` 换成国内镜像（如腾讯/阿里 `mirrors.cloud.tencent.com/gradle/...`）；
  2. 在 `android/build.gradle.kts` / `android/settings.gradle.kts` 的
     `repositories` 中追加腾讯 Maven 镜像（`https://mirrors.cloud.tencent.com/nexus/repository/maven-public/`）。
  Task 17 构建时 `~/.gradle/caches/modules-2` 已 1.7G 且 Gradle 9.1.0 已缓存，
  未需要加镜像即成功；以上为「网络异常时的回退方案」，若将来改动则在此记录。

## 4. 冒烟安装验证（有设备时）

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

手工冒烟流程：
1. 首次引导：4 步引导页可跳过 → 进入首页。
2. 录入持仓：资产页「添加你的第一笔黄金持仓」→ 输入克重与买入价 → 首页显示行情与盈亏。
3. 首页：金价卡片 + 盈亏卡片（涨红跌绿），大数字不跳动（`tabularFigures`）。
4. 行情页：1日/7日/30日切换 + K线切换，折线/K线正常绘制。
5. 提醒页：右上角 + 添加「价格上涨/下跌/收益目标」提醒，开关可切换。
6. 设置页：导出备份（JSON 写入文档目录）→ 可再导入。

> Task 17 执行时 `adb devices` 无连接设备，安装步骤已跳过（APK 产物即为交付物）。

## 5. 已知限制（Known Limitations）

- 启动器图标 label 仍为 `goldpulse`（`AndroidManifest.xml` 的 `android:label`），
  未改成本地名「金脉」；如需可后续替换。
- 后台价格提醒存在 15 分钟级延迟（`workmanager` 周期限制），应用需保持在最近任务中。
- 历史行情「1年」视图受限于本地数据积累时长（MVP 上线即开始积累）。
- `minSdk` 取 Flutter 默认 `flutter.minSdkVersion`（24）。brief 原写 23，但
  `flutter build` 的 gradle 迁移步骤会把显式 `minSdk = 23` 重置回 `flutter.minSdkVersion`，
  且 23 会触发插件 minSdk 告警；故按迁移后的工作值采用 24（见 `android/app/build.gradle.kts`）。
- `targetSdk 34`（brief 要求）低于 Flutter 默认 36；两者均可用，如需上架商店可再升到 36。
- 本地优先、无账号体系；数据仅在本机（导入导出 JSON 备份）。

## 6. 提交

```bash
git add pubspec.yaml android test lib docs/RELEASE.md
git commit -m "release: goldpulse v0.1.0 apk"
```
