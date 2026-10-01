import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rooster_core/rooster_core.dart';
import 'package:rooster_rage/app/app.dart';
import 'package:rooster_rage/screens/roster_screen.dart';
import 'package:rooster_rage/widgets/chicken_info_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the real screens so layout / indexing errors (e.g. 8 chickens vs
/// 5 variants) fail in CI instead of showing a grey screen in the browser.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in const [Size(1280, 800), Size(740, 360), Size(375, 812)]) {
    testWidgets('home screen builds at ${size.width}x${size.height}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: RoosterApp()));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      expect(find.text('ROOSTER RAGE'), findsOneWidget);
      expect(find.byIcon(Icons.menu_book), findsWidgets);
    });
  }

  testWidgets('roster lists all chickens', (tester) async {
    tester.view.physicalSize = const Size(1280, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: RosterScreen())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(ChickenInfoCard), findsNWidgets(ChickenClasses.all.length));
  });
}
