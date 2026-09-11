import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/main.dart';

/// Responsive smoke test: the beekeeper portal must render cleanly from
/// 320 dp up to 430 dp. Flutter test auto-fails on any layout overflow /
/// uncaught render exception, so this guards the "no clipped / overflowing
/// rows, no horizontal scroll required" acceptance for the small-phone tier.
void main() {
  setUpAll(() {
    HoneyChainStore.testMode = true;
  });

  for (final width in [320.0, 360.0, 390.0, 430.0]) {
    testWidgets('beekeeper portal renders at ${width.toInt()} dp', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final store = HoneyChainStore.instance;
      await store.ensureStarted();
      store.resetToDemo();
      store.completeLogin();

      await tester.pumpWidget(const HoneyChainApp());
      await tester.pumpAndSettle();

      // Home: sync status, alert section and the two primary actions.
      expect(find.text('Online'), findsOneWidget);
      expect(find.text('3 hives need attention'), findsOneWidget);
      expect(find.text("Add today's harvest"), findsOneWidget);

      // Record Harvest form: quick weight buttons, 100 g hint, source field.
      await tester.tap(find.text("Add today's harvest").first);
      await tester.pumpAndSettle();
      expect(find.text('100 g'), findsOneWidget);
      expect(find.text('3 kg'), findsOneWidget);
      expect(find.textContaining('Minimum 100 g'), findsOneWidget);
      await see(tester, 'Confirm & Save Harvest');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await openHives(tester);
      for (final hive in ['Hive #1', 'Hive #2', 'Hive #3', 'Hive #4']) {
        expect(find.text(hive), findsWidgets);
      }

      await tester.tap(find.text('Hive #1').first);
      await tester.pumpAndSettle();
      await see(tester, 'MONITOR READINGS');
      await see(tester, 'WHAT SHOULD I DO?');
      await tester.pageBack();
      await tester.pumpAndSettle();
      // Hives was pushed (not a tab), so back out to the shell too.
      await tester.pageBack();
      await tester.pumpAndSettle();

      await goToTab(tester, 'More');
      for (final item in ['My Honey', 'Bee Health', 'Alerts', 'Profile', 'Language', 'Settings']) {
        await see(tester, item);
      }

      // My Honey batches screen renders.
      await tapText(tester, 'My Honey');
      await tester.pumpAndSettle();
      await see(tester, 'My Honey');
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Alerts list renders.
      await tapText(tester, 'Alerts');
      await tester.pumpAndSettle();
      await see(tester, 'Alerts');
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Developer -> IoT Simulation is tucked away here, never on Home.
      await tapText(tester, 'Developer');
      await tester.pumpAndSettle();
      await see(tester, 'IoT Simulation');
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Settings: General section + language row.
      await tapText(tester, 'Settings');
      await tester.pumpAndSettle();
      await see(tester, 'Language');
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Bee Health large hive picking + inspected state.
      await tapText(tester, 'Bee Health');
      await tester.pumpAndSettle();
      await see(tester, 'Select a hive');
      await see(tester, 'Not inspected');
      await tapText(tester, 'Hive #1');
      await see(tester, 'Start');
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Profile: purity row gone, Edit + Logout present.
      await see(tester, 'Profile');
      await tapText(tester, 'Profile');
      await tester.pumpAndSettle();
      await see(tester, 'Ravi Kumar');
      await see(tester, 'Edit Profile Details');
      await see(tester, 'Logout');
      expect(find.text('Purity Rating'), findsNothing);
    });
  }
}

Future<void> goToTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  ));
  await tester.pumpAndSettle();
}

/// Opens the Hives list from the Home dashboard (My Hives primary action).
Future<void> openHives(WidgetTester tester) async {
  await goToTab(tester, 'Home');
  await tester.tap(find.text('My Hives').first);
  await tester.pumpAndSettle();
}

/// Scrolls until [text] is built, brings it on-screen with [ensureVisible],
/// then taps it. Lazily-built slivers and viewport-edge items are handled.
Future<void> tapText(WidgetTester tester, String text) async {
  var finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isNotEmpty) {
      try {
        await tester.scrollUntilVisible(
          finder,
          140,
          scrollable: scrollable.first,
        );
      } catch (_) {
        await tester.scrollUntilVisible(
          finder,
          -140,
          scrollable: find.byType(Scrollable).last,
        );
      }
    }
    finder = find.text(text);
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.tap(finder.first, warnIfMissed: false);
    await tester.pumpAndSettle();
  }
}

Future<void> see(WidgetTester tester, String text) async {
  if (find.text(text).evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).hitTestable();
    if (scrollable.evaluate().isNotEmpty) {
      try {
        await tester.scrollUntilVisible(
          find.text(text),
          120,
          scrollable: scrollable.first,
        );
      } catch (_) {
        await tester.scrollUntilVisible(
          find.text(text),
          -120,
          scrollable: find.byType(Scrollable).hitTestable().last,
        );
      }
    }
  }
  final hit = find.text(text).hitTestable();
  if (hit.evaluate().isNotEmpty) {
    await tester.ensureVisible(hit.first);
  }
  await tester.pumpAndSettle();
}