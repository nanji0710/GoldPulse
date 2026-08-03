import 'package:flutter_test/flutter_test.dart';
import 'package:goldpulse/app.dart';

void main() {
  testWidgets('GoldPulseApp renders home title', (WidgetTester tester) async {
    await tester.pumpWidget(const GoldPulseApp());

    // Verify that the home screen shows the app title.
    expect(find.text('金脉 GoldPulse'), findsOneWidget);
  });
}
