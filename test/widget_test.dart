// Zyra Mobile smoke test — verifies the app boots into the vehicle-select
// screen on a fresh install (no profile persisted).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zyra_mobile/app/theme.dart';
import 'package:zyra_mobile/features/vehicle_select/presentation/vehicle_select_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Vehicle select screen renders on fresh install',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ZyraTheme.dark(),
          home: const VehicleSelectScreen(),
        ),
      ),
    );

    // Initial async load.
    await tester.pumpAndSettle();

    expect(find.text('ZYRA'), findsOneWidget);
    expect(find.text('Choose your vehicle'), findsOneWidget);
    expect(find.text('Car'), findsOneWidget);
    expect(find.text('Scooter'), findsOneWidget);
  });
}
