import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/data/honeychain_store.dart';

import 'package:honeychain/models/domain.dart';
import 'package:honeychain/screens/productivity_screen.dart';
import 'package:honeychain/services/honeychain_services.dart';
import 'package:honeychain/main.dart';

void main() {
  setUpAll(() {
    HoneyChainStore.testMode = true;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = HoneyChainStore.instance;
    await store.ensureStarted();
    store.resetToDemo();
    store.logout();
  });

  Hive hive(String id) => HoneyChainStore.instance.hives.firstWhere(
        (h) => h.id == id,
      );

  List<HiveReading> readings(List<double> weights) => [
        for (var i = 0; i < weights.length; i++)
          HiveReading(
            id: 'r-$i',
            hiveId: 'hive-x',
            recordedAt: DateTime(2026, 1, 1).add(Duration(days: i)),
            temperatureC: 34,
            humidityPercent: 60,
            weightKg: weights[i],
          ),
      ];

  test('insufficient data yields the honest empty insight', () {
    final insight = HiveInsightService().createInsight(
      hive('hive-001'),
      const [],
    );
    expect(insight.productivityInsight, isEmpty);
    expect(insight.weightStatus, WeightStatus.steady);
  });

  test('rising weight telemetry is reported as a growing outlook', () {
    final insight = HiveInsightService().createInsight(
      hive('hive-001'),
      readings([10, 10.4, 10.8, 11.4]),
    );
    expect(insight.weightStatus, WeightStatus.growing);
  });

  test('dropping weight telemetry is reported as dropping', () {
    final insight = HiveInsightService().createInsight(
      hive('hive-001'),
      readings([10, 9.9, 9.6, 9.2]),
    );
    expect(insight.weightStatus, WeightStatus.dropping);
  });

  testWidgets('productivity screen renders the prediction from real readings',
      (tester) async {
    final store = HoneyChainStore.instance;
    store.completeLogin();
    await tester.pumpWidget(const MaterialApp(home: ProductivityScreen()));
    await tester.pumpAndSettle();

    // After completeLogin() the demo user's first hive is preselected, so the
    // screen shows the telemetry outlook rather than the empty state.
    expect(find.text(store.tr('prod.telemetry')), findsOneWidget);
    // The first hive is preselected; its recorded demo telemetry is real.
    final anyOutlook = find.text(store.tr('prod.outlook.growing'));
    final steady = find.text(store.tr('prod.outlook.steady'));
    final dropping = find.text(store.tr('prod.outlook.dropping'));
    final outlooks = anyOutlook.evaluate().length +
        steady.evaluate().length +
        dropping.evaluate().length;
    expect(outlooks, 1, reason: 'exactly one outlook state is shown');
    // No colony measurements have been entered yet, so the yield slot reports
    // the insufficient-data state rather than a fabricated number.
    expect(find.text(store.tr('prod.yield.insufficient')), findsOneWidget);
    expect(find.text(store.tr('prod.inputs.title')), findsOneWidget);
    expect(find.text(store.tr('prod.refresh')), findsOneWidget);
  });

  testWidgets('navigation: More tab reaches Productivity Prediction',
      (tester) async {
    final store = HoneyChainStore.instance;
    store.completeLogin();
    await tester.pumpWidget(const HoneyChainApp());
    await tester.pumpAndSettle();

    // Open the More tab.
    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('More'),
    ));
    await tester.pumpAndSettle();

    // The menu list is lazy — scroll until the entry mounts, then tap it.
    var guard = 0;
    while (find.text('Productivity Prediction').evaluate().isEmpty &&
        guard < 10) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -150));
      await tester.pumpAndSettle();
      guard++;
    }
    expect(find.text('Productivity Prediction'), findsOneWidget);
    await tester.tap(find.text('Productivity Prediction'));
    await tester.pumpAndSettle();

    expect(find.text(store.tr('prod.title')), findsOneWidget);
    expect(find.byType(ProductivityScreen), findsOneWidget);
  });
}
