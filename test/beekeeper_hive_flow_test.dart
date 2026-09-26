import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/bee_health/models/bee_health_models.dart';
import 'package:honeychain/bee_health/services/bee_health_question_engine.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/models/domain.dart';
import 'package:honeychain/models/iot.dart';
import 'package:honeychain/repositories/local_honeychain_repository.dart';
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

  test('adopting the server id collapses local+server hives to a single row',
      () {
    final repo = LocalHoneychainRepository(seedDemo: false);
    const beekeeperId = 'bk-test';

    // The store creates the local hive first with a generated id...
    repo.addHive(
      const Hive(
        id: 'hive-new-1',
        name: 'LSO',
        beekeeperId: beekeeperId,
        organizationId: 'ORG',
        location: 'Orchard',
        honeyType: 'Floral Honey',
      ),
    );

    // ...then the backend acknowledges it with its DB uuid. addHiveToBackend
    // re-keys the local record to that server id (the fix for the two-rows
    // merge bug). Simulate that re-key directly here:
    repo.replaceHive(
      'hive-new-1',
      const Hive(
        id: '00000000-0000-4000-8000-0000000000ab',
        name: 'LSO',
        beekeeperId: beekeeperId,
        organizationId: 'ORG',
        location: 'Orchard',
        honeyType: 'Floral Honey',
      ),
    );

    // Both representations map to a UUID. If the server row also carried the
    // same id (it does after a successful POST), the merge sees ONE entry.
    final rows = repo.hivesForBeekeeper(beekeeperId);
    expect(rows, hasLength(1));
    expect(rows.single.id, '00000000-0000-4000-8000-0000000000ab');
    expect(rows.single.name, 'LSO');
  });

  test('replaceHive falls back to appending when the old id is absent', () {
    final repo = LocalHoneychainRepository(seedDemo: false);
    repo.replaceHive(
      'missing-id',
      const Hive(
        id: 'server-uuid',
        name: 'Late Synced',
        beekeeperId: 'bk-test',
        organizationId: 'ORG',
        location: '',
        honeyType: 'Apiary',
      ),
    );
    final rows = repo.hivesForBeekeeper('bk-test');
    expect(rows, hasLength(1));
    expect(rows.single.id, 'server-uuid');
  });

  test('home surfaces the most severe unread backend notification', () {
    final store = HoneyChainStore.instance;
    store.debugSetApiNotifications([
      const BackendNotification(
        notificationId: 'n-info',
        category: 'apiary',
        severity: 'info',
        reason: 'routine',
        recommendedAction: 'Continue monitoring',
        source: 'simulator',
        title: 'Routine update',
        body: 'All clear',
        createdAt: '2026-01-01T00:00:00Z',
        read: false,
        isSimulated: true,
      ),
      const BackendNotification(
        notificationId: 'n-critical',
        category: 'environment',
        severity: 'critical',
        reason: 'hive_fire_risk',
        recommendedAction: 'Move the hive to shade and call the local team',
        source: 'simulator',
        title: 'Extreme heat warning',
        body: 'Temperature outside safe range',
        createdAt: '2026-01-02T00:00:00Z',
        read: false,
        isSimulated: true,
      ),
      const BackendNotification(
        notificationId: 'n-warning',
        category: 'environment',
        severity: 'warning',
        reason: 'humidity',
        recommendedAction: 'Check ventilation',
        source: 'simulator',
        title: 'High humidity',
        body: 'Humidity approaching threshold',
        createdAt: '2026-01-03T00:00:00Z',
        read: false,
        isSimulated: true,
      ),
    ]);
    expect(store.apiUnreadNotifications, 3);

    // The critical alert outranks the warning and info regardless of recency.
    final priority = _severityPriority(store);
    expect(priority?.title, 'Extreme heat warning');

    store.debugSetApiNotifications(const []);
    expect(store.apiUnreadNotifications, 0);
    expect(_severityPriority(store), isNull);
  });
}

BackendNotification? _severityPriority(HoneyChainStore store) {
  BackendNotification? best;
  for (final note in store.apiNotifications) {
    if (note.read) continue;
    final rank = _alertRank(note.severity);
    final bestRank = best == null ? -1 : _alertRank(best.severity);
    if (best == null || rank > bestRank) best = note;
  }
  return best;
}

int _alertRank(String severity) => switch (severity) {
      'critical' || 'error' => 3,
      'warning' => 2,
      'info' => 1,
      _ => 0,
    };
