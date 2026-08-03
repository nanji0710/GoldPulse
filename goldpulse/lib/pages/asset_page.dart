// lib/pages/asset_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/state/holding_provider.dart';
import 'package:goldpulse/widgets/holding_list_tile.dart';

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
