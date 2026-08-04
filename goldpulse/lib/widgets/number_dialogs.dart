// lib/widgets/number_dialogs.dart
// 公共数字输入对话框：从 holding_list_tile.dart 提取（签名不变），
// 供持仓列表项（长按菜单）与持仓详情页（追加买入/记卖出/加记生息）复用。
import 'package:flutter/material.dart';
import '../utils/formatters.dart';

/// 解析数字输入：容忍千分位分隔符与首尾空白（如 "1,000.50"）。
double? parseNum(String s) => double.tryParse(s.replaceAll(',', '').trim());

/// 单数字输入对话框；返回 null 表示取消。
Future<double?> promptNumber(
  BuildContext context,
  String title, {
  String hint = '',
  String? initial,
}) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final v = parseNum(controller.text);
            if (v != null && v > 0) Navigator.pop(ctx, v);
          },
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 追加买入对话框：克重 + 买入单价（默认当前行情价，可编辑）。
/// [maxAmount] 可选持仓上限；克重超过上限时内联报错且不关闭对话框（不传则不限）。
Future<({double amount, double price})?> promptBuy(
  BuildContext context, {
  String? defaultPrice,
  double? maxAmount,
}) {
  final amountC = TextEditingController();
  final priceC = TextEditingController(text: defaultPrice);
  return showDialog<({double amount, double price})>(
    context: context,
    builder: (ctx) {
      String? errorText;
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          void revalidate() {
            final amount = parseNum(amountC.text);
            setDialogState(() {
              errorText = maxAmount != null && amount != null && amount > maxAmount
                  ? '超过持仓上限 ${fmtGrams(maxAmount)}g'
                  : null;
            });
          }

          return AlertDialog(
            title: const Text('追加买入'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountC,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '买入克重 (g)',
                    hintText: '例如 50',
                    errorText: errorText,
                  ),
                  onChanged: (_) => revalidate(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceC,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '买入价格 (元/g)'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = parseNum(amountC.text);
                  final price = parseNum(priceC.text);
                  if (amount != null &&
                      amount > 0 &&
                      (maxAmount == null || amount <= maxAmount) &&
                      price != null &&
                      price > 0) {
                    Navigator.pop(ctx, (amount: amount, price: price));
                  }
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// 卖出对话框：克重 + 价格（默认当前行情价）。
/// [maxAmount] 当前持仓克重；超卖时内联报错且不关闭对话框。
Future<({double amount, double price})?> promptSell(
  BuildContext context, {
  String? defaultPrice,
  required double maxAmount,
}) {
  final amountC = TextEditingController();
  final priceC = TextEditingController(text: defaultPrice);
  return showDialog<({double amount, double price})>(
    context: context,
    builder: (ctx) {
      String? errorText;
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          void revalidate() {
            final amount = parseNum(amountC.text);
            setDialogState(() {
              errorText = amount != null && amount > maxAmount
                  ? '超过当前持仓 ${fmtGrams(maxAmount)}g'
                  : null;
            });
          }

          return AlertDialog(
            title: const Text('记一笔卖出'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountC,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: '卖出克重',
                    hintText: '例如 50',
                    errorText: errorText,
                  ),
                  onChanged: (_) => revalidate(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: priceC,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '卖出价格（元/g）'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = parseNum(amountC.text);
                  final price = parseNum(priceC.text);
                  if (amount != null &&
                      amount > 0 &&
                      amount <= maxAmount &&
                      price != null &&
                      price > 0) {
                    Navigator.pop(ctx, (amount: amount, price: price));
                  }
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    },
  );
}
