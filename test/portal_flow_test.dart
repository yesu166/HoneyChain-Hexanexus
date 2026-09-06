import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/main.dart';
import 'package:honeychain/models/domain.dart';

/// End-to-end UI flows for the v2 demo: FPO custody -> lab -> explicit
/// blockchain anchor -> release -> buyer allocation -> per-jar provenance ->
/// consumer jar passport. These drive the actual screens, not just the store.
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

  Finder scrollable() => find.byType(Scrollable).hitTestable().first;

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      try {
        await tester.scrollUntilVisible(finder, 200, scrollable: scrollable());
      } catch (_) {
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

  /// Records a harvest and drives it through custody/lab/anchor/release on the
  /// store so the released batch is ready for the buyer screens.
  Batch releasedBatch(double qtyKg) {
    final store = HoneyChainStore.instance;
    store.recordHarvest(hive: store.hives.first, quantityKg: qtyKg);
    final batch = store.activeV2Batch!;
    store.acceptV2Custody(batch);
    store.verifyV2Batch(batch, VerificationStatus.pass);
    store.anchorV2Batch(batch, 'BATCH_VERIFIED');
    store.releaseV2BatchToMarket(batch);
    return store.batchById(batch.id)!;
  }

  Future<void> openRoleGate(WidgetTester tester) async {
    await tester.pumpWidget(const HoneyChainApp());
    await tester.pumpAndSettle();
  }

  /// Gate -> "Organization / FPO" -> org login -> portal.
  Future<void> openOrgPortal(WidgetTester tester) async {
    await openRoleGate(tester);
    await see(tester, 'Organization / FPO');
    await tester.tap(find.text('Organization / FPO'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Collector');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }

  Future<void> openBatchDetail(WidgetTester tester, Batch batch) async {
    await tester.tap(find.text(batch.code).first);
    await tester.pumpAndSettle();
  }

  testWidgets('org portal: custody, lab, explicit anchor and release via UI', (
    tester,
  ) async {
    final store = HoneyChainStore.instance;
    store.recordHarvest(hive: store.hives.first, quantityKg: 5.0);
    final batch = store.activeV2Batch!;

    await openOrgPortal(tester);
    await see(tester, 'Organization Portal');
    await see(tester, batch.code);

    await openBatchDetail(tester, batch);
    await see(tester, 'CUSTODY & INTAKE');

    // Accept custody.
    await see(tester, 'Accept custody');
    await tester.tap(find.text('Accept custody'));
    await tester.pumpAndSettle();
    expect(store.custodyFor(batch), isNotEmpty);
    expect(
      find.text('Custody accepted from beekeeper'),
      findsWidgets,
      reason: 'card + toast both confirm custody acceptance',
    );

    // Lab verify (demo) — never anchors automatically.
    await see(tester, 'Verify at lab (demo)');
    await tester.tap(find.text('Verify at lab (demo)'));
    await tester.pumpAndSettle();
    expect(store.verificationsFor(batch).first.status, VerificationStatus.pass);
    expect(store.anchorsFor(batch), isEmpty,
        reason: 'lab pass must not auto-anchor the batch');

    // Anchor is now enabled and shows the guard hint before releasing.
    await see(tester, 'Anchor the batch before releasing to market.');

    // Cancel first — nothing is anchored.
    await reveal(tester, find.text('Anchor to blockchain'));
    await tester.tap(find.text('Anchor to blockchain'));
    await tester.pumpAndSettle();
    await see(tester, 'Anchor batch to blockchain?');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.anchorsFor(batch), isEmpty);

    // Confirm — the batch is anchored.
    await reveal(tester, find.text('Anchor to blockchain'));
    await tester.tap(find.text('Anchor to blockchain'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anchor now'));
    await tester.pumpAndSettle();
    expect(store.anchorsFor(batch), isNotEmpty);

    // Release to market.
    await reveal(tester, find.text('Release to market'));
    await tester.tap(find.text('Release to market'));
    await tester.pumpAndSettle();
    expect(store.batchById(batch.id)!.status, BatchStatus.listed);
    await see(tester, 'This batch is live on the marketplace for buyers.');

    // No jars yet.
    await see(tester, 'No jars packaged for this batch yet. A buyer allocation creates jars here.');
  });

  testWidgets('buyer portal only lists released batches', (tester) async {
    final store = HoneyChainStore.instance;
    store.recordHarvest(hive: store.hives.first, quantityKg: 5.0);
    final unreleased = store.activeV2Batch!;

    await openRoleGate(tester);
    await see(tester, 'Buyer');
    await tester.tap(find.text('Buyer'));
    await tester.pumpAndSettle();

    await see(tester, 'Buyer Portal');
    expect(find.text(unreleased.code), findsNothing,
        reason: 'an unreleased batch must never reach the buyer portal');
  });

  testWidgets('buyer allocates jars and the org sees + anchors packaging', (
    tester,
  ) async {
    final store = HoneyChainStore.instance;
    final batch = releasedBatch(5.0);
    final beforeJars = store.jars.length;

    // Buyer portal -> allocate 2.0 kg (default) into 500g jars.
    await openRoleGate(tester);
    await see(tester, 'Buyer');
    await tester.tap(find.text('Buyer'));
    await tester.pumpAndSettle();
    await see(tester, 'Buyer Portal');
    await see(tester, batch.code);

    await reveal(tester, find.text('Allocate & Package'));
    await tester.tap(find.text('Allocate & Package'));
    await tester.pumpAndSettle();
    await see(tester, 'Batch Allocation & Packaging');

    // Confirm dialog -> create jars.
    await reveal(tester, find.text('Confirm & Create Jars'));
    await tester.tap(find.text('Confirm & Create Jars'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Confirm & Create Jars').last,
    );
    await tester.pumpAndSettle();

    final jars = store.jars.skip(beforeJars).toList();
    expect(jars.length, 4, reason: '2.0 kg / 500 g jar = 4 jars');
    await see(tester, 'Created 4 Individual Jars');
    await see(tester, jars.first.jarId);

    // The 100g-friendly split leaves exactly 3.0 kg on the listing.
    final listing = store.marketplaceListings
        .where((l) => l.batchId == batch.id)
        .first;
    expect(listing.effectiveRemainingKg, closeTo(3.0, 0.001));

    // Return to the role gate, then enter the org portal as the FPO.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('Return to Portal'));
await tester.tap(find.text('Return to Portal'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openOrgPortal(tester);
    await see(tester, batch.code);
    await openBatchDetail(tester, batch);

    // Jars & packaging provenance section shows the packaging batch + jars.
    await see(tester, 'JARS & PACKAGING PROVENANCE');
    await see(tester, jars.first.packagingBatchId);
    await see(tester, '4 jars · 500g');

    // Per-jar passport opens from the tile.
    await reveal(tester, find.text('View Passport').first);
    await tester.tap(find.text('View Passport').first);
    await tester.pumpAndSettle();
    await see(tester, 'Honey Passport');
    await see(tester, jars.first.jarId);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Anchor packaging.
    await reveal(tester, find.text('Anchor packaging'));
    await tester.tap(find.text('Anchor packaging'));
    await tester.pumpAndSettle();
    final pb = store.packagingBatchById(jars.first.packagingBatchId);
    expect(pb, isNotNull);
    final packagingAnchors = store.anchorsFor(batch).where(
          (a) => a.packagingBatchId == jars.first.packagingBatchId,
        );
    expect(packagingAnchors, isNotEmpty);
    expect(
      store.packagingBatchById(jars.first.packagingBatchId)!.status,
      'ANCHORED',
    );
    // StatusPill uppercases its label, so the pill reads "PACKAGING ANCHORED".
    await tester.dragUntilVisible(
      find.text('PACKAGING ANCHORED'),
      find.byType(Scrollable).first,
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    expect(find.text('PACKAGING ANCHORED'), findsOneWidget);
  });

  testWidgets('consumer scans a jar payload and opens the jar passport', (
    tester,
  ) async {
    final store = HoneyChainStore.instance;
    final batch = releasedBatch(5.0);
    final jars = store.allocateAndCreateJars(
      batch: batch,
      allocatedKg: 1.0,
      jarSizeGrams: 500,
      buyerId: 'BUYER-DEMO-001',
    );
    final jar = jars.first;

    await openRoleGate(tester);
    await see(tester, 'Consumer');
    await tester.tap(find.text('Consumer'));
    await tester.pumpAndSettle();
    await see(tester, 'Verify Your Honey');

    // Paste the deterministic QR payload exactly as a vending QR encodes it.
    await tester.enterText(
      find.byType(TextField).first,
      'honeychain://jar/${jar.jarId}',
    );
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    await see(tester, 'Honey Passport');
    await see(tester, jar.jarId);
    expect(find.text(batch.code), findsWidgets,
        reason: 'jar passport retains the source batch genealogy');
  });

  testWidgets('consumer batch lookup still opens the batch passport', (
    tester,
  ) async {
    final batch = releasedBatch(3.0);

    await openRoleGate(tester);
    await see(tester, 'Consumer');
    await tester.tap(find.text('Consumer').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, batch.code);
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    await see(tester, 'Honey Passport');
    expect(find.text(batch.code), findsWidgets,
        reason: 'batch passport surfaces the batch id');
  });
}