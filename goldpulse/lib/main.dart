import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'state/price_provider.dart';

void main() {
  final dio = Dio(BaseOptions(headers: {'User-Agent': 'goldpulse/1.0'}));
  runApp(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: const GoldPulseApp(),
  ));
}
