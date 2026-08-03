// lib/pages/setting_page.dart
// 设置页：刷新频率、数据备份（导出/导入/清空）、关于。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_theme.dart';
import '../database/app_database.dart';
import '../services/backup_service.dart';
import '../state/alert_provider.dart';
import '../state/holding_provider.dart';
import '../state/price_provider.dart';

/// 刷新频率选项：秒数 → 文案。默认 2 分钟。
const Map<int, String> _refreshOptions = {
  30: '30 秒',
  60: '1 分钟',
  120: '2 分钟',
  300: '5 分钟',
  900: '15 分钟',
};

class SettingPage extends ConsumerWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interval = ref.watch(refreshIntervalProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(children: [
        const _SectionTitle('刷新频率'),
        ListTile(
          title: const Text('行情刷新间隔'),
          subtitle: Text(interval != null ? '当前 ${_label(interval)}' : '默认 2 分钟'),
          onTap: () => _pickRefreshRate(context, ref),
        ),
        const Divider(color: AppTheme.card),
        const _SectionTitle('数据管理'),
        ListTile(
          title: const Text('导出备份（JSON）'),
          subtitle: const Text('保存持仓、交易、提醒到本地 JSON 文件'),
          onTap: () => _exportBackup(context, ref),
        ),
        ListTile(
          title: const Text('导入备份'),
          subtitle: const Text('从本地 JSON 文件恢复数据'),
          onTap: () => _importBackup(context, ref),
        ),
        ListTile(
          title: const Text('清空全部数据'),
          subtitle: const Text('删除全部持仓、交易、提醒与价格历史'),
          onTap: () => _clearAll(context, ref),
        ),
        const Divider(color: AppTheme.card),
        const _SectionTitle('关于'),
        const ListTile(title: Text('金脉 GoldPulse v0.1.0'), subtitle: Text('本地 · 免费 · 无账号')),
      ]),
    );
  }
}

String _label(Duration d) => _refreshOptions[d.inSeconds] ?? '${d.inSeconds} 秒';

/// 底部弹窗选择刷新间隔，持久化到 shared_preferences 并 invalidate 行情轮询。
Future<void> _pickRefreshRate(BuildContext context, WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  final current = prefs.getInt(refreshIntervalPrefKey) ?? 120;
  final chosen = await showModalBottomSheet<int>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('行情刷新间隔'), leading: Icon(Icons.timelapse)),
        for (final e in _refreshOptions.entries)
          ListTile(
            leading: e.key == current ? const Icon(Icons.check, color: AppTheme.gold) : null,
            title: Text(e.value),
            onTap: () => Navigator.pop(ctx, e.key),
          ),
      ]),
    ),
  );
  if (chosen == null) return;
  await prefs.setInt(refreshIntervalPrefKey, chosen);
  ref.invalidate(refreshIntervalProvider); // priceProvider 监听它，自动以新间隔重启
}

/// 收集三张业务表 → 序列化 → 写入应用文档目录（timestamped 文件名）。
Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final holdings = await ref.read(holdingDaoProvider).list();
    final trades = await ref.read(tradeDaoProvider).all();
    final alerts = await ref.read(alertDaoProvider).list();
    final json = await BackupService().exportJson(
      holdings: holdings,
      trades: trades,
      alerts: alerts,
    );
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}goldpulse-backup-${_timestamp()}.json');
    await file.writeAsString(json, flush: true);
    messenger.showSnackBar(SnackBar(content: Text('已备份到 ${file.path}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
  }
}

/// 列出文档目录中的 .json 备份文件 → 用户选择 → 校验并重建库 → 刷新 providers。
Future<void> _importBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final dir = await getApplicationDocumentsDirectory();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .toList();
    if (files.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('文档目录中没有找到备份文件')));
      return;
    }
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('选择备份文件'), leading: Icon(Icons.folder_open)),
          for (final f in files)
            ListTile(
              title: Text(f.path.split(Platform.pathSeparator).last),
              onTap: () => Navigator.pop(ctx, f.path),
            ),
        ]),
      ),
    );
    if (picked == null || !context.mounted) return;
    final raw = await File(picked).readAsString();
    await BackupService().importJson(raw); // 校验 version；失败抛 FormatException 不落数据
    ref.invalidate(holdingsProvider);
    ref.invalidate(alertsProvider);
    ref.invalidate(priceProvider); // 清库后重读行情历史
    messenger.showSnackBar(const SnackBar(content: Text('导入成功')));
  } on FormatException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('导入失败：${e.message}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
  }
}

/// 确认对话框 → 删除四张表全部行 → 刷新 providers。
Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('清空全部数据'),
      content: const Text('将删除全部持仓、交易、提醒与价格历史，且不可恢复。确定继续？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final db = await AppDatabase.database;
  await db.delete('gold_price');
  await db.delete('trade_record');
  await db.delete('holding');
  await db.delete('alert');
  ref.invalidate(holdingsProvider);
  ref.invalidate(alertsProvider);
  ref.invalidate(priceProvider);
  messenger.showSnackBar(const SnackBar(content: Text('已清空全部数据')));
}

String _timestamp() {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${n.year}${two(n.month)}${two(n.day)}-${two(n.hour)}${two(n.minute)}${two(n.second)}';
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title,
          style: const TextStyle(
              color: AppTheme.gold, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }
}
