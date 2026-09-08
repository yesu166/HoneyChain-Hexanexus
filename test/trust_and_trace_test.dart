import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/models/domain.dart';
import 'package:honeychain/screens/developer_screen.dart';
import 'package:honeychain/services/trace_qr_service.dart';

/// Phase E: explicit trust tiers, split/merge/correction business rules, the
/// canonical QR contract and runtime resolution — exercised against the store
/// and services, not just the UI.
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

  /// Drives a fresh harvest to a released, verified batch.
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

  group('trust tiers', () {
    test('rise with recorded proof and stay honest about the mock anchor', () {
      final store = HoneyChainStore.instance;
      final batch = releasedBatch(5.0);

      final trust = store.trustFor(batch);
      expect(trust.tier, TrustTier.blockchainAnchored);
      expect(trust.passCount, 1);
      expect(trust.custodyCount, 1);
      expect(trust.anchorCount, greaterThanOrEqualTo(1));
      expect(trust.isPrototypeAnchor, isTrue,
          reason: 'this demo anchors on prototype mock infrastructure');
      expect(
        trust.caveats.any((c) => c.contains('prototype mock infrastructure')),
        isTrue,
      );
      expect(
        trust.caveats.any((c) => c.contains('does NOT certify')),
        isTrue,
      );
      expect(
        trust.claims.any((c) => c.contains('Laboratory verification passed')),
        isTrue,
      );
    });

    test('a lab failure caps the tier until a later pass, and says so', () {
      final store = HoneyChainStore.instance;
      store.recordHarvest(hive: store.hives.first, quantityKg: 5.0);
      final batch = store.activeV2Batch!;
      store.acceptV2Custody(batch);
      store.verifyV2Batch(batch, VerificationStatus.fail);

      var trust = store.trustFor(batch);
      expect(trust.tier, TrustTier.organizationVerified);
      expect(trust.failCount, 1);
      expect(
        trust.claims.any((c) => c.contains('did not pass')),
        isTrue,
      );

      store.verifyV2Batch(batch, VerificationStatus.pass);
      trust = store.trustFor(batch);
      expect(trust.tier, TrustTier.labVerified);
      expect(trust.passCount, 1);
      expect(
        trust.caveats.any((c) => c.contains('passed a later laboratory test')),
        isTrue,
      );
    });

    test('split children inherit the parent tier and record genealogy', () {
      final store = HoneyChainStore.instance;
      store.recordHarvest(hive: store.hives.first, quantityKg: 5.0);
      final parent = store.activeV2Batch!;
      store.acceptV2Custody(parent);
      store.verifyV2Batch(parent, VerificationStatus.pass);

      final children = store.splitBatchInto(parent, [2.0, 3.0]);
      expect(children.length, 2);
      expect(children.map((c) => c.code).toSet().length, 2,
          reason: 'every child gets its own code');
      expect(children.map((c) => c.code).toSet().contains(parent.code), isFalse);

      for (final child in children) {
        final trust = store.trustFor(child);
        expect(trust.tier, TrustTier.labVerified,
            reason: 'child inherits the verified history of its parent');
        final splitEvent = store
            .eventsFor(child)
            .where((e) => e.type == 'SPLIT_FROM' && e.description.contains(parent.code));
        expect(splitEvent, isNotEmpty);
      }
    });

    test('merge is only as trusted as the weakest child', () {
      final store = HoneyChainStore.instance;
      final strong =
          releasedBatch(5.0); // custody + lab pass + mock anchor

      store.recordHarvest(hive: store.hives.first, quantityKg: 3.0);
      final weak = store.activeV2Batch!; // self-declared only

      final merged = store.mergeBatchesFrom([strong, weak]);
      expect(merged.quantityKg, closeTo(8.0, 0.001));
      final trust = store.trustFor(merged);
      expect(trust.tier, TrustTier.selfDeclared,
          reason: 'a self-declared lot drags the merged tier down');
      expect(
        trust.caveats.any((c) => c.contains('weakest child')),
        isTrue,
      );

      // Two verified lots produce a verified, honest merged result.
      final anotherStrong =
          releasedBatch(2.0); // custody + lab pass + mock anchor
      final verifiedMerge = store.mergeBatchesFrom([anotherStrong, strong]);
      final vTrust = store.trustFor(verifiedMerge);
      expect(vTrust.tier, TrustTier.blockchainAnchored);
      expect(vTrust.isPrototypeAnchor, isTrue);
    });

    test('split enforces quantity parity instead of silently cheating', () {
      final store = HoneyChainStore.instance;
      final batch = releasedBatch(5.0);
      expect(
        () => store.splitBatchInto(batch, [1.0]),
        throwsArgumentError,
      );
    });

    test('corrections append to the trail without rewriting history', () {
      final store = HoneyChainStore.instance;
      store.recordHarvest(hive: store.hives.first, quantityKg: 5.0);
      final batch = store.activeV2Batch!;
      final eventsBefore = store.eventsFor(batch).length;

      final corrected = store.correctBatch(
        batch,
        description: 'Weight corrected on re-weighing.',
        quantityKg: 4.5,
      );

      expect(corrected.quantityKg, closeTo(4.5, 0.001));
      final events = store.eventsFor(corrected);
      expect(events.length, eventsBefore + 1,
          reason: 'a correction appends, it never rewrites');
      expect(
        events.any((e) => e.type == 'CORRECTION'
            && e.description.contains('Weight corrected')),
        isTrue,
      );
      expect(
        events.any((e) => e.type == 'CORRECTION'), isTrue);
      expect(
        events.first.type == 'CREATED',
        isTrue,
        reason: 'the original creation event is still the first record',
      );
    });
  });

  group('canonical QR contract', () {
    test('build and parse round-trip for products and jars', () {
      final productPayload =
          TraceQrService.buildForProduct('HC-TN-00128-C');
      expect(productPayload, 'honeychain://trace/HC-TN-00128-C');

      final parsedProduct = TraceQrService.parse(productPayload)!;
      expect(parsedProduct.isTrace, isTrue);
      expect(parsedProduct.isJar, isFalse);
      expect(parsedProduct.code, 'HC-TN-00128-C');

      final jarPayload = TraceQrService.buildForJar('JAR-HC-000001');
      expect(jarPayload, 'honeychain://jar/JAR-HC-000001');
      final parsedJar = TraceQrService.parse(jarPayload)!;
      expect(parsedJar.isJar, isTrue);
      expect(parsedJar.code, 'JAR-HC-000001');
    });

    test('rejects foreign, empty and malformed payloads', () {
      expect(TraceQrService.isValid(null), isFalse);
      expect(TraceQrService.isValid(''), isFalse);
      expect(TraceQrService.isValid('  '), isFalse);
      expect(TraceQrService.isValid('https://other.example/q'), isFalse);
      expect(TraceQrService.isValid('honeychain://'), isFalse);
      expect(TraceQrService.isValid('honeychain://trace'), isFalse);
      expect(TraceQrService.isValid('honeychain://trace/'), isFalse);
      expect(TraceQrService.isValid('honeychain://jar/'), isFalse);
      expect(TraceQrService.isValid('honeychain://other/ABC'), isFalse);
    });
  });

  group('runtime scan resolution', () {
    test('resolves product, jar and batch payloads against real records', () {
      final store = HoneyChainStore.instance;
      final productParent = releasedBatch(5.0);
      final product = store.createProductBatch(
        productParent,
        ProductSize.size100g,
      );

      final jarParent = releasedBatch(5.0);
      final jars = store.allocateAndCreateJars(
        batch: jarParent,
        allocatedKg: 1.0,
        jarSizeGrams: 500,
        buyerId: 'BUYER-DEMO-001',
      );
      final jar = jars.first;

      // Batch with no jars/products = unambiguous batch payload.
      final plainBatch = releasedBatch(5.0);

      final productRes = store.resolveScan(
        TraceQrService.buildForProduct(product.productCode),
      );
      expect(productRes, isA<ScanResolutionProduct>());
      expect((productRes as ScanResolutionProduct).product.productCode,
          product.productCode);

      final jarRes = store.resolveScan(TraceQrService.buildForJar(jar.jarId));
      expect(jarRes, isA<ScanResolutionJar>());
      expect((jarRes as ScanResolutionJar).jar.jarId, jar.jarId);

      final batchTraceRes = store.resolveScan(
        TraceQrService.buildForProduct(plainBatch.code),
      );
      expect(batchTraceRes, isA<ScanResolutionBatch>());
      expect((batchTraceRes as ScanResolutionBatch).batch.code,
          plainBatch.code);

      final bareRes = store.resolveScan(plainBatch.code);
      expect(bareRes, isA<ScanResolutionBatch>());
      expect((bareRes as ScanResolutionBatch).batch.code, plainBatch.code);
    });

    test('unknown codes and non-app schemes resolve to unknown', () {
      final store = HoneyChainStore.instance;
      releasedBatch(5.0);

      expect(store.resolveScan('HC-TN-99999'), isA<ScanResolutionUnknown>());
      expect(
        store.resolveScan(TraceQrService.buildForJar('JAR-HC-999999')),
        isA<ScanResolutionUnknown>(),
      );
      expect(store.resolveScan('not even a code'), isA<ScanResolutionUnknown>());
      expect(store.resolveScan(''), isA<ScanResolutionUnknown>());
    });
  });

  group('developer screen', () {
    testWidgets('is functional: reset + live trust + debug panel', (
      tester,
    ) async {
      final store = HoneyChainStore.instance;
      await tester.pumpWidget(
        const MaterialApp(home: DeveloperScreen()),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;

      Future<void> scrollTo(String text) async {
        try {
          await tester.scrollUntilVisible(
            find.text(text),
            120,
            scrollable: scrollable,
          );
        } catch (_) {
          await tester.scrollUntilVisible(
            find.text(text),
            -120,
            scrollable: scrollable,
          );
        }
        await tester.pumpAndSettle();
      }

      expect(find.text('Demo Data & Reset'), findsOneWidget);

      // The live trust panel shows a seeded batch code + tier.
      expect(find.textContaining('HC-TN'), findsOneWidget);

      // Lab pass extends the seeded demo batch's proof.
      final target =
          store.seededDemoBatch() ??
          (store.batches.isNotEmpty ? store.batches.first : null);
      final passesBefore = store.trustFor(target!).passCount;
      await scrollTo('Lab pass');
      await tester.tap(find.text('Lab pass'));
      await tester.pumpAndSettle();
      expect(store.trustFor(target).passCount, passesBefore + 1);

      // Debug panel exists further down.
      await scrollTo('Debug');
      expect(find.text('Debug'), findsOneWidget);
      expect(find.text('Batches'), findsOneWidget);

      // Reset restores the deterministic seed.
      await scrollTo('Reset all demo data');
      await tester.tap(find.text('Reset all demo data'));
      await tester.pumpAndSettle();
      expect(store.trustFor(target).passCount, passesBefore);
    });
  });
}