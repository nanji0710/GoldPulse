// lib/state/onboarding_provider.dart
// 首次引导完成标记：持久化到 shared_preferences。
// 只有第一次启动（未完成引导）才展示引导页；跳过/完成即写入标记，
// 后续启动直接进入主界面（即使未录入持仓）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const onboardingDoneKey = 'onboarding_done';

/// 是否已完成首次引导（默认 false）。
final onboardedProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(onboardingDoneKey) ?? false;
});

/// 标记引导完成（跳过或走完流程都调用），随后 invalidate 让 StartupGate 重判。
final completeOnboardingProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(onboardingDoneKey, true);
  ref.invalidate(onboardedProvider);
});
