import 'package:flutter_test/flutter_test.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/models/domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HoneyChainStore.testMode = true;

  late HoneyChainStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = HoneyChainStore.instance;
    await store.ensureStarted();
    store.resetToDemo();
  });

  test('recording a harvest auto-batches it as collected (no double offer)',
      () {
    final hive = store.hives.first;
    final harvest = store.recordHarvest(hive: hive, quantityKg: 1.5);
    expect(harvest.collected, isTrue,
        reason: 'auto-batch is the FPO collection step, so mark collected');

    final batch = store.activeV2Batch;
    expect(batch, isNotNull);
    expect(batch!.quantityKg, closeTo(1.5, 0.001));
    final linked = store.harvestsForBatch(batch);
    expect(linked.map((h) => h.id), contains(harvest.id),
        reason: 'harvest and batch share lineage');

    expect(
      store.incomingHarvests.map((h) => h.id),
      isNot(contains(harvest.id)),
      reason: 'auto-batched harvest is not re-offered as incoming',
    );
    expect(
      store.collectedHarvests.map((h) => h.id),
      isNot(contains(harvest.id)),
      reason: 'auto-batched harvest is not re-offered for consolidation',
    );
  });

  test('lab verification never anchors blockchain automatically', () {
    store.recordHarvest(hive: store.hives.first, quantityKg: 2.0);
    final batch = store.activeV2Batch!;

    store.acceptV2Custody(batch);
    expect(store.custodyFor(batch), isNotEmpty);

    store.verifyV2Batch(batch, VerificationStatus.pass);
    expect(store.verificationsFor(batch).first.status, VerificationStatus.pass);

    expect(store.anchorsFor(batch), isEmpty,
        reason: 'Section 11/13: lab pass must not auto-anchor');

    store.anchorV2Batch(batch, 'BATCH_VERIFIED');
    expect(store.anchorsFor(batch), isNotEmpty,
        reason: 'anchor happens only on explicit user action');
  });

  test('release lists only the quantity and keeps the batch out of buyer view '
      'before release', () {
    store.recordHarvest(hive: store.hives.first, quantityKg: 3.0);
    final batch = store.activeV2Batch!;

    expect(
      store.marketplaceListings.where((l) => l.batchId == batch.id),
      isEmpty,
      reason: 'no listing before release',
    );

    store.acceptV2Custody(batch);
    store.verifyV2Batch(batch, VerificationStatus.pass);
    store.anchorV2Batch(batch, 'BATCH_VERIFIED');
    final listing = store.releaseV2BatchToMarket(batch);

    expect(listing.batchId, batch.id);
    expect(listing.effectiveRemainingKg, closeTo(3.0, 0.001));
    expect(store.batchById(batch.id)!.status, BatchStatus.listed);
  });

  test('jar split keeps whole jars and leaves the remainder on the listing',
      () {
    store.recordHarvest(hive: store.hives.first, quantityKg: 5.0);
    final batch = store.activeV2Batch!;
    store.acceptV2Custody(batch);
    store.verifyV2Batch(batch, VerificationStatus.pass);
    store.anchorV2Batch(batch, 'BATCH_VERIFIED');
    store.releaseV2BatchToMarket(batch);

    final jars = store.allocateAndCreateJars(
      batch: batch,
      allocatedKg: 2.1,
      jarSizeGrams: 500,
      buyerId: 'BUYER-TEST-001',
    );

    expect(jars.length, 4,
        reason: 'only whole 500g jars are packed (2.0 kg), not 2.1 kg');
    expect(
      jars.every((j) => j.quantityGrams == 500),
      isTrue,
    );
    expect(
      jars.every((j) => j.qrPayload == 'honeychain://jar/${j.jarId}'),
      isTrue,
      reason: 'jar QR payload is the deterministic honeychain://jar handle',
    );

    final listing = store.marketplaceListings
        .where((l) => l.batchId == batch.id)
        .first;
    expect(listing.effectiveRemainingKg, closeTo(3.0, 0.001),
        reason: 'the 0.1 kg remainder stays available instead of being lost');
  });

  test('consumer resolveJar maps a honeychain://jar payload to the passport',
      () {
    store.recordHarvest(hive: store.hives.first, quantityKg: 5.0);
    final batch = store.activeV2Batch!;
    store.acceptV2Custody(batch);
    store.verifyV2Batch(batch, VerificationStatus.pass);
    store.anchorV2Batch(batch, 'BATCH_VERIFIED');
    store.releaseV2BatchToMarket(batch);

    final jars = store.allocateAndCreateJars(
      batch: batch,
      allocatedKg: 1.0,
      jarSizeGrams: 500,
      buyerId: 'BUYER-TEST-002',
    );
    final jar = jars.first;

    final byPayload = store.resolveJar('honeychain://jar/${jar.jarId}');
    expect(byPayload?.jarId, jar.jarId);
    final byPlain = store.resolveJar(jar.jarId.toLowerCase());
    expect(byPlain?.jarId, jar.jarId);
    expect(store.resolveJar('honeychain://jar/NOPE-000000'), isNull);

    expect(store.jarsFor(batch).length, jars.length);
    expect(store.jarById(jar.jarId)?.sourceBatchId, batch.id,
        reason: 'jar keeps lineage to its source batch');
  });
}