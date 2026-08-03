import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/app.dart';
import 'package:goldpulse/models/gold_price.dart';
import 'package:goldpulse/state/price_provider.dart';

void main() {
  testWidgets('GoldPulseApp renders home title', (WidgetTester tester) async {
    final stream = Stream<GoldPrice?>.value(
        GoldPrice(code: 'Au9999', price: 780.20, change: 3.50, percent: 0.45, preClose: 776.70, time: 1));
    await tester.pumpWidget(ProviderScope(
      overrides: [priceProvider.overrideWith((ref) => stream)],
      child: const GoldPulseApp(),
    ));

    // Verify that the home screen shows the app title.
    expect(find.text('金脉 GoldPulse'), findsOneWidget);
  });
}
