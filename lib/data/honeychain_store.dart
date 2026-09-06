import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../l10n/app_strings.dart';
import '../models/disease.dart';
import '../models/honey_batch.dart';
import '../models/domain.dart';
import '../repositories/local_honeychain_repository.dart';
import '../services/connectivity_factory.dart';
import '../services/connectivity_service.dart';
import '../services/disease_detection_service.dart';
import '../services/honeychain_services.dart';
import '../services/image_input_service.dart';
import '../services/local_store.dart';
import '../services/sync_service.dart';
import '../bee_health/models/bee_health_models.dart';
import '../bee_health/services/bee_health_knowledge.dart';
import 'demo_seed.dart';
import 'mock_data.dart';

/// Central application state for the beekeeper-facing HoneyChain app.
///
/// Layering: UI → Store → Repository/Services → Local storage (API later).
/// The store owns offline persistence, pending-sync queue, connectivity
/// status and the selected language.
class HoneyChainStore extends ChangeNotifier {
  HoneyChainStore._() {
    _repository = LocalHoneychainRepository();
    _syncEngine = SyncEngine(MockSyncGateway());
  }

  static final HoneyChainStore instance = HoneyChainStore._();

  /// When true (widget tests), no real network checks are performed.
  static bool testMode = false;

  late LocalHoneychainRepository _repository;
  late final HiveInsightService hiveInsightService = HiveInsightService();
  late final BatchService batchService = BatchService(_repository);
  late final VerificationService verificationService = VerificationService(
    _repository,
    batchService,
  );
  late final CustodyService custodyService = CustodyService(
    _repository,
    batchService,
  );
  late final BlockchainService blockchainService = BlockchainService(
    _repository,
  );
  late final GenealogyService genealogyService = GenealogyService(_repository);
  late final PassportService passportService = PassportService(_repository);
  late final MarketplaceService marketplaceService = MarketplaceService(
    _repository,
    batchService,
  );
  late SyncEngine _syncEngine;

  /// Photo-based hive disease screening. Demo implementation today; can be
  /// swapped for a real on-device model without changing the UI.
  late final DiseaseDetectionService diseaseDetection =
      DemoDiseaseDetectionService();

  /// Injectable camera/gallery image source (demo + widget tests use the
  /// demo implementation so no real hardware is required).
  ImageInputService imageInput = DemoImageInputService();

  /// Demo outcome used by [DemoDiseaseDetectionService] (Profile simulation
  /// panel and widget tests). Defaults to a neutral healthy result.
  DiseaseScreenOutcome demoScreeningOutcome =
      DiseaseScreenOutcome.noObviousSigns;

  bool _started = false;
  bool _online = true;
  bool _loggedIn = false;
  String _language = 'en';
  BeekeeperProfile _profile = DemoSeed.profile;
  ConnectivityService? _connectivity;
  HoneyBatch _batch = MockData.demoBatch();
  Batch? _activeV2Batch;

  // Organization / FPO portal (v2 demo)
  bool _fpoRole = false;
  String _activeFpoOrgId = 'ORG-TN-001';

  // ---------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------

  Future<void> ensureStarted({bool usePersistence = true}) async {
    if (_started) return;
    _started = true;
    await LocalStore.instance.init();

    if (usePersistence) {
      _language = AppLanguages.fromCode(LocalStore.instance.loadLanguage())
          .code;
      _loggedIn = LocalStore.instance.loadLoggedIn();
      final profile = LocalStore.instance.loadProfile();
      if (profile != null) _profile = profile;
      _loadPersisted();
    }

    unawaited(BeeHealthKnowledge.instance.load(_language));

    if (!testMode) {
      _connectivity = createConnectivityService();
      _connectivity!.addListener(_onConnectivityChanged);
      await _connectivity!.refresh();
      _online = _connectivity!.isOnline;
      if (_online) {
        await _syncPendingRecords();
      }
    }
    notifyListeners();
  }

  Future<void> refreshConnectivity() async {
    await _connectivity?.refresh();
  }

  /// Re-evaluates connectivity and immediately drains the pending queue when
  /// the connection is available again.
  Future<void> syncPending() => _syncPendingRecords();

  void _onConnectivityChanged() async {
    _online = _connectivity?.isOnline ?? true;
    notifyListeners();
    if (_online) {
      await _syncPendingRecords();
    }
  }

  /// Forces connectivity state (used by widget tests and demo tooling).
  @visibleForTesting
  void debugSetOnline(bool value) {
    _online = value;
    notifyListeners();
  }

  void _loadPersisted() {
    final hives = LocalStore.instance.loadHives();
    final harvests = LocalStore.instance.loadHarvests();
    final batches = LocalStore.instance.loadBatches();
    final verifications = LocalStore.instance.loadVerifications();
    final alerts = LocalStore.instance.loadAlerts();
    final healthChecks = LocalStore.instance.loadHealthChecks();
    final beeHealthEvents = LocalStore.instance.loadBeeHealthEvents();
    final treatments = LocalStore.instance.loadTreatments();
    final followUps = LocalStore.instance.loadFollowUps();
    final custody = LocalStore.instance.loadCustody();
    final anchors = LocalStore.instance.loadAnchors();
    final processing = LocalStore.instance.loadProcessing();
    final relations = LocalStore.instance.loadRelations();
    final productBatches = LocalStore.instance.loadProductBatches();
    final packagingBatches = LocalStore.instance.loadPackagingBatches();
    final jars = LocalStore.instance.loadJars();
    final listings = LocalStore.instance.loadListings();
    final requests = LocalStore.instance.loadRequests();
    final passports = LocalStore.instance.loadPassports();

    if (hives == null &&
        harvests == null &&
        batches == null &&
        verifications == null &&
        alerts == null &&
        healthChecks == null &&
        beeHealthEvents == null &&
        treatments == null &&
        followUps == null &&
        custody == null &&
        anchors == null &&
        processing == null &&
        relations == null &&
        productBatches == null &&
        packagingBatches == null &&
        jars == null &&
        listings == null &&
        requests == null &&
        passports == null) {
      return;
    }
    _repository.replaceAll(
      hives: hives,
      harvests: harvests,
      batches: batches,
      verifications: verifications,
      alerts: alerts,
      healthChecks: healthChecks,
      beeHealthEvents: beeHealthEvents,
      treatments: treatments,
      followUps: followUps,
      custody: custody,
      anchors: anchors,
      processing: processing,
      relations: relations,
      productBatches: productBatches,
      packagingBatches: packagingBatches,
      jars: jars,
      listings: listings,
      requests: requests,
      passports: passports,
    );
  }

  // ---------------------------------------------------------------------
  // Localization
  // ---------------------------------------------------------------------

  String get language => _language;
  AppLang get currentLang => AppLanguages.fromCode(_language);

  String tr(String key) => AppStrings.of(_language, key);

  void setLanguage(String code) {
    _language = AppLanguages.fromCode(code).code;
    LocalStore.instance.saveLanguage(_language);
    unawaited(BeeHealthKnowledge.instance.load(_language));
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------

  HoneyBatch get batch => _batch;
  BeekeeperProfile get profile => _profile;
  bool get loggedIn => _loggedIn;
  bool get isOnline => _online;
  User get currentBeekeeper => DemoSeed.ravi;
  Batch? get activeV2Batch => _activeV2Batch;

  // ---------------------------------------------------------------------
  // Organization / FPO portal
  // ---------------------------------------------------------------------

  bool get isFpoRole => _fpoRole;

  /// Cooperating organizations for the collect/batch flow.
  List<Organization> get organizations => DemoSeed.organizations;
  String get activeFpoOrgId => _activeFpoOrgId;

  Organization get activeFpoOrg {
    for (final org in DemoSeed.organizations) {
      if (org.id == _activeFpoOrgId) return org;
    }
    return DemoSeed.organizations.first;
  }

  /// All harvests across hives (beekeeper + org viewpoints use the same store).
  List<Harvest> get allHarvests => _repository.allHarvests;

  /// Harvests not yet collected by the organization (incoming).
  List<Harvest> get incomingHarvests =>
      allHarvests.where((h) => !h.collected).toList()
        ..sort((a, b) => b.harvestedAt.compareTo(a.harvestedAt));

  /// Harvests already collected for batch creation.
  List<Harvest> get collectedHarvests =>
      allHarvests.where((h) => h.collected && !_inBatch(h.id)).toList();

  int get incomingCount => incomingHarvests.length;
  int get collectedCount => collectedHarvests.length;

  int get activeBatchesCount =>
      batches.where((b) => b.status != BatchStatus.labFailed).length;

  int get pendingLabCount =>
      batches.where((b) => b.status == BatchStatus.labPending).length;

  /// Product batches created from all consolidated batches.
  List<ProductBatch> get productBatches => List.of(_repository.productBatches)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int get packagedCount => productBatches.length;

  List<ProcessingEvent> processingFor(Batch batch) =>
      _repository.processingFor(batch.id);

  List<ProductBatch> productsFor(Batch batch) =>
      _repository.productBatchesFor(batch.id);

  void setFpoRole(bool value) {
    _fpoRole = value;
    notifyListeners();
  }

  void setActiveFpoOrg(String orgId) {
    _activeFpoOrgId = orgId;
    notifyListeners();
  }

  /// True when a harvest is already linked to a batch (so it is not
  /// offered for collection twice).
  bool _inBatch(String harvestId) =>
      batches.any((b) => _repository.harvestsForBatch(b.id).any(
            (link) => link.harvestId == harvestId,
          ));

  /// Organization marks an incoming harvest as collected.
  void collectHarvest(Harvest harvest) {
    _repository.updateHarvestStatus(harvest, HarvestStatus.collected);
    _persistHarvests();
    notifyListeners();
  }

  /// Consolidates multiple collected harvests into ONE batch (multi-hive).
  /// Returns the created batch.
  Batch createConsolidatedBatch(
    List<Harvest> harvests, {
    String? honeyTypeOverride,
  }) {
    final total = harvests.fold<double>(
      0,
      (sum, h) => sum + h.quantityKg,
    );
    final honeyType =
        honeyTypeOverride ??
        (harvests.isEmpty ? 'Floral Honey' : harvests.first.honeyType);
    final batch = batchService.createBatchDirect(
      organizationId: activeFpoOrg.id,
      origin: profile.location,
      honeyType: honeyType,
      quantityKg: total,
      harvests: harvests,
    );
    final withState = batch.copyWith(
      displayStatus: BatchDisplayStatus.pending,
      syncStatus: isOnline ? SyncStatus.synced : SyncStatus.pending,
    );
    _repository.updateBatch(withState);
    passportService.create(withState);
    _persistBatches();
    notifyListeners();
    return withState;
  }

  /// Organization records a processing step for a batch.
  ProcessingEvent recordProcessing(Batch batch, String unit) {
    final event = ProcessingEvent(
      id: 'proc-${batch.id}-${DateTime.now().microsecondsSinceEpoch}',
      batchId: batch.id,
      unit: unit,
      date: DateTime.now(),
      status: 'COMPLETED',
    );
    _repository.addProcessingEvent(event);
    notifyListeners();
    return event;
  }

  /// Organization creates a packaged product batch from a parent batch.
  /// Generates the consumer QR once the product is created.
  ProductBatch createProductBatch(Batch parent, ProductSize size) {
    final now = DateTime.now();
    final suffix = switch (size) {
      ProductSize.size500ml => 'A',
      ProductSize.size1kg => 'B',
      ProductSize.size100g => 'C',
      ProductSize.size250g => 'D',
    };
    final productCode =
        '${parent.code}-$suffix'; // e.g. HC-TN-00128-A
    final product = ProductBatch(
      id: 'prod-$productCode-${now.microsecondsSinceEpoch}',
      productCode: productCode,
      parentBatchId: parent.id,
      size: size,
      createdAt: now,
    );
    _repository.addProductBatch(product);
    final updated = parent.copyWith(status: BatchStatus.completed);
    _repository.updateBatch(updated);
    _persistBatches();
    notifyListeners();
    return product;
  }

  List<Hive> get hives => _repository.hivesForBeekeeper(currentBeekeeper.id);
  List<Harvest> get harvests =>
      _repository.harvestsForBeekeeper(currentBeekeeper.id);
  List<Batch> get batches => _repository.batches;
  List<HiveAlert> get alerts => _repository.alerts;
  List<HealthCheckEvent> get healthChecks => _repository.healthChecks;
  List<MarketplaceListing> get marketplaceListings => _repository.listings;

  int get needsCareCount =>
      hives.where((h) => insightFor(h).riskLevel != RiskLevel.healthy).length;

  int get harvestCount => harvests.length;

  double get totalHarvestKg => harvests.fold(0, (sum, h) => sum + h.quantityKg);

  double get thisMonthHarvestKg {
    final now = DateTime.now();
    return harvests
        .where(
          (h) =>
              h.harvestedAt.year == now.year &&
              h.harvestedAt.month == now.month,
        )
        .fold(0, (sum, h) => sum + h.quantityKg);
  }

  int get pendingCount {
    final pendingHarvests = harvests
        .where((h) => h.syncStatus == SyncStatus.pending)
        .length;
    final pendingBatches = batches
        .where((b) => b.syncStatus == SyncStatus.pending)
        .length;
    return pendingHarvests + pendingBatches;
  }

  List<Harvest> get pendingHarvests =>
      harvests.where((h) => h.syncStatus == SyncStatus.pending).toList();

  List<Batch> get pendingBatches =>
      batches.where((b) => b.syncStatus == SyncStatus.pending).toList();

  List<HiveReading> readingsForHive(String hiveId) =>
      _repository.readingsForHive(hiveId);

  HiveInsight insightFor(Hive hive) {
    final base = hiveInsightService.createInsight(
      hive,
      readingsForHive(hive.id),
    );
    if (!hasHiveConditionAlert(hive.id)) return base;
    return base.copyWith(
      riskLevel: RiskLevel.highRisk,
      riskExplanation:
          'Possible disease signs detected in ${hive.name}. '
          'Photo screening recommended.',
      inspectionRecommendation:
          'Please inspect the hive and run a photo screening.',
    );
  }

  /// Demo/simulated acoustic activity level derived from the hive's latest
  /// reading. Labeled as simulation — no real audio hardware is claimed.
  /// Returns (label, level 0..2). The caller maps the level to a color.
  (String, int) acousticFor(Hive hive) {
    final readings = readingsForHive(hive.id);
    final latest = readings.isNotEmpty ? readings.last : null;
    final temp = latest?.temperatureC ?? 34;
    // Deterministic demo heuristic (temperature + id hash) producing a
    // stable buzz level. Purely illustrative, not sensor-backed.
    var seed = 0;
    for (final c in hive.id.runes) {
      seed = (seed + c) % 97;
    }
    final level = ((seed + (temp - 30).round()) % 3).abs();
    return switch (level) {
      0 => ('Healthy buzzing', level),
      1 => ('Active colony', level),
      _ => ('Elevated activity (simulated)', level),
    };
  }

  /// True when the hive currently has a disease or abnormal-condition alert
  /// (flagged for inspection). Never claims an IoT reading is a disease.
  bool hasHiveConditionAlert(String hiveId) {
    for (final alert in alerts) {
      if (alert.hiveId != hiveId) continue;
      if (alert.type == AlertType.disease || alert.type == AlertType.iot) {
        return true;
      }
    }
    return false;
  }

  Hive? hiveById(String id) {
    for (final hive in hives) {
      if (hive.id == id) return hive;
    }
    return null;
  }

  Batch? batchById(String id) {
    for (final batch in batches) {
      if (batch.id == id) return batch;
    }
    return null;
  }

  ProductBatch? productByCode(String code) {
    for (final product in productBatches) {
      if (product.productCode == code) return product;
    }
    return null;
  }

  /// The fully-traceable seeded demo batch (HC-TN-00128) that the org flow
  /// also produces, so beekeeper -> FPO -> batch -> QR -> consumer all point
  /// at the SAME batch. Falls back to the newest batch if the seed is absent.
  Batch? seededDemoBatch() {
    for (final batch in batches) {
      if (batch.id == 'batch-demo-128') return batch;
    }
    return batches.isNotEmpty ? batches.first : null;
  }

  String hiveName(String id) => hiveById(id)?.name ?? id;

  /// Label of the hive a batch was made from (e.g. "Hive #2").
  String batchSourceHive(Batch batch) {
    final links = _repository.harvestsForBatch(batch.id);
    if (links.isEmpty) return '—';
    for (final h in harvests) {
      if (h.id == links.first.harvestId) return hiveName(h.hiveId);
    }
    return '—';
  }

  /// Hive names from which a batch's consolidated harvests came (genealogy).
  List<String> sourceHivesForBatch(Batch batch) {
    final links = _repository.harvestsForBatch(batch.id);
    final names = <String>[];
    final seen = <String>{};
    for (final link in links) {
      for (final h in harvests) {
        if (h.id != link.harvestId) continue;
        final n = hiveName(h.hiveId);
        if (seen.add(n)) names.add(n);
        break;
      }
    }
    return names;
  }

  /// Harvest records linked to a consolidated batch (genealogy).
  List<Harvest> harvestsForBatch(Batch batch) {
    final links = _repository.harvestsForBatch(batch.id);
    final out = <Harvest>[];
    for (final link in links) {
      for (final h in harvests) {
        if (h.id == link.harvestId) {
          out.add(h);
          break;
        }
      }
    }
    return out;
  }

  Batch? batchByCode(String code) {
    for (final batch in batches) {
      if (batch.code == code) return batch;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------

  void completeLogin({String? phone, String? name}) {
    if (phone != null || name != null) {
      _profile = _profile.copyWith(phone: phone, name: name ?? _profile.name);
      LocalStore.instance.saveProfile(_profile);
    }
    _loggedIn = true;
    LocalStore.instance.saveLoggedIn(true);
    notifyListeners();
  }

  void logout() {
    _loggedIn = false;
    LocalStore.instance.saveLoggedIn(false);
    notifyListeners();
  }

  void updateProfile({String? name, String? location}) {
    _profile = _profile.copyWith(name: name, location: location);
    LocalStore.instance.saveProfile(_profile);
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Beekeeper actions
  // ---------------------------------------------------------------------

  /// Records a harvest. Stored locally first; queued for background sync
  /// whenever the phone is offline (never silently lost).
  ///
  /// [floralSource] optionally overrides the flower/nectar source; when null or
  /// empty the hive's own honey type is used.
  Harvest recordHarvest({
    required Hive hive,
    required double quantityKg,
    DateTime? date,
    String? floralSource,
  }) {
    final harvestedAt = date ?? DateTime.now();
    final nowMicro = DateTime.now().microsecondsSinceEpoch;
    final source = floralSource?.trim();
    final cleanSource =
        (source != null && source.isNotEmpty) ? source : 'Not specified';
    final harvest = Harvest(
      id: 'harvest-$nowMicro',
      hiveId: hive.id,
      beekeeperId: currentBeekeeper.id,
      harvestedAt: harvestedAt,
      honeyType: cleanSource,
      quantityKg: quantityKg,
      syncStatus: isOnline ? SyncStatus.synced : SyncStatus.pending,
      status: HarvestStatus.collected,
    );
    _repository.addHarvest(harvest);

    // Section 4: Create/associate batch using existing BatchService.
    // FPO must automatically see the SAME beekeeper, beekeeperId, hiveId, harvestId, batchId, harvestDate, quantity, floral source.
    final batch = batchService.createBatchDirect(
      organizationId: hive.organizationId.isNotEmpty
          ? hive.organizationId
          : 'ORG-TN-001',
      origin:
          hive.location.isNotEmpty ? hive.location : 'Nilgiris, Tamil Nadu',
      honeyType: cleanSource,
      quantityKg: quantityKg,
      createdAt: harvestedAt,
      harvests: [harvest],
    );
    _activeV2Batch = batch;

    _persistHarvests();
    _persistBatches();
    if (_online) {
      _syncPendingRecords();
    }
    notifyListeners();
    return harvest;
  }

  // ---------------------------------------------------------------------
  // Bee health (offline-first, decision-tree screening)
  // ---------------------------------------------------------------------

  List<BeeHealthEvent> get beeHealthEvents => _repository.beeHealthEvents;

  List<BeeHealthEvent> beeHealthEventsFor(String hiveId) {
    final events = beeHealthEvents.where((e) => e.hiveId == hiveId).toList()
      ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
    return events;
  }

  List<TreatmentRecord> get treatments => _repository.treatments;

  List<TreatmentRecord> treatmentsFor(String hiveId) {
    return treatments.where((t) => t.hiveId == hiveId).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  }

  List<BeeHealthFollowUp> get followUps => _repository.followUps;

  List<BeeHealthFollowUp> followUpsFor(String hiveId) {
    return followUps.where((f) => f.hiveId == hiveId).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  void recordBeeHealth({
    required String hiveId,
    required String conditionId,
    required Map<String, int> answers,
    required int questionsAsked,
  }) {
    final event = BeeHealthEvent(
      id: 'bh-${DateTime.now().microsecondsSinceEpoch}',
      hiveId: hiveId,
      conditionId: conditionId,
      answers: answers,
      questionsAsked: questionsAsked,
      checkedAt: DateTime.now(),
    );
    _repository.addBeeHealthEvent(event);
    _persistBeeHealth();
    notifyListeners();
  }

  void addTreatment({required String hiveId, required String treatment}) {
    final record = TreatmentRecord(
      id: 'tr-${DateTime.now().microsecondsSinceEpoch}',
      hiveId: hiveId,
      eventId: '',
      treatment: treatment,
      startedAt: DateTime.now(),
      status: TreatmentStatus.active,
    );
    _repository.addTreatment(record);
    _persistTreatments();
    notifyListeners();
  }

  void completeTreatment(String treatmentId) {
    final list = treatments.map((t) {
      if (t.id == treatmentId) {
        return t.copyWith(status: TreatmentStatus.completed);
      }
      return t;
    }).toList();
    _repository.replaceTreatments(list);
    _persistTreatments();
    notifyListeners();
  }

  void completeFollowUp(String followUpId) {
    final list = followUps.map((f) {
      if (f.id == followUpId) {
        return f.copyWith(status: FollowUpStatus.done, doneAt: DateTime.now());
      }
      return f;
    }).toList();
    _repository.replaceFollowUps(list);
    _persistFollowUps();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Disease screening (AI-assisted, offline-first)
  // ---------------------------------------------------------------------

  /// Health screening events for a hive, newest first.
  List<HealthCheckEvent> healthChecksFor(String hiveId) {
    final events = healthChecks.where((e) => e.hiveId == hiveId).toList()
      ..sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
    return events;
  }

  /// Demo outcome for the offline screening service (Profile panel + tests).
  void setDemoScreeningOutcome(DiseaseScreenOutcome outcome) {
    demoScreeningOutcome = outcome;
    notifyListeners();
  }

  /// Stores a completed screening locally and keeps the hive's condition
  /// alerts consistent with the qualitative result.
  void recordScreening(Hive hive, DiseaseScreeningResult result) {
    final event = HealthCheckEvent(
      id: 'health-${DateTime.now().microsecondsSinceEpoch}',
      hiveId: hive.id,
      checkedAt: DateTime.now(),
      outcome: result.outcome,
      conditionId: result.condition?.id,
    );
    _repository.addHealthCheck(event);
    _persistHealthChecks();

    switch (result.outcome) {
      case DiseaseScreenOutcome.possibleDisease:
        _addDiseaseAlertIfMissing(hive.id, hive.name);
      case DiseaseScreenOutcome.noObviousSigns:
        _repository.removeAlertsForHive(hive.id, AlertType.disease);
        _persistAlerts();
      case DiseaseScreenOutcome.unableToAssess:
        break;
    }
    notifyListeners();
  }

  void _addDiseaseAlertIfMissing(String hiveId, String hiveName) {
    for (final alert in alerts) {
      if (alert.hiveId == hiveId && alert.type == AlertType.disease) return;
    }
    _repository.addAlert(
      HiveAlert(
        id: 'alert-disease-${DateTime.now().microsecondsSinceEpoch}',
        type: AlertType.disease,
        severity: AlertSeverity.urgent,
        hiveId: hiveId,
        createdAt: DateTime.now(),
      ),
    );
    _persistAlerts();
  }

  // ---------------------------------------------------------------------
  // Demo simulation (prototype only; same flow as future real screening)
  // ---------------------------------------------------------------------

  /// Clears Hive #4's simulated condition alerts and resets the demo outcome
  /// to a healthy screening result.
  void demoSimulateHealthy() {
    _repository.removeAlertsForHive('hive-004', AlertType.disease);
    _repository.removeAlertsForHive('hive-004', AlertType.iot);
    _persistAlerts();
    demoScreeningOutcome = DiseaseScreenOutcome.noObviousSigns;
    notifyListeners();
  }

  /// Simulates an abnormal IoT sensor event on Hive #4 (temperature HIGH,
  /// bee activity LOW). Flags the hive for inspection WITHOUT claiming a
  /// specific disease.
  void demoSimulateIoTAbnormal() {
    _repository.addAlert(
      HiveAlert(
        id: 'alert-iot-${DateTime.now().microsecondsSinceEpoch}',
        type: AlertType.iot,
        severity: AlertSeverity.care,
        hiveId: 'hive-004',
        createdAt: DateTime.now(),
      ),
    );
    _persistAlerts();
    notifyListeners();
  }

  /// Simulates a possible-disease screening on Hive #4: the hive is flagged,
  /// a disease alert appears, and the next screening returns the
  /// possible-disease state.
  void demoSimulatePossibleDisease() {
    _addDiseaseAlertIfMissing('hive-004', 'Hive #4');
    demoScreeningOutcome = DiseaseScreenOutcome.possibleDisease;
    notifyListeners();
  }

  /// Sets the demo screening outcome to "unable to assess" (no hive flag).
  void demoSimulateUnableToAssess() {
    demoScreeningOutcome = DiseaseScreenOutcome.unableToAssess;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Batch lifecycle (legacy role screens)
  // ---------------------------------------------------------------------

  Batch createBatchFromHarvests(List<Harvest> selectedHarvests) {
    _activeV2Batch = batchService.createBatch(
      harvests: selectedHarvests,
      organizationId: DemoSeed.fpo.id,
      origin: DemoSeed.profile.location,
    );
    final withState = _activeV2Batch!.copyWith(
      displayStatus: BatchDisplayStatus.pending,
      syncStatus: isOnline ? SyncStatus.synced : SyncStatus.pending,
    );
    _repository.updateBatch(withState);
    _activeV2Batch = withState;
    passportService.create(_activeV2Batch!);
    _persistBatches();
    notifyListeners();
    return _activeV2Batch!;
  }

  Batch createBatchDirect({
    required String honeyType,
    required String origin,
    required double quantityKg,
    List<Harvest> harvests = const [],
  }) {
    _activeV2Batch = batchService.createBatchDirect(
      organizationId: DemoSeed.fpo.id,
      origin: origin,
      honeyType: honeyType,
      quantityKg: quantityKg,
      harvests: harvests,
    );
    final withState = _activeV2Batch!.copyWith(
      displayStatus: BatchDisplayStatus.pending,
      syncStatus: isOnline ? SyncStatus.synced : SyncStatus.pending,
    );
    _repository.updateBatch(withState);
    _activeV2Batch = withState;
    passportService.create(_activeV2Batch!);
    _persistBatches();
    notifyListeners();
    return _activeV2Batch!;
  }

  CustodyEvent acceptV2Custody(Batch batch) {
    final event = custodyService.accept(batch);
    _activeV2Batch = batches.firstWhere(
      (item) => item.id == batch.id,
      orElse: () => batch,
    );
    _persistBatches();
    _persistCustody();
    notifyListeners();
    return event;
  }

  LabVerification verifyV2Batch(Batch batch, VerificationStatus status) {
    final result = verificationService.verify(batch, status);
    _activeV2Batch = batches.firstWhere(
      (item) => item.id == batch.id,
      orElse: () => batch,
    );
    if (status == VerificationStatus.pass) {
      _activeV2Batch = _activeV2Batch!.copyWith(
        displayStatus: BatchDisplayStatus.verified,
      );
      _repository.updateBatch(_activeV2Batch!);
      // NOTE: Section 11 & 13: Lab verification MUST NOT automatically anchor blockchain!
    } else if (status == VerificationStatus.fail) {
      _activeV2Batch = _activeV2Batch!.copyWith(
        displayStatus: BatchDisplayStatus.failed,
      );
      _repository.updateBatch(_activeV2Batch!);
    }
    _persistBatches();
    _persistVerifications();
    notifyListeners();
    return result;
  }

  ProcessingEvent completeProcessing(Batch batch, [String? unit]) {
    final u = unit ?? activeFpoOrg.name;
    final event = recordProcessing(batch, u);
    final updated = batch.copyWith(status: BatchStatus.processing);
    _repository.updateBatch(updated);
    _activeV2Batch = updated;
    _persistBatches();
    _persistProcessing();
    notifyListeners();
    return event;
  }

  BlockchainAnchor anchorV2Batch(Batch batch, String eventType) {
    final harvests = harvestsForBatch(batch);
    final cust = custodyFor(batch);
    final verifs = verificationsFor(batch);
    final procs = processingFor(batch);

    final details = <String, dynamic>{
      'batchId': batch.id,
      'batchCode': batch.code,
      'honeyType': batch.honeyType,
      'quantityKg': batch.quantityKg,
      'organizationId': batch.organizationId,
      'origin': batch.origin,
      'harvestIds': harvests.map((h) => h.id).toList(),
      'hiveIds': harvests.map((h) => h.hiveId).toSet().toList(),
      'beekeeperId': currentBeekeeper.id,
      'beekeeperName': currentBeekeeper.name,
      'custodyAccepted': cust.isNotEmpty,
      'labStatus': verifs.isNotEmpty ? verifs.first.status.name : 'none',
      'processingStatus': procs.isNotEmpty ? procs.first.status : 'none',
      'createdAt': batch.createdAt.toIso8601String(),
    };

    final anchor = blockchainService.anchor(batch, eventType, details: details);
    final updated = batch.copyWith(displayStatus: BatchDisplayStatus.verified);
    _repository.updateBatch(updated);
    _activeV2Batch = updated;
    _persistBatches();
    _persistAnchors();
    notifyListeners();
    return anchor;
  }

  MarketplaceListing releaseV2BatchToMarket(Batch batch) {
    final updated = batch.copyWith(status: BatchStatus.listed);
    _repository.updateBatch(updated);
    _activeV2Batch = updated;

    final existingListing = _repository.listings
        .where((l) => l.batchId == batch.id)
        .firstOrNull;
    late final MarketplaceListing listing;
    if (existingListing != null) {
      listing = existingListing.copyWith(
        isActive: true,
        quantityKg: batch.quantityKg,
        remainingQuantityKg:
            existingListing.remainingQuantityKg ?? batch.quantityKg,
      );
      _repository.updateListing(listing);
    } else {
      listing = MarketplaceListing(
        id: '${batch.id}-listing',
        batchId: batch.id,
        quantityKg: batch.quantityKg,
        pricePerKg: 650,
        isActive: true,
        remainingQuantityKg: batch.quantityKg,
      );
      _repository.addListing(listing);
    }

    _persistBatches();
    _persistListings();
    notifyListeners();
    return listing;
  }

  List<HoneyJar> allocateAndCreateJars({
    required Batch batch,
    required double allocatedKg,
    required int jarSizeGrams,
    required String buyerId,
  }) {
    final allocatedGrams = (allocatedKg * 1000).round();
    if (allocatedGrams <= 0 || jarSizeGrams <= 0) return [];
    final jarCount = allocatedGrams ~/ jarSizeGrams;
    if (jarCount <= 0) return [];

    // Only whole jars are packed; the split remainder (allocatedGrams % jarSize)
    // stays available on the marketplace instead of being silently consumed.
    final packedGrams = jarCount * jarSizeGrams;
    final packedKg = packedGrams / 1000.0;

    final listing = _repository.listings
        .where((l) => l.batchId == batch.id)
        .firstOrNull;
    if (listing != null) {
      final currentRemaining = listing.effectiveRemainingKg;
      final newRemaining =
          (currentRemaining - packedKg).clamp(0.0, double.infinity);
      _repository.updateListing(
        listing.copyWith(remainingQuantityKg: newRemaining),
      );
    }

    final packIndex = _repository.packagingBatches.length + 1;
    final packId = 'PACK-HC-${packIndex.toString().padLeft(4, '0')}';
    final now = DateTime.now();

    final packagingBatch = PackagingBatch(
      packagingBatchId: packId,
      sourceBatchId: batch.id,
      buyerId: buyerId,
      quantityUsedGrams: packedGrams,
      jarSizeGrams: jarSizeGrams,
      jarCount: jarCount,
      packagingDate: now,
      status: 'CREATED',
    );
    _repository.addPackagingBatch(packagingBatch);

    final harvests = harvestsForBatch(batch);
    final hIds = harvests.map((h) => h.id).toList();
    final hvIds = harvests.map((h) => h.hiveId).toSet().toList();

    final createdJars = <HoneyJar>[];
    final startIndex = _repository.jars.length + 1;
    for (var i = 0; i < jarCount; i++) {
      final jarSeq = (startIndex + i).toString().padLeft(6, '0');
      final jarId = 'JAR-HC-$jarSeq';
      createdJars.add(HoneyJar(
        jarId: jarId,
        packagingBatchId: packId,
        sourceBatchId: batch.id,
        harvestIds: hIds,
        hiveIds: hvIds,
        beekeeperId: currentBeekeeper.id,
        beekeeperName: currentBeekeeper.name,
        organizationId: batch.organizationId,
        buyerId: buyerId,
        quantityGrams: jarSizeGrams,
        packageSize: '${jarSizeGrams}g',
        createdAt: now,
        qrPayload: 'honeychain://jar/$jarId',
      ));
    }
    _repository.addJars(createdJars);

    _repository.addRelation(BatchRelation(
      id: 'rel-$packId',
      parentBatchId: batch.id,
      childBatchId: packId,
      type: RelationType.split,
      createdAt: now,
    ));

    final legacySize = ProductSizeX.fromGrams(jarSizeGrams);
    _repository.addProductBatch(ProductBatch(
      id: 'prod-$packId',
      productCode: batch.code,
      parentBatchId: batch.id,
      size: legacySize,
      createdAt: now,
      packagingStatus: PackagingStatus.packaged,
    ));

    _persistPackagingBatches();
    _persistJars();
    _persistRelations();
    _persistListings();
    _persistProductBatches();
    notifyListeners();
    return createdJars;
  }

  BlockchainAnchor anchorPackagingBatch(PackagingBatch packagingBatch) {
    final anchor = blockchainService.anchorPackaging(
      packagingBatch,
      'PACKAGING_PROVENANCE',
    );
    final updated = packagingBatch.copyWith(
      status: 'ANCHORED',
      blockchainAnchorId: anchor.anchorId,
    );
    _repository.updatePackagingBatch(updated);

    final batchJars =
        _repository.jarsForPackagingBatch(packagingBatch.packagingBatchId);
    for (final j in batchJars) {
      _repository.updateJar(j.copyWith(blockchainAnchorId: anchor.anchorId));
    }

    _persistAnchors();
    _persistPackagingBatches();
    _persistJars();
    notifyListeners();
    return anchor;
  }

  List<PackagingBatch> get packagingBatches => _repository.packagingBatches;
  List<HoneyJar> get jars => _repository.jars;
  HoneyJar? jarById(String id) => _repository.jarById(id);
  PackagingBatch? packagingBatchById(String id) =>
      _repository.packagingBatchById(id);
  List<PackagingBatch> packagingBatchesFor(Batch batch) =>
      _repository.packagingBatchesForBatch(batch.id);
  List<HoneyJar> jarsForPackagingBatch(String id) =>
      _repository.jarsForPackagingBatch(id);
  List<HoneyJar> jarsFor(Batch batch) =>
      _repository.jarsForBatch(batch.id);

  HoneyJar? resolveJar(String query) {
    var clean = query.trim();
    if (clean.toLowerCase().startsWith('honeychain://jar/')) {
      clean = clean.substring('honeychain://jar/'.length);
    }
    clean = clean.toUpperCase();
    return _repository.jarById(clean);
  }

  MarketplaceListing listV2Batch(Batch batch) {
    final listing = marketplaceService.list(batch);
    _activeV2Batch = batches.firstWhere((item) => item.id == batch.id);
    notifyListeners();
    return listing;
  }

  PurchaseRequest requestPurchase(
    MarketplaceListing listing,
    String buyerName,
    double quantityKg,
    String message,
  ) {
    final request = marketplaceService.request(
      listing,
      buyerName,
      quantityKg,
      message,
    );
    notifyListeners();
    return request;
  }

  List<LabVerification> verificationsFor(Batch batch) =>
      _repository.verificationsForBatch(batch.id);
  List<CustodyEvent> custodyFor(Batch batch) =>
      _repository.custodyForBatch(batch.id);
  List<BlockchainAnchor> anchorsFor(Batch batch) =>
      _repository.anchorsForBatch(batch.id);
  List<AuditEvent> eventsFor(Batch batch) =>
      _repository.eventsForBatch(batch.id);
  QRPassport? passportForSlug(String slug) => passportService.find(slug);

  Batch? batchForPassport(String slug) {
    final passport = passportForSlug(slug);
    if (passport == null) return null;
    for (final batch in batches) {
      if (batch.id == passport.batchId) return batch;
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------

  Future<bool> _syncPendingRecords() async {
    final queueHarvests = harvests
        .where((h) => h.syncStatus == SyncStatus.pending)
        .toList();
    final queueBatches = batches
        .where((b) => b.syncStatus == SyncStatus.pending)
        .toList();
    if (queueHarvests.isEmpty && queueBatches.isEmpty) return false;

    await _syncEngine.process(
      pendingHarvests: queueHarvests,
      pendingBatches: queueBatches,
      onHarvestSynced: (h) =>
          _repository.updateHarvest(h.copyWith(syncStatus: SyncStatus.synced)),
      onBatchSynced: (b) =>
          _repository.updateBatch(b.copyWith(syncStatus: SyncStatus.synced)),
    );
    _persistHarvests();
    _persistBatches();
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------

  void _persistHives() async {
    await LocalStore.instance.saveHives(hives);
  }

  void _persistHarvests() async {
    await LocalStore.instance.saveHarvests(harvests);
  }

  void _persistBatches() async {
    await LocalStore.instance.saveBatches(batches);
  }

  void _persistVerifications() async {
    await LocalStore.instance.saveVerifications(_repository.allVerifications);
  }

  void _persistAlerts() async {
    await LocalStore.instance.saveAlerts(alerts);
  }

  void _persistHealthChecks() async {
    await LocalStore.instance.saveHealthChecks(healthChecks);
  }

  void _persistBeeHealth() async {
    await LocalStore.instance.saveBeeHealthEvents(beeHealthEvents);
  }

  void _persistTreatments() async {
    await LocalStore.instance.saveTreatments(treatments);
  }

  void _persistFollowUps() async {
    await LocalStore.instance.saveFollowUps(followUps);
  }

  void _persistCustody() async {
    await LocalStore.instance.saveCustody(_repository.allCustody);
  }

  void _persistAnchors() async {
    await LocalStore.instance.saveAnchors(_repository.allAnchors);
  }

  void _persistProcessing() async {
    await LocalStore.instance.saveProcessing(_repository.allProcessing);
  }

  void _persistRelations() async {
    await LocalStore.instance.saveRelations(_repository.allRelations);
  }

  void _persistProductBatches() async {
    await LocalStore.instance.saveProductBatches(_repository.productBatches);
  }

  void _persistPackagingBatches() async {
    await LocalStore.instance.savePackagingBatches(_repository.packagingBatches);
  }

  void _persistJars() async {
    await LocalStore.instance.saveJars(_repository.jars);
  }

  void _persistListings() async {
    await LocalStore.instance.saveListings(_repository.listings);
  }

  void _persistRequests() async {
    await LocalStore.instance.saveRequests(_repository.allRequests);
  }

  void _persistPassports() async {
    await LocalStore.instance.savePassports(_repository.allPassports);
  }

  /// Pushes persisted state back to seed values (used by the demo reset).
  void resetToDemo() {
    _batch = MockData.demoBatch();
    _activeV2Batch = null;
    _fpoRole = false;
    _activeFpoOrgId = 'ORG-TN-001';
    demoScreeningOutcome = DiseaseScreenOutcome.noObviousSigns;
    _repository.reset();
    _persistHives();
    _persistHarvests();
    _persistBatches();
    _persistVerifications();
    _persistAlerts();
    _persistHealthChecks();
    _persistBeeHealth();
    _persistTreatments();
    _persistFollowUps();
    _persistCustody();
    _persistAnchors();
    _persistProcessing();
    _persistRelations();
    _persistProductBatches();
    _persistPackagingBatches();
    _persistJars();
    _persistListings();
    _persistRequests();
    _persistPassports();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Legacy single-batch demo helpers (paths preserved for role screens)
  // ---------------------------------------------------------------------

  HoneyBatch registerBatch({
    required String beekeeper,
    required String origin,
    required String honeyType,
    required String harvestDate,
    required double quantity,
  }) {
    final id = _nextId();
    _batch = HoneyBatch(
      id: id,
      beekeeper: beekeeper,
      origin: origin,
      honeyType: honeyType,
      harvestDate: harvestDate,
      quantity: quantity,
      events: [
        HoneyEvent(
          type: 'REGISTER',
          actor: 'Beekeeper',
          timestamp: _now(),
          status: 'Completed',
          description: 'Batch registered with HoneyChain.',
        ),
      ],
    );
    notifyListeners();
    return _batch;
  }

  void acceptCustody() {
    if (_batch.custodyAccepted) return;
    _addEvent(
      HoneyEvent(
        type: 'CUSTODY',
        actor: 'Collection / Processor',
        timestamp: _now(),
        status: 'Completed',
        description: 'Custody accepted from beekeeper.',
      ),
    );
    _batch = _batch.copyWith(custodyStatus: 'accepted');
    notifyListeners();
  }

  void submitVerification() {
    if (_batch.labVerified) return;
    _addEvent(
      HoneyEvent(
        type: 'LAB_VERIFY',
        actor: 'Regional Laboratory',
        timestamp: _now(),
        status: 'Verified',
        description: 'Laboratory verification completed — authenticity PASS.',
      ),
    );
    _batch = _batch.copyWith(
      labStatus: 'verified',
      authenticityStatus: 'verified',
      labResults: const {
        'moisture': '17.2% — within expected range',
        'sugarProfile': 'Consistent with natural honey',
        'authenticity': 'No indicators of adulteration',
      },
    );
    notifyListeners();
  }

  void anchorBlockchain() {
    if (_batch.integrityAnchored) return;
    _addEvent(
      HoneyEvent(
        type: 'ANCHOR',
        actor: 'HoneyChain Integrity Layer',
        timestamp: _now(),
        status: 'Anchored',
        description: 'Verification evidence anchored to mock blockchain.',
      ),
    );
    _batch = _batch.copyWith(
      blockchainStatus: 'anchored',
      blockchainHash: _mockHash(),
    );
    notifyListeners();
  }

  void _addEvent(HoneyEvent event) {
    _batch = _batch.copyWith(events: [..._batch.events, event]);
  }

  String _nextId() {
    final random = Random();
    final number = 10000 + random.nextInt(90000);
    return 'HC-${DateTime.now().year}-$number';
  }

  String _mockHash() {
    const chars = '0123456789abcdef';
    final random = Random();
    final full = List.generate(
      64,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    return '0x${full.substring(0, 4)}...${full.substring(60)}';
  }

  String _now() {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)} ${months[t.month - 1]} ${t.year}, '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  void dispose() {
    _connectivity?.removeListener(_onConnectivityChanged);
    _connectivity?.dispose();
    super.dispose();
  }
}
