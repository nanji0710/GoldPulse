plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.goldpulse.goldpulse"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 18 要求启用 core library desugaring。
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.goldpulse.goldpulse"
        // MVP 约定（brief）：targetSdk 34（≤ compileSdk 36）。minSdk 保留
        // flutter.minSdkVersion（当前 24，即 Flutter 推荐下限；brief 原写 23，
        // 但 flutter build 的 gradle 迁移步骤会把显式 23 重置回 flutter.minSdkVersion，
        // 且 23 会触发插件 minSdk 告警，故采用 24）。各插件均允许此值。
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        // versionCode/versionName 由 pubspec.yaml（0.1.0+1）单一来源决定。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // 发布签名：密钥库 android/keystore/goldpulse.jks（*.jks 已被 .gitignore 忽略，禁止入库）。
        // storePassword/keyPassword 从构建环境变量 GOLDPULSE_KEY_PASS 读取；未设置时 release 构建会失败，
        // 详见 docs/RELEASE.md。
        create("release") {
            storeFile = file("../keystore/goldpulse.jks")
            storePassword = System.getenv("GOLDPULSE_KEY_PASS")
            keyAlias = "goldpulse"
            keyPassword = System.getenv("GOLDPULSE_KEY_PASS")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    // flutter_local_notifications 18 依赖 core library desugaring。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
