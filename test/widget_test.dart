import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:screen_protector_app/main.dart';

void main() {
  testWidgets('Screen Protector app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ScreenProtectorApp(initialThemeMode: ThemeMode.system));

    // The app should load and show either the onboarding screen (with loading indicator
    // while checking permissions) or the home screen (if already calibrated).
    // Verify that the MaterialApp is present.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
