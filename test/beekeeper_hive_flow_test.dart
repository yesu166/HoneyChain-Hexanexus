import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/bee_health/models/bee_health_models.dart';
import 'package:honeychain/bee_health/services/bee_health_question_engine.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/screens/create_hive_screen.dart';

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

  testWidgets('create hive keeps the exact user name and does not require location',
      (tester) async {
    final store = HoneyChainStore.instance;

    await tester.pumpWidget(
      const MaterialApp(home: CreateHiveScreen()),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('create-hive-name')),
      'LSO',
    );
    final save = find.byKey(const ValueKey('create-hive-save'));
    await tester.scrollUntilVisible(
      save,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    final created = store.hives.where((h) => h.name == 'LSO').toList();
    expect(created, hasLength(1));
    expect(created.single.name, 'LSO');
    expect(created.single.id, startsWith('hive-new-'));
    expect(created.single.location, isEmpty);
  });

  test('bee health starter sentinels never become model features', () {
    final engine = BeeHealthQuestionEngine();

    engine.start();
    final weak = engine.recordStarterChoice('__weak');
    expect(weak.askedCount, 0);
    expect(engine.answers, isEmpty);

    engine.reset();
    engine.start();
    final unsure = engine.recordStarterChoice('__not_sure');
    expect(unsure.askedCount, 0);
    expect(unsure.notSureCount, 1);
    expect(engine.answers, isEmpty);

    engine.reset();
    engine.start();
    final real = engine.recordStarterChoice(BeeHealthFeature.kWing);
    expect(real.askedCount, 1);
    expect(engine.answers[BeeHealthFeature.kWing], BeeHealthValue.yes);
  });
}
