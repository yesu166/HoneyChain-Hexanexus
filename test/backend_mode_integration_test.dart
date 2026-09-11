import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/core/api/api_config.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/models/domain.dart';
import 'package:honeychain/services/honey_api_service.dart';
import 'package:honeychain/services/local_store.dart';

/// Integration wiring between the offline-first store and the optional
/// FastAPI backend (beekeeper path). These tests run without a compiled
/// API_BASE_URL and without any network, so they prove the offline-first
/// contract stays intact and that backend actions degrade safely instead of
/// ever silently faking a success.
void main() {
  setUp(() {
    HoneyChainStore.testMode = true;
    SharedPreferences.setMockInitialValues({});
    final store = HoneyChainStore.instance;
    store.ensureStarted();
    store.resetToDemo();
    store.clearSyncErrors();
  });

  group('backend-mode guards', () {
    test('test build never hardcodes a live backend URL', () {
      expect(ApiConfig.isConfigured, isFalse,
          reason: 'the test build must not compile in a production URL');
      expect(HoneyChainStore.instance.backendModeActive, isFalse);
    });

    test('backend actions no-op (never fake a success) when unconfigured',
        () async {
      final store = HoneyChainStore.instance;
      final hive = store.hives.first;
      store.recordHarvest(hive: hive, quantityKg: 1.5);

      final pushed =
          await store.pushHarvestToBackend(store.harvests.last);
      expect(pushed, isNull,
          reason: 'must not claim a server row exists without a backend');

      final created =
          await store.addHiveToBackend(name: 'Mango Apiary', location: 'TN');
      expect(created, isNull);

      final anchored = await store.anchorHarvestEvidence(
        harvest: store.harvests.last,
        serverHarvestId: 'server-harvest-1',
      );
      expect(anchored, isNull,
          reason: 'must not fabricate a Fabric-anchored bundle');

      final verified = await store.verifyLastBundle();
      expect(verified, isNull);
    });

    test('offline harvest stays queued locally even with the backend absent',
        () async {
      final store = HoneyChainStore.instance;
      store.debugSetOnline(false);
      final hive = store.hives.first;

      store.recordHarvest(hive: hive, quantityKg: 2.0);

      expect(
        store.harvests
            .where((h) => h.syncStatus == SyncStatus.pending),
        isNotEmpty,
        reason: 'offline-first write must be queued locally',
      );
      expect(store.pendingCount, greaterThan(0));
    });
  });

  group('server row mapping (beekeeper UI wiring)', () {
    test('hiveFromServer maps backend columns into the local Hive shape', () {
      final store = HoneyChainStore.instance;
      final server = ServerHive(
        id: 'h-server-7',
        hiveCode: 'HC-LIVE-007',
        beekeeperId: 'u-bk-7',
        orgId: 'ORG-TN-001',
        status: 'active',
        clientId: 'cli-7',
        location: 'Nilgiris',
      );

      final hive = store.hiveFromServer(server);
      expect(hive.id, 'h-server-7');
      expect(hive.name, 'HC-LIVE-007');
      expect(hive.organizationId, 'ORG-TN-001');
      expect(hive.location, 'Nilgiris');
      expect(hive.detail, contains('active'));
    });

    test('harvestFromServer maps collected + synced status', () {
      final store = HoneyChainStore.instance;
      final collected = ServerHarvest(
        id: 'hv-server-1',
        hiveId: 'h-server-7',
        beekeeperId: 'u-bk-7',
        harvestedAt: DateTime.utc(2026, 9, 10),
        quantityKg: 3.5,
        honeyType: 'Wild Forest',
        clientId: 'cli-7',
        collected: true,
      );

      final harvest = store.harvestFromServer(collected);
      expect(harvest.id, 'hv-server-1');
      expect(harvest.quantityKg, 3.5);
      expect(harvest.honeyType, 'Wild Forest');
      expect(harvest.syncStatus, SyncStatus.synced);
      expect(harvest.status, HarvestStatus.collected);

      final pendingStoreHarvest = ServerHarvest(
        id: 'hv-server-2',
        hiveId: 'h-server-7',
        beekeeperId: 'u-bk-7',
        harvestedAt: DateTime.utc(2026, 9, 11),
        quantityKg: 1.0,
        honeyType: 'Wild Forest',
        clientId: 'cli-8',
        collected: false,
      );
      expect(store.harvestFromServer(pendingStoreHarvest).status,
          HarvestStatus.pending);
    });
  });

  group('restart durability of the pending queue', () {
    test('a pending harvest is persisted on disk and survives a restart',
        () async {
      final store = HoneyChainStore.instance;
      store.debugSetOnline(false);
      final hive = store.hives.first;

      final before = LocalStore.instance.loadHarvests() ?? const [];
      store.recordHarvest(hive: hive, quantityKg: 1.5);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final onDisk = LocalStore.instance.loadHarvests() ?? const [];
      expect(onDisk.length, greaterThan(before.length),
          reason: 'new offline harvest must be written to durable storage');
      expect(
        onDisk.any(
          (h) => h.quantityKg == 1.5 && h.syncStatus == SyncStatus.pending,
        ),
        isTrue,
        reason: 'the queued record must come back pending after a restart',
      );
    });
  });
}