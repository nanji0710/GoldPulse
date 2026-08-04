# 金脉 GoldPulse R8/ProGuard 混淆保留规则
#
# 背景：Flutter 3.44 release 构建默认启用 R8 混淆。WorkManager 通过
# androidx.startup.InitializationProvider 在应用启动时反射实例化其内部
# Room 数据库实现类（WorkDatabase_Impl）。R8 感知不到反射调用，会移除该
# 生成类的无参构造函数，导致启动即崩溃：
#   java.lang.NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> []
# （此崩溃已在真机 Android 17 上复现并定位。）

# WorkManager 的 Room 数据库实现类：保留无参构造函数（反射实例化）
-keep class androidx.work.impl.WorkDatabase_Impl { <init>(); }

# 通用兜底：任何 Room 生成的数据库实现类均保留无参构造函数
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# WorkManager 内部模型类（Room 实体/DAO 经反射访问）
-keepclassmembers class androidx.work.impl.model.** { *; }
