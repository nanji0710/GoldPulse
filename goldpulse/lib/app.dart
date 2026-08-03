import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';
import 'package:goldpulse/pages/alert_page.dart';
import 'package:goldpulse/pages/asset_page.dart';
import 'package:goldpulse/pages/home_page.dart';
import 'package:goldpulse/pages/market_page.dart';
import 'package:goldpulse/pages/onboarding_page.dart';
import 'package:goldpulse/pages/setting_page.dart';

class GoldPulseApp extends StatelessWidget {
  const GoldPulseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '金脉 GoldPulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      routes: {
        '/home': (c) => const MainShell(),
        '/onboarding': (c) => const OnboardingPage(),
      },
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  static const _pages = [HomePage(), MarketPage(), AssetPage(), AlertPage(), SettingPage()];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.card,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '行情'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: '资产'),
          NavigationDestination(icon: Icon(Icons.notifications_outlined), label: '提醒'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}
