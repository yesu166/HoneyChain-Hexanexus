import '../data/demo_seed.dart';
import '../models/disease.dart';
import '../models/domain.dart';
import '../bee_health/models/bee_health_models.dart';

abstract class HoneychainRepository {
  List<Hive> hivesForBeekeeper(String beekeeperId);
  void addHive(Hive hive);
  List<HiveReading> readingsForHive(String hiveId);
  List<Harvest> harvestsForBeekeeper(String beekeeperId);
  List<Batch> get batches;
  List<BatchHarvest> harvestsForBatch(String batchId);
  List<LabVerification> verificationsForBatch(String batchId);
  List<CustodyEvent> custodyForBatch(String batchId);
  List<BlockchainAnchor> anchorsForBatch(String batchId);
  List<AuditEvent> eventsForBatch(String batchId);
  List<BatchRelation> relationsForBatch(String batchId);
  List<MarketplaceListing> get listings;
  List<CustodyEvent> get allCustody;
  List<BlockchainAnchor> get allAnchors;
  List<ProcessingEvent> get allProcessing;
  List<BatchRelation> get allRelations;
  List<PurchaseRequest> get allRequests;
  List<QRPassport> get allPassports;
  QRPassport? passportForSlug(String slug);
  void addHarvest(Harvest harvest);
  void addBatch(Batch batch, List<BatchHarvest> harvestLinks);
  void updateBatch(Batch batch);
  void addVerification(LabVerification verification);
  void addCustody(CustodyEvent event);
  void addAnchor(BlockchainAnchor anchor);
  void addEvent(AuditEvent event);
  void addRelation(BatchRelation relation);
  void addListing(MarketplaceListing listing);
  void addPurchaseRequest(PurchaseRequest request);
  void addPassport(QRPassport passport);

  // Organization / FPO flow (v2 demo)
  List<Harvest> get allHarvests;
  void updateHarvestStatus(Harvest harvest, HarvestStatus status);
  List<ProcessingEvent> processingFor(String batchId);
  void addProcessingEvent(ProcessingEvent event);
  List<ProductBatch> get productBatches;
  List<ProductBatch> productBatchesFor(String parentBatchId);
  void addProductBatch(ProductBatch product);

  // Packaging & Jars (v3 supply chain)
  List<PackagingBatch> get packagingBatches;
  PackagingBatch? packagingBatchById(String id);
  List<PackagingBatch> packagingBatchesForBatch(String batchId);
  void addPackagingBatch(PackagingBatch batch);
  void updatePackagingBatch(PackagingBatch batch);
  List<HoneyJar> get jars;
  HoneyJar? jarById(String jarId);
  List<HoneyJar> jarsForPackagingBatch(String packagingBatchId);
  List<HoneyJar> jarsForBatch(String batchId);
  void addJar(HoneyJar jar);
  void addJars(List<HoneyJar> jars);
  void updateJar(HoneyJar jar);
  void updateListing(MarketplaceListing listing);

  // Offline-first additions
  List<HiveAlert> get alerts;
  void addAlert(HiveAlert alert);
  void removeAlertsForHive(String hiveId, AlertType type);
  void updateHarvest(Harvest harvest);
  void replaceAll({
    List<Hive>? hives,
    List<Harvest>? harvests,
    List<Batch>? batches,
    List<LabVerification>? verifications,
    List<HiveAlert>? alerts,
    List<HealthCheckEvent>? healthChecks,
    List<BeeHealthEvent>? beeHealthEvents,
    List<TreatmentRecord>? treatments,
    List<BeeHealthFollowUp>? followUps,
    List<CustodyEvent>? custody,
    List<BlockchainAnchor>? anchors,
    List<ProcessingEvent>? processing,
    List<BatchRelation>? relations,
    List<ProductBatch>? productBatches,
    List<PackagingBatch>? packagingBatches,
    List<HoneyJar>? jars,
    List<MarketplaceListing>? listings,
    List<PurchaseRequest>? requests,
    List<QRPassport>? passports,
  });

  // Disease screening (offline-first)
  List<HealthCheckEvent> get healthChecks;
  void addHealthCheck(HealthCheckEvent event);

  // Bee health (offline-first)
  List<BeeHealthEvent> get beeHealthEvents;
  void addBeeHealthEvent(BeeHealthEvent event);
  List<TreatmentRecord> get treatments;
  void addTreatment(TreatmentRecord record);
  void replaceTreatments(List<TreatmentRecord> records);
  List<BeeHealthFollowUp> get followUps;
  void addFollowUp(BeeHealthFollowUp followUp);
  void replaceFollowUps(List<BeeHealthFollowUp> followUps);

  void reset();
}

class LocalHoneychainRepository implements HoneychainRepository {
  LocalHoneychainRepository({this.seedDemo = true}) {
    if (seedDemo) _seedStartupData();
  }

  /// When true (demo / widget tests / Developer mode) the repository starts
  /// with the deterministic demo genealogy. Production builds keep the local
  /// store empty until real records arrive (offline-first sync pull).
  final bool seedDemo;

  void _seedStartupData() {
    _hives.addAll(DemoSeed.hives);
    _harvests.addAll(DemoSeed.harvests);
    _batches.addAll(DemoSeed.batches);
    _batchHarvests.addAll(DemoSeed.batchLinks);
    _verifications.addAll(DemoSeed.verifications);
    _alerts.addAll(DemoSeed.alerts);
    _seedDemoProductFlow();
  }

  /// Seeds a ready end-to-end genealogy: 3 hives -> 1 consolidated batch
  /// (HC-TN-00128) -> lab -> processing -> product batch -> QR passport.
  /// Deterministic demo data so the full demo works without building it up.
  void _seedDemoProductFlow() {
    final h1 = 'harvest-demo-001';
    final h2 = 'harvest-demo-002';
    final h3 = 'harvest-demo-003';
    _harvests.addAll([
      Harvest(
        id: h1,
        hiveId: 'hive-001',
        beekeeperId: 'user-ravi',
        harvestedAt: DateTime(2026, 8, 20),
        honeyType: 'Floral Honey',
        quantityKg: 28.4,
        status: HarvestStatus.collected,
      ),
      Harvest(
        id: h2,
        hiveId: 'hive-002',
        beekeeperId: 'user-ravi',
        harvestedAt: DateTime(2026, 8, 21),
        honeyType: 'Mustard Honey',
        quantityKg: 19.2,
        status: HarvestStatus.collected,
      ),
      Harvest(
        id: h3,
        hiveId: 'hive-003',
        beekeeperId: 'user-ravi',
        harvestedAt: DateTime(2026, 8, 22),
        honeyType: 'Neem Honey',
        quantityKg: 33.8,
        status: HarvestStatus.collected,
      ),
    ]);

    final batch = Batch(
      id: 'batch-demo-128',
      code: 'HC-TN-00128',
      organizationId: 'ORG-TN-001',
      honeyType: 'Multi-Flora',
      origin: 'Local Apiary',
      quantityKg: 81.4,
      createdAt: DateTime(2026, 8, 23),
      status: BatchStatus.completed,
      displayStatus: BatchDisplayStatus.verified,
    );
    _batches.add(batch);
    _batchHarvests.addAll([
      BatchHarvest(batchId: batch.id, harvestId: h1, quantityKg: 28.4),
      BatchHarvest(batchId: batch.id, harvestId: h2, quantityKg: 19.2),
      BatchHarvest(batchId: batch.id, harvestId: h3, quantityKg: 33.8),
    ]);
    _verifications.add(LabVerification(
      id: 'batch-demo-128-lab',
      batchId: batch.id,
      labOrganizationId: DemoSeed.lab.id,
      status: VerificationStatus.pass,
      testedAt: DateTime(2026, 8, 24, 16),
      summary:
          'Moisture and sugar profile are within expected ranges. Demo lab reference LAB-DEMO-00128.',
      evidence: [
        EvidenceFile(
          id: 'lrf128',
          name: 'lab-report-HC-TN-00128.pdf',
          mimeType: 'application/pdf',
          uploadedAt: DateTime(2026, 8, 24, 16),
        ),
      ],
    ));
    _passports.add(QRPassport(
      slug: 'hc-tn-00128',
      batchId: batch.id,
      createdAt: DateTime(2026, 8, 23),
    ));
    _passports.add(QRPassport(
      slug: 'hc-tn-00128-a',
      batchId: batch.id,
      createdAt: DateTime(2026, 8, 26, 10),
    ));
    _processing.add(ProcessingEvent(
      id: 'proc-demo-128',
      batchId: batch.id,
      unit: 'Nilgiri Honey Unit',
      date: DateTime(2026, 8, 25),
      status: 'COMPLETED',
    ));
    _productBatches.add(ProductBatch(
      id: 'prod-demo-128-a',
      productCode: 'HC-TN-00128-A',
      parentBatchId: batch.id,
      size: ProductSize.size500ml,
      createdAt: DateTime(2026, 8, 26, 10),
    ));
  }

  final List<Hive> _hives = [];
  final List<Harvest> _harvests = [];
  final List<Batch> _batches = [];
  final List<BatchHarvest> _batchHarvests = [];
  final List<LabVerification> _verifications = [];
  final List<HiveAlert> _alerts = [];
  final List<CustodyEvent> _custody = [];
  final List<BlockchainAnchor> _anchors = [];
  final List<AuditEvent> _events = [];
  final List<BatchRelation> _relations = [];
  final List<MarketplaceListing> _listings = [];
  final List<PurchaseRequest> _requests = [];
  final List<QRPassport> _passports = [];
  final List<HealthCheckEvent> _healthChecks = [];
  final List<BeeHealthEvent> _beeHealthEvents = [];
  final List<TreatmentRecord> _treatments = [];
  final List<BeeHealthFollowUp> _followUps = [];

  // Organization / FPO flow (v2 demo)
  final List<ProcessingEvent> _processing = [];
  final List<ProductBatch> _productBatches = [];
  final List<PackagingBatch> _packagingBatches = [];
  final List<HoneyJar> _jars = [];

  @override
  List<Hive> hivesForBeekeeper(String beekeeperId) =>
      _hives.where((hive) => hive.beekeeperId == beekeeperId).toList();

  @override
  void addHive(Hive hive) => _hives.add(hive);

  @override
  List<HiveReading> readingsForHive(String hiveId) =>
      DemoSeed.readingsFor(hiveId);

  @override
  List<Harvest> harvestsForBeekeeper(String beekeeperId) =>
      _harvests.where((harvest) => harvest.beekeeperId == beekeeperId).toList();

  @override
  List<Batch> get batches => List.unmodifiable(_batches);

  @override
  List<BatchHarvest> harvestsForBatch(String batchId) =>
      _batchHarvests.where((link) => link.batchId == batchId).toList();

  @override
  List<LabVerification> verificationsForBatch(String batchId) =>
      _verifications.where((item) => item.batchId == batchId).toList();

  @override
  List<CustodyEvent> custodyForBatch(String batchId) =>
      _custody.where((item) => item.batchId == batchId).toList();

  @override
  List<BlockchainAnchor> anchorsForBatch(String batchId) =>
      _anchors.where((item) => item.batchId == batchId).toList();

  @override
  List<AuditEvent> eventsForBatch(String batchId) =>
      _events.where((item) => item.batchId == batchId).toList();

  @override
  List<BatchRelation> relationsForBatch(String batchId) => _relations
      .where(
        (item) => item.parentBatchId == batchId || item.childBatchId == batchId,
      )
      .toList();

  @override
  List<MarketplaceListing> get listings => List.unmodifiable(_listings);

  @override
  List<CustodyEvent> get allCustody => List.unmodifiable(_custody);

  @override
  List<BlockchainAnchor> get allAnchors => List.unmodifiable(_anchors);

  @override
  List<ProcessingEvent> get allProcessing => List.unmodifiable(_processing);

  @override
  List<BatchRelation> get allRelations => List.unmodifiable(_relations);

  @override
  List<PurchaseRequest> get allRequests => List.unmodifiable(_requests);

  @override
  List<QRPassport> get allPassports => List.unmodifiable(_passports);

  @override
  QRPassport? passportForSlug(String slug) => _passports
      .where((passport) => passport.slug == slug)
      .cast<QRPassport?>()
      .firstOrNull;

  @override
  List<HiveAlert> get alerts => List.unmodifiable(_alerts);

  /// All health screening events across hives (used for offline persistence).
  @override
  List<HealthCheckEvent> get healthChecks => List.unmodifiable(_healthChecks);

  /// All verifications across batches (used for offline persistence).
  List<LabVerification> get allVerifications =>
      List.unmodifiable(_verifications);

  @override
  void addHarvest(Harvest harvest) => _harvests.add(harvest);

  @override
  void updateHarvest(Harvest harvest) {
    final index = _harvests.indexWhere((item) => item.id == harvest.id);
    if (index >= 0) _harvests[index] = harvest;
  }

  @override
  void addBatch(Batch batch, List<BatchHarvest> harvestLinks) {
    _batches.add(batch);
    _batchHarvests.addAll(harvestLinks);
  }

  @override
  void updateBatch(Batch batch) {
    final index = _batches.indexWhere((item) => item.id == batch.id);
    if (index >= 0) _batches[index] = batch;
  }

  @override
  void addVerification(LabVerification verification) =>
      _verifications.add(verification);

  @override
  void addAlert(HiveAlert alert) => _alerts.add(alert);

  @override
  void removeAlertsForHive(String hiveId, AlertType type) {
    _alerts.removeWhere((a) => a.hiveId == hiveId && a.type == type);
  }

  @override
  void addHealthCheck(HealthCheckEvent event) => _healthChecks.add(event);

  @override
  List<BeeHealthEvent> get beeHealthEvents =>
      List.unmodifiable(_beeHealthEvents);

  @override
  void addBeeHealthEvent(BeeHealthEvent event) => _beeHealthEvents.add(event);

  @override
  List<TreatmentRecord> get treatments => List.unmodifiable(_treatments);

  @override
  void addTreatment(TreatmentRecord record) => _treatments.add(record);

  @override
  void replaceTreatments(List<TreatmentRecord> records) {
    _treatments
      ..clear()
      ..addAll(records);
  }

  @override
  List<BeeHealthFollowUp> get followUps => List.unmodifiable(_followUps);

  @override
  void addFollowUp(BeeHealthFollowUp followUp) => _followUps.add(followUp);

  @override
  void replaceFollowUps(List<BeeHealthFollowUp> records) {
    _followUps
      ..clear()
      ..addAll(records);
  }

  @override
  void addCustody(CustodyEvent event) => _custody.add(event);

  @override
  void addAnchor(BlockchainAnchor anchor) => _anchors.add(anchor);

  @override
  void addEvent(AuditEvent event) => _events.add(event);

  @override
  void addRelation(BatchRelation relation) => _relations.add(relation);

  @override
  void addListing(MarketplaceListing listing) => _listings.add(listing);

  @override
  void addPurchaseRequest(PurchaseRequest request) => _requests.add(request);

  @override
  void addPassport(QRPassport passport) => _passports.add(passport);

  @override
  List<Harvest> get allHarvests => List.unmodifiable(_harvests);

  @override
  void updateHarvestStatus(Harvest harvest, HarvestStatus status) {
    final index = _harvests.indexWhere((item) => item.id == harvest.id);
    if (index >= 0) _harvests[index] = harvest.copyWith(status: status);
  }

  @override
  List<ProcessingEvent> processingFor(String batchId) =>
      _processing.where((event) => event.batchId == batchId).toList();

  @override
  void addProcessingEvent(ProcessingEvent event) => _processing.add(event);

  @override
  List<ProductBatch> get productBatches => List.unmodifiable(_productBatches);

  @override
  List<ProductBatch> productBatchesFor(String parentBatchId) =>
      _productBatches
          .where((product) => product.parentBatchId == parentBatchId)
          .toList();

  @override
  void addProductBatch(ProductBatch product) => _productBatches.add(product);

  @override
  List<PackagingBatch> get packagingBatches => List.unmodifiable(_packagingBatches);

  @override
  PackagingBatch? packagingBatchById(String id) =>
      _packagingBatches.where((b) => b.packagingBatchId == id).firstOrNull;

  @override
  List<PackagingBatch> packagingBatchesForBatch(String batchId) =>
      _packagingBatches.where((b) => b.sourceBatchId == batchId).toList();

  @override
  void addPackagingBatch(PackagingBatch batch) => _packagingBatches.add(batch);

  @override
  void updatePackagingBatch(PackagingBatch batch) {
    final index = _packagingBatches.indexWhere((b) => b.packagingBatchId == batch.packagingBatchId);
    if (index >= 0) _packagingBatches[index] = batch;
  }

  @override
  List<HoneyJar> get jars => List.unmodifiable(_jars);

  @override
  HoneyJar? jarById(String jarId) =>
      _jars.where((j) => j.jarId == jarId).firstOrNull;

  @override
  List<HoneyJar> jarsForPackagingBatch(String packagingBatchId) =>
      _jars.where((j) => j.packagingBatchId == packagingBatchId).toList();

  @override
  List<HoneyJar> jarsForBatch(String batchId) =>
      _jars.where((j) => j.sourceBatchId == batchId).toList();

  @override
  void addJar(HoneyJar jar) => _jars.add(jar);

  @override
  void addJars(List<HoneyJar> newJars) => _jars.addAll(newJars);

  @override
  void updateJar(HoneyJar jar) {
    final index = _jars.indexWhere((item) => item.jarId == jar.jarId);
    if (index >= 0) _jars[index] = jar;
  }

  @override
  void updateListing(MarketplaceListing listing) {
    final index = _listings.indexWhere((l) => l.id == listing.id);
    if (index >= 0) {
      _listings[index] = listing;
    } else {
      _listings.add(listing);
    }
  }

  @override
  void replaceAll({
    List<Hive>? hives,
    List<Harvest>? harvests,
    List<Batch>? batches,
    List<LabVerification>? verifications,
    List<HiveAlert>? alerts,
    List<HealthCheckEvent>? healthChecks,
    List<BeeHealthEvent>? beeHealthEvents,
    List<TreatmentRecord>? treatments,
    List<BeeHealthFollowUp>? followUps,
    List<CustodyEvent>? custody,
    List<BlockchainAnchor>? anchors,
    List<ProcessingEvent>? processing,
    List<BatchRelation>? relations,
    List<ProductBatch>? productBatches,
    List<PackagingBatch>? packagingBatches,
    List<HoneyJar>? jars,
    List<MarketplaceListing>? listings,
    List<PurchaseRequest>? requests,
    List<QRPassport>? passports,
  }) {
    if (hives != null) {
      _hives
        ..clear()
        ..addAll(hives);
    }
    if (harvests != null) {
      _harvests
        ..clear()
        ..addAll(harvests);
    }
    if (batches != null) {
      _batches
        ..clear()
        ..addAll(batches);
    }
    if (verifications != null) {
      _verifications
        ..clear()
        ..addAll(verifications);
    }
    if (alerts != null) {
      _alerts
        ..clear()
        ..addAll(alerts);
    }
    if (healthChecks != null) {
      _healthChecks
        ..clear()
        ..addAll(healthChecks);
    }
    if (beeHealthEvents != null) {
      _beeHealthEvents
        ..clear()
        ..addAll(beeHealthEvents);
    }
    if (treatments != null) {
      _treatments
        ..clear()
        ..addAll(treatments);
    }
    if (followUps != null) {
      _followUps
        ..clear()
        ..addAll(followUps);
    }
    if (custody != null) {
      _custody
        ..clear()
        ..addAll(custody);
    }
    if (anchors != null) {
      _anchors
        ..clear()
        ..addAll(anchors);
    }
    if (processing != null) {
      _processing
        ..clear()
        ..addAll(processing);
    }
    if (relations != null) {
      _relations
        ..clear()
        ..addAll(relations);
    }
    if (productBatches != null) {
      _productBatches
        ..clear()
        ..addAll(productBatches);
    }
    if (packagingBatches != null) {
      _packagingBatches
        ..clear()
        ..addAll(packagingBatches);
    }
    if (jars != null) {
      _jars
        ..clear()
        ..addAll(jars);
    }
    if (listings != null) {
      _listings
        ..clear()
        ..addAll(listings);
    }
    if (requests != null) {
      _requests
        ..clear()
        ..addAll(requests);
    }
    if (passports != null) {
      _passports
        ..clear()
        ..addAll(passports);
    }
  }

  @override
  void reset() {
    if (seedDemo) {
      _hives
        ..clear()
        ..addAll(DemoSeed.hives);
      _harvests
        ..clear()
        ..addAll(DemoSeed.harvests);
      _batches
        ..clear()
        ..addAll(DemoSeed.batches);
      _batchHarvests
        ..clear()
        ..addAll(DemoSeed.batchLinks);
      _verifications
        ..clear()
        ..addAll(DemoSeed.verifications);
      _alerts
        ..clear()
        ..addAll(DemoSeed.alerts);
    } else {
      _hives.clear();
      _harvests.clear();
      _batches.clear();
      _batchHarvests.clear();
      _verifications.clear();
      _alerts.clear();
    }
    _custody.clear();
    _anchors.clear();
    _events.clear();
    _relations.clear();
    _listings.clear();
    _requests.clear();
    _passports.clear();
    _healthChecks.clear();
    _beeHealthEvents.clear();
    _treatments.clear();
    _followUps.clear();
    _processing.clear();
    _productBatches.clear();
    _packagingBatches.clear();
    _jars.clear();
    if (seedDemo) _seedDemoProductFlow();
  }
}
