import 'package:flutter/material.dart';
import 'package:goldpulse/constants/app_theme.dart';

class GoldPulseApp extends StatelessWidget {
  const GoldPulseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '金脉 GoldPulse',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(),
      home: const Scaffold(body: Center(child: Text('金脉 GoldPulse'))),
    );
  }
}
