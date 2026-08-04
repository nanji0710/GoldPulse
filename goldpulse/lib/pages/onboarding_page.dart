// lib/pages/onboarding_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/state/onboarding_provider.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});
  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  /// 跳过或走完流程：标记引导完成（持久化），随后进入主界面。
  Future<void> _finishOnboarding() async {
    await ref.read(completeOnboardingProvider.future);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

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
            child: TextButton(onPressed: _finishOnboarding,
                child: const Text('跳过')),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('金脉 GoldPulse',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
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
                  ? _finishOnboarding
                  : () => _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
              child: Text(_page == _steps.length - 1 ? '开始使用' : '下一步'),
            ),
          ),
        ]),
      ),
    );
  }
}
