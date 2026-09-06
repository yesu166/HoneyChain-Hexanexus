import 'package:flutter_test/flutter_test.dart';
import 'package:honeychain/data/honeychain_store.dart';
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

  test('END-TO-END demo trace: consumer product lookup resolves full chain', () {
    final product = store.productByCode('HC-TN-00128-A');
    expect(product, isNotNull, reason: 'Product HC-TN-00128-A should exist');

    final batch = store.batchById(product!.parentBatchId);
    expect(batch, isNotNull);
    expect(batch!.code, 'HC-TN-00128');

    final harvests = store.harvestsForBatch(batch);
    expect(harvests.length, 3, reason: '3 source harvests');
    final ids = harvests.map((h) => h.id).toSet();
    expect(ids, containsAll(['harvest-demo-001', 'harvest-demo-002', 'harvest-demo-003']));

    final sum = harvests.fold<double>(0, (a, h) => a + h.quantityKg);
    expect((sum - batch.quantityKg).abs() < 0.01, isTrue, reason: 'harvest sum == batch qty');

    final hives = harvests.map((h) => store.hiveById(h.hiveId)).toList();
    expect(hives.every((h) => h != null), isTrue, reason: 'all source hives exist');

    final verifications = store.verificationsFor(batch);
    expect(verifications, isNotEmpty, reason: 'batch has lab verification');
    expect(verifications.first.status.name, 'pass');

    final processing = store.processingFor(batch);
    expect(processing, isNotEmpty, reason: 'batch has processing event');

    final byBatch = store.batchForPassport('hc-tn-00128');
    expect(byBatch?.id, batch.id);
    final byProduct = store.batchForPassport('hc-tn-00128-a');
    expect(byProduct?.id, batch.id);
  });

  test('reset preserves genealogy links (batch-023 -> harvest-001)', () {
    final b = store.batchById('batch-023');
    expect(b, isNotNull);
    final harvests = store.harvestsForBatch(b!);
    expect(harvests.map((h) => h.id), contains('harvest-001'),
        reason: 'reset must restore seed batch links');
  });

  test('demo batch seeded and product-code source hives correct', () {
    final demo = store.seededDemoBatch();
    expect(demo, isNotNull);
    final hives = store.harvestsForBatch(demo!).map((h) => store.hiveById(h.hiveId)?.name).toList();
    expect(hives.contains('Hive #2'), isTrue);
    expect(hives.contains('Hive #3'), isTrue);
  });
}
