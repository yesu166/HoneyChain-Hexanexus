import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/main.dart';
import 'package:honeychain/models/disease.dart';
import 'package:honeychain/models/domain.dart';

void main() {
  setUpAll(() {
    // Keep the widget tests fully offline (no real network connectivity checks).
    HoneyChainStore.testMode = true;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = HoneyChainStore.instance;
    await store.ensureStarted();
    store.resetToDemo();
    store.logout();
  });

  Finder scrollable() => find.byType(Scrollable).hitTestable().first;

  /// Scrolls the active tab until [finder] is visible, then asserts it exists.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      try {
        await tester.scrollUntilVisible(finder, 200, scrollable: scrollable());
      } catch (_) {
        // The item may be above the current scroll offset — try the other way.
        await tester.scrollUntilVisible(finder, -200, scrollable: scrollable());
      }
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> see(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await reveal(tester, finder);
    expect(finder, findsOneWidget);
  }

  /// Switches the bottom navigation bar to the tab labelled [label].
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

  /// Opens the [More] menu and taps the menu item with the given title.
  Future<void> openMoreItem(WidgetTester tester, String title) async {
    await goToTab(tester, 'More');
    await see(tester, title);
    await tester.tap(find.text(title).first);
    await tester.pumpAndSettle();
  }

  /// Drives the real phone + OTP login flow (OTP 1234) to the main shell.
  /// Picks the Beekeeper role on the first-launch gate, then logs in.
  Future<void> loginViaUi(WidgetTester tester) async {
    await tester.pumpWidget(const HoneyChainApp());
    await tester.pumpAndSettle();

    // First-launch role gate -> Beekeeper.
    await tester.tap(find.text('Beekeeper'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.enterText(find.byType(TextField).at(i + 1), '${i + 1}');
      await tester.pump();
    }

    await tester.tap(find.text('Verify & Login'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  /// Boots straight into the logged-in main shell (login done via the store).
  Future<void> openLoggedInApp(WidgetTester tester) async {
    final store = HoneyChainStore.instance;
    if (!store.loggedIn) store.completeLogin();
    await tester.pumpWidget(const HoneyChainApp());
    await tester.pumpAndSettle();
  }

  testWidgets('role gate to login and signing in opens the home tab', (
    tester,
  ) async {
    await loginViaUi(tester);

    final store = HoneyChainStore.instance;
    expect(store.loggedIn, isTrue);

    // Home dashboard shows the online status, overall health, and the harvest
    // action (attention count driven by the demo hive readings).
    await see(tester, 'Online · Auto-synced');
    await see(tester, '3 hives need attention');
    await see(tester, "Add today's harvest");
  });

  testWidgets('recording a harvest from home updates the store', (
    tester,
  ) async {
    await openLoggedInApp(tester);

    await see(tester, "Add today's harvest");
    await tester.tap(find.text("Add today's harvest"));
    await tester.pumpAndSettle();

    // Pick a hive in the dropdown (the default preselection only takes effect
    // once an item is chosen).
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hive #1 · Mango Orchard').last);
    await tester.pumpAndSettle();

    await see(tester, 'Confirm & Save Harvest');
    await tester.tap(find.text('Confirm & Save Harvest'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    final store = HoneyChainStore.instance;
    expect(
      store.harvests.where(
        (h) => h.hiveId == 'hive-001' && h.quantityKg == 1.0,
      ),
      hasLength(1),
    );

    // Drain the save snackbar timer so no timers remain pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('hive details, alerts and honey passport drilldown', (
    tester,
  ) async {
    await openLoggedInApp(tester);

    // My Hives -> hive details.
    await openHives(tester);
    await tester.tap(find.text('Hive #1').first);
    await tester.pumpAndSettle();
    await see(tester, 'MONITOR READINGS');
    await see(tester, 'WHAT SHOULD I DO?');
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Hives was pushed (not a tab), so back out to the shell too.
    await tester.pageBack();
    await tester.pumpAndSettle();

    // More -> Alerts (seeded from the demo data).
    await openMoreItem(tester, 'Alerts');
    await see(tester, 'Hive #4 needs cooling');
    await see(tester, 'Hive #3 needs care');
    await see(tester, 'Honey Batch Verified');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // More -> My Honey -> verified passport for the seeded batch.
    await openMoreItem(tester, 'My Honey');
    await tester.tap(find.text('Batch #24').first);
    await tester.pumpAndSettle();
    await see(tester, 'Honey Passport');
    await see(tester, 'Lab Verified');
  });

  testWidgets('profile renders and logout returns to the role gate', (
    tester,
  ) async {
    await openLoggedInApp(tester);

    await openMoreItem(tester, 'Profile');
    await see(tester, 'Ravi Kumar');
    await see(tester, 'Member ID: HC-9082');
    await see(tester, 'Nilgiris Honey FPO');
    await see(tester, 'Logout');

    await tester.tap(find.text('Logout').first);
    await tester.pumpAndSettle();
    await see(tester, 'Log out of HoneyChain?');

    await tester.tap(find.widgetWithText(TextButton, 'Logout'));
    await tester.pumpAndSettle();

    final store = HoneyChainStore.instance;
    expect(store.loggedIn, isFalse);
    await see(tester, 'How will you use HoneyChain?');
    await see(tester, 'Beekeeper');
  });

  testWidgets('check for disease opens the photo source sheet and cancel closes it', (
    tester,
  ) async {
    await openLoggedInApp(tester);

    await openHives(tester);
    await tester.tap(find.text('Hive #1').first);
    await tester.pumpAndSettle();

    await see(tester, 'Check for Disease');
    await tester.tap(find.text('Check for Disease'));
    await tester.pumpAndSettle();

    // The camera / gallery selection sheet appears.
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose Photo'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Still on the hive details screen — no navigation happened.
    await see(tester, 'MONITOR READINGS');
  });

  testWidgets('demo simulation flags a hive for possible disease', (
    tester,
  ) async {
    await openLoggedInApp(tester);

    // Demo simulation tooling now lives under More -> Developer.
    await openMoreItem(tester, 'Developer');
    await see(tester, 'Simulate Possible Disease');
    await tester.tap(find.text('Simulate Possible Disease'));
    await tester.pumpAndSettle();

    final store = HoneyChainStore.instance;
    expect(store.demoScreeningOutcome, DiseaseScreenOutcome.possibleDisease);
    expect(store.hasHiveConditionAlert('hive-004'), isTrue);
    final diseaseAlerts = store.alerts
        .where(
          (a) =>
              a.type == AlertType.disease &&
              a.hiveId == 'hive-004' &&
              a.id.startsWith('alert-disease-'),
        )
        .toList();
    expect(diseaseAlerts, isNotEmpty);

    // Back to the shell, then open the flagged hive's details.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openHives(tester);
    await see(tester, 'Hive #4');
    await tester.tap(find.text('Hive #4').first);
    await tester.pumpAndSettle();
    await see(tester, 'Possible disease signs detected. Photo screening recommended.');
  });

  testWidgets('screening a photo shows the possible-disease result and records history', (
    tester,
  ) async {
    await openLoggedInApp(tester);

    final store = HoneyChainStore.instance;
    store.setDemoScreeningOutcome(DiseaseScreenOutcome.possibleDisease);

    await openHives(tester);
    await tester.tap(find.text('Hive #1').first);
    await tester.pumpAndSettle();

    await see(tester, 'Check for Disease');
    await tester.tap(find.text('Check for Disease'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();

    // Preview -> analysis -> possible-disease result.
    await see(tester, 'Disease Screening');
    await see(tester, 'Analyze Photo');
    await tester.tap(find.text('Analyze Photo'));
    await tester.pumpAndSettle();

    await see(tester, 'Possible Disease Signs');
    await see(tester, 'Possible condition: EFB');
    await see(tester, 'Further inspection recommended.');
    await see(tester, 'AI-assisted screening — this is not a confirmed diagnosis.');

    expect(store.healthChecksFor('hive-001'), hasLength(1));
    expect(
      store.healthChecksFor('hive-001').single.conditionId,
      'efb',
    );
    expect(
      store.healthChecksFor('hive-001').single.outcome,
      DiseaseScreenOutcome.possibleDisease,
    );

    // Done returns to the hive, showing the disease banner + health history.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await see(tester, 'RECENT HEALTH CHECKS');
    await see(tester, 'Possible disease signs');
    await see(tester, 'EFB');
  });

  testWidgets('screening a healthy photo records history and clears disease alerts', (
    tester,
  ) async {
    await openLoggedInApp(tester);

    final store = HoneyChainStore.instance;
    store.setDemoScreeningOutcome(DiseaseScreenOutcome.noObviousSigns);

    await openHives(tester);
    await tester.tap(find.text('Hive #1').first);
    await tester.pumpAndSettle();

    await see(tester, 'Check for Disease');
    await tester.tap(find.text('Check for Disease'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze Photo'));
    await tester.pumpAndSettle();

    await see(tester, 'No Obvious Disease Signs');
    await see(tester, 'Continue routine hive monitoring.');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    await see(tester, 'No obvious signs');
    expect(
      store.healthChecksFor('hive-001').single.outcome,
      DiseaseScreenOutcome.noObviousSigns,
    );
    expect(
      store.alerts.where(
        (a) => a.type == AlertType.disease && a.hiveId == 'hive-001',
      ),
      isEmpty,
    );
  });

  testWidgets('unclear photos give an unable-to-assess result that lets you retake', (
    tester,
  ) async {
    await openLoggedInApp(tester);

    final store = HoneyChainStore.instance;
    store.setDemoScreeningOutcome(DiseaseScreenOutcome.unableToAssess);

    await openHives(tester);
    await tester.tap(find.text('Hive #1').first);
    await tester.pumpAndSettle();

    await see(tester, 'Check for Disease');
    await tester.tap(find.text('Check for Disease'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze Photo'));
    await tester.pumpAndSettle();

    await see(tester, 'Unable to Assess');
    await see(tester, 'Take a clearer photo showing the brood/frame.');

    // "Retake Photo" re-opens the source sheet.
    await tester.tap(find.text('Retake Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Take Photo'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The screening attempt was still recorded for the hive.
    expect(
      store.healthChecksFor('hive-001').single.outcome,
      DiseaseScreenOutcome.unableToAssess,
    );
  });

  testWidgets('iot abnormality simulation warns without claiming disease', (
    tester,
  ) async {
    await openLoggedInApp(tester);

    final store = HoneyChainStore.instance;
    await openMoreItem(tester, 'Developer');
    await see(tester, 'Simulate IoT Abnormality');
    await tester.tap(find.text('Simulate IoT Abnormality'));
    await tester.pumpAndSettle();

    expect(store.hasHiveConditionAlert('hive-004'), isTrue);
    expect(
      store.alerts.where(
        (a) => a.type == AlertType.iot && a.hiveId == 'hive-004',
      ),
      isNotEmpty,
    );
    // Sensor noise must never be turned into a disease claim.
    expect(
      store.alerts.where(
        (a) => a.type == AlertType.disease && a.hiveId == 'hive-004',
      ),
      isEmpty,
    );

    final hive4 = store.hives.firstWhere((h) => h.id == 'hive-004');
    expect(store.insightFor(hive4).riskLevel, RiskLevel.highRisk);

    // Back to the shell, then open the anomalous hive's details.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openHives(tester);
    await see(tester, 'Hive #4');
    await tester.tap(find.text('Hive #4').first);
    await tester.pumpAndSettle();
    await see(tester, 'Abnormal hive condition detected. Inspection recommended.');
  });
}