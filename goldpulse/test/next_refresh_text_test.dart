// test/next_refresh_text_test.dart
// 回归测试：底部刷新频率文案必须仅在真实快速重试（无缓存且拉取失败）时
// 提示"获取失败"，正常模式一律按配置间隔显示 —— 修复曾有的
// "remain < interval 恒真导致失败文案常驻"的误报 bug。
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/state/price_provider.dart';

void main() {
  test('快速重试（retrying=true）显示失败与自动重试文案', () {
    expect(
      nextRefreshFreqText(retrying: true, configured: const Duration(minutes: 2)),
      '行情获取失败，每 30 秒自动重试',
    );
  });

  test('正常模式（retrying=false）按配置间隔显示分钟', () {
    expect(
      nextRefreshFreqText(retrying: false, configured: const Duration(minutes: 2)),
      '每 2 分钟刷新',
    );
  });

  test('正常模式按配置间隔显示秒', () {
    expect(
      nextRefreshFreqText(retrying: false, configured: const Duration(seconds: 30)),
      '每 30 秒刷新',
    );
  });

  test('正常模式（2 分钟）绝不显示失败文案（回归：误报 bug）', () {
    expect(
      nextRefreshFreqText(retrying: false, configured: const Duration(minutes: 2)),
      isNot(contains('失败')),
    );
  });
}
