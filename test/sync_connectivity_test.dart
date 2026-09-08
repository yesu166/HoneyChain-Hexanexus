import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/models/domain.dart';
import 'package:honeychain/services/sync_service.dart';
import 'package:honeychain/widgets/sync_status_badge.dart';

/// Always-failing gateway: every push throws, so the sync engine exercises its
/// retry + failure reporting without any real network.
class _FailingGateway implements SyncGateway {
  int pushCount = 0;

  @override
  Future<SyncResult> pushHarvest(Harvest harvest) async {
    pushCount++;
    throw Exception('boom');
  }

  @override
  Future<SyncResult> pushBatch(Batch batch) async {
    pushCount++;
    throw Exception('boom');
  }
}

void main() {
  setUp(() {
    HoneyChainStore.testMode = true;
    SharedPreferences.setMockInitialValues({});
    final store = HoneyChainStore.instance;
    store.ensureStarted();
    store.resetToDemo();
    store.clearSyncErrors();
  });

  group('sync engine', () {
    test('retries within a pass up to maxAttempts then reports failure', () async {
      final gateway = _FailingGateway();
      final engine = SyncEngine(gateway);

      var failed = 0;
      var synced = 0;
      final harvest = Harvest(
        id: 'harvest-retry',
        hiveId: 'hive-x',
        beekeeperId: 'bk-x',
        harvestedAt: DateTime.now(),
        honeyType: 'Wild Forest',
        quantityKg: 1.5,
        syncStatus: SyncStatus.pending,
      );

      await engine.process(
        pendingHarvests: [harvest],
        pendingBatches: const [],
        onHarvestSynced: (_) => synced++,
        onBatchSynced: (_) => synced++,
        onHarvestFailed: (_) => failed++,
        onBatchFailed: (_) => failed++,
        maxAttempts: 2,
      );

      expect(gateway.pushCount, 2);
      expect(failed, 1);
      expect(synced, 0);
      expect(engine.isSyncing, isFalse);
      expect(engine.lastError, isNotEmpty);
    });

    test('a passing gateway marks the record synced once', () async {
      final engine = SyncEngine(MockSyncGateway());
      var synced = 0;
      var failed = 0;

      await engine.process(
        pendingHarvests: [
          Harvest(
            id: 'harvest-ok',
            hiveId: 'hive-x',
            beekeeperId: 'bk-x',
            harvestedAt: DateTime.now(),
            honeyType: 'Wild Forest',
            quantityKg: 1.5,
            syncStatus: SyncStatus.pending,
          ),
        ],
        pendingBatches: const [],
        onHarvestSynced: (_) => synced++,
        onBatchSynced: (_) => synced++,
        onHarvestFailed: (_) => failed++,
        onBatchFailed: (_) => failed++,
      );

      expect(synced, 1);
      expect(failed, 0);
    });
  });

  group('store offline queue', () {
    test('offline records stay pending and sync when connectivity returns', () async {
      final store = HoneyChainStore.instance;
      store.debugSetOnline(false);
      final hive = store.hives.first;

      store.recordHarvest(hive: hive, quantityKg: 1.5);

      final queued = store.harvests
          .where((h) => h.syncStatus == SyncStatus.pending)
          .toList();
      expect(queued, isNotEmpty, reason: 'offline harvest must be queued');
      expect(store.pendingCount, greaterThan(0));

      store.debugSetOnline(true);
      final drained = await store.syncPendingNow();
      expect(drained, isTrue);
      expect(store.pendingCount, 0);
      expect(
        store.harvests.where((h) => h.syncStatus != SyncStatus.synced),
        isEmpty,
      );
    });

    test('parses failed sync status from persisted storage', () {
      final failed = Harvest.fromJson({
        'id': 'h-1',
        'hiveId': 'hv-1',
        'beekeeperId': 'bk-1',
        'harvestedAt': DateTime.now().toIso8601String(),
        'honeyType': 'X',
        'quantityKg': 1.0,
        'syncStatus': 'failed',
      });
      expect(failed.syncStatus, SyncStatus.failed);
    });
  });

  group('canonical sync badge', () {
    Widget wrap() => const MaterialApp(home: Scaffold(body: SyncStatusBadge()));

    testWidgets('shows online when reachable', (tester) async {
      HoneyChainStore.instance.debugSetOnline(true);
      await tester.pumpWidget(wrap());
      expect(find.text('Online'), findsOneWidget);
    });

    testWidgets('shows offline with its auto-sync subtitle', (tester) async {
      HoneyChainStore.instance.debugSetOnline(false);
      await tester.pumpWidget(wrap());
      expect(find.textContaining('Offline'), findsOneWidget);
    });

    testWidgets('shows pending uploads while online but not yet synced',
        (tester) async {
      final store = HoneyChainStore.instance;
      store.debugSetOnline(false);
      store.recordHarvest(hive: store.hives.first, quantityKg: 1.0);
      store.debugSetOnline(true);

      await tester.pumpWidget(wrap());
      expect(find.textContaining('Pending local upload'), findsOneWidget);
      expect(store.pendingCount, greaterThan(0));
    });
  });
}