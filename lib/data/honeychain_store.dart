import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/api/api_exception.dart';
import '../l10n/app_strings.dart';
import '../models/disease.dart';
import '../models/honey_batch.dart';
import '../models/domain.dart';
import '../models/iot.dart';
import '../repositories/local_honeychain_repository.dart';
import '../services/api_token_store.dart';
import '../services/backend_iot_service.dart';
import '../services/connectivity_factory.dart';
import '../services/connectivity_service.dart';
import '../services/disease_detection_service.dart';
import '../services/fastapi_auth_repository.dart';
import '../services/honey_api_service.dart';
import '../services/platform_api_service.dart';
import '../services/honeychain_services.dart';
import '../services/image_input_service.dart';
import '../services/local_store.dart';
import '../services/passport_verification_service.dart';
import '../services/sync_gateway_factory.dart';
import '../services/sync_service.dart';
import '../services/trace_qr_service.dart';
import '../services/trust_service.dart';
import '../bee_health/models/bee_health_models.dart';
import '../bee_health/services/bee_health_knowledge.dart';
import 'demo_seed.dart';
import 'mock_data.dart';
import 'auth.dart';

/// Central application state for the beekeeper-facing HoneyChain app.
///
/// Layering: UI → Store → Repository/Services → Local storage (API later).
/// The store owns offline persistence, pending-sync queue, connectivity
/// status and the selected language.
class HoneyChainStore extends ChangeNotifier {
  HoneyChainStore._() {
    // Demo genealogy is only seeded when tests / developer mode request it;
    // production builds start blank and fill via offline-first sync pull.
    _repository = LocalHoneychainRepository(seedDemo: HoneyChainStore.testMode);
    _syncEngine = SyncEngine(createSyncGateway());
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
  late final TrustService trustService = TrustService(_repository);
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
  String _buyerId = 'BUYER';
  ConnectivityService? _connectivity;
  ConnectivityStatus? _forcedStatus;
  HoneyBatch _batch = MockData.demoBatch();
  Batch? _activeV2Batch;

  /// True while a sync pass is in flight (drives the "Syncing…" badge).
  bool _syncing = false;

  /// Set when the last sync pass left at least one item failed.
  String? _syncError;
  Map<String, int> _syncAttempts = {};
  Map<String, String> _syncErrors = {};

  // Organization / FPO portal (v2 demo)
  bool _fpoRole = false;
  String _activeFpoOrgId = 'ORG-TN-001';

  /// Workspace of the current user session (persisted, see [Workspace]).
  Workspace _activeWorkspace = Workspace.beekeeper;

  // ---------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------

  Future<void> ensureStarted({bool usePersistence = true}) async {
    if (_started) return;
    _started = true;
    await LocalStore.instance.init();
    await ApiTokenStore.instance.init();

    if (usePersistence) {
      _language = AppLanguages.fromCode(LocalStore.instance.loadLanguage())
          .code;
      _loggedIn = LocalStore.instance.loadLoggedIn();
      final profile = LocalStore.instance.loadProfile();
      if (profile != null) _profile = profile;
      final buyerId = LocalStore.instance.loadBuyerId();
      if (buyerId != null && buyerId.trim().isNotEmpty) _buyerId = buyerId;
      _restoreBackendSession();
      _activeWorkspace = Workspace.fromCode(
        LocalStore.instance.loadActiveWorkspace(),
      );
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
    _forcedStatus = value
        ? ConnectivityStatus.online
        : ConnectivityStatus.offline;
    notifyListeners();
  }

  /// Test-only: drops the singleton's startup latch and backend-session flags
  /// so a test can re-run [ensureStarted] against freshly seeded persistence
  /// (simulating an app restart). Local domain data is left intact.
  @visibleForTesting
  void debugResetForTest() {
    _started = false;
    _backendSignedIn = false;
    _backendRole = null;
    _backendChecked = false;
    _backendOnline = false;
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

    _syncAttempts = LocalStore.instance.loadSyncAttempts();
    _syncErrors = LocalStore.instance.loadSyncErrors();

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

  /// Raw connectivity state reported by the reachability service. Defaults to
  /// [ConnectivityStatus.checking] before the first probe completes.
  ConnectivityStatus get connectivityStatus {
    if (_forcedStatus != null) return _forcedStatus!;
    final status = _connectivity?.status;
    if (status != null) return status;
    return testMode ? ConnectivityStatus.online : ConnectivityStatus.checking;
  }

  /// True while a sync pass is being processed.
  bool get isSyncing => _syncing;

  /// Whether the last sync pass left items unsynced (shown as "sync error").
  bool get hasSyncError => _syncError != null;

  String? get syncError => _syncError;

  /// Best-effort attempt count for a pending/failed record id.
  int syncAttemptsOf(String id) => _syncAttempts[id] ?? 0;

  /// Total retries recorded across all currently unsynced records.
  int get syncFailureCount =>
      _syncAttempts.values.fold(0, (sum, attempts) => sum + attempts);
  User get currentBeekeeper => DemoSeed.ravi;
  Batch? get activeV2Batch => _activeV2Batch;

  /// Current buyer identity used for jar allocations. When set by the buyer
  /// (organization / member name) it is persisted locally; a neutral default
  /// is used instead of a hardcoded demo id.
  String get buyerId => _buyerId;

  void setBuyerId(String value) {
    final clean = value.trim();
    _buyerId = clean.isEmpty ? 'BUYER' : clean.toUpperCase();
    LocalStore.instance.saveBuyerId(_buyerId);
    notifyListeners();
  }

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

  // ---------------------------------------------------------------------
  // Session state + workspaces
  // ---------------------------------------------------------------------

  /// Canonical session state derived from the persisted login, the compiled-in
  /// backend configuration and live connectivity.
  AuthState get authState {
    if (!_loggedIn) return AuthState.signedOut;
    if (_online && backendConfigured && _backendOnline) {
      return AuthState.authenticated;
    }
    return AuthState.offlineAuthenticated;
  }

  /// Honest one-line description of the session state (shown in More Tab).
  String get authStateLabel => switch (authState) {
        AuthState.signedOut => 'Signed out',
        AuthState.unknown => 'Starting…',
        AuthState.authenticated => 'Signed in to the backend',
        AuthState.offlineAuthenticated =>
          ApiConfig.isConfigured
              ? 'Offline — using saved account'
              : 'No backend configured — using saved account',
      };

  Workspace get activeWorkspace => _activeWorkspace;

  /// Workspaces this account may enter without logging in again.
  ///
  /// A demo (unconfigured) account can enter every persona the seed actually
  /// models (beekeeper, FPO, lab, processor, buyer, institution, consumer).
  /// When the account is backed by the FastAPI backend the list is narrowed to
  /// the workspaces the account's role is allowed to enter — never invented.
  List<Workspace> get availableWorkspaces {
    if (_backendSignedIn && _backendRole != null) {
      final role = _backendRole;
      final workspaces = <Workspace>[Workspace.beekeeper, Workspace.consumer];
      if (role == 'fpo' ||
          role == 'admin' ||
          role == 'field_officer' ||
          role == 'organization') {
        workspaces.add(Workspace.organization);
      }
      if (role == 'lab' || role == 'admin') {
        workspaces.add(Workspace.lab);
      }
      if (role == 'processor' || role == 'admin') {
        workspaces.add(Workspace.processor);
      }
      if (role == 'buyer') {
        workspaces.add(Workspace.buyer);
      }
      if (role == 'institution' || role == 'govt' || role == 'registrar') {
        workspaces.add(Workspace.institution);
      }
      if (role == 'platform_oversight') {
        workspaces.add(Workspace.platform);
      }
      return workspaces;
    }
    return const [
      Workspace.beekeeper,
      Workspace.organization,
      Workspace.lab,
      Workspace.processor,
      Workspace.buyer,
      Workspace.institution,
      Workspace.consumer,
    ];
  }

  /// Switches the current workspace without ending the session. Only
  /// workspaces the account can actually enter are accepted.
  bool switchWorkspace(Workspace workspace) {
    if (!availableWorkspaces.contains(workspace)) return false;
    if (workspace == _activeWorkspace) return true;
    _activeWorkspace = workspace;
    if (workspace == Workspace.organization || workspace == Workspace.lab) {
      _fpoRole = true;
    }
    LocalStore.instance.saveActiveWorkspace(workspace.code);
    notifyListeners();
    return true;
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
        .where((h) => h.syncStatus != SyncStatus.synced)
        .length;
    final pendingBatches = batches
        .where((b) => b.syncStatus != SyncStatus.synced)
        .length;
    return pendingHarvests + pendingBatches;
  }

  /// Records waiting for upload: [SyncStatus.pending] (new) or
  /// [SyncStatus.failed] (retry pending). Never includes synced records.
  List<Harvest> get pendingHarvests =>
      harvests.where((h) => h.syncStatus != SyncStatus.synced).toList();

  List<Batch> get pendingBatches =>
      batches.where((b) => b.syncStatus != SyncStatus.synced).toList();

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

  /// Adds a new hive to the beekeeper's apiary. The id is derived from the
  /// current hive count so it stays unique and remains stable across resets
  /// (never reusing the seeded hive-001..004 ids).
  Hive addHive({
    required String name,
    required String location,
    required String honeyType,
    String detail = '',
  }) {
    final base = 'hive-new';
    var n = 1;
    var id = '$base-$n';
    final existing = hives.map((h) => h.id).toSet();
    while (existing.contains(id)) {
      n += 1;
      id = '$base-$n';
    }
    final hive = Hive(
      id: id,
      name: name.trim().isEmpty ? id : name.trim(),
      beekeeperId: currentBeekeeper.id,
      organizationId: currentBeekeeper.organizationId,
      location: location.trim(),
      honeyType: honeyType.trim().isEmpty ? 'Floral Honey' : honeyType.trim(),
      detail: detail.trim(),
    );
    _repository.addHive(hive);
    _persistHives();
    notifyListeners();
    return hive;
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
  // Trust model (explicit tiers; see services/trust_service.dart)
  // ---------------------------------------------------------------------

  /// Trust snapshot for a batch, evaluated from its persisted records.
  ///
  /// Split children inherit the parent's verified history; a merged lot is
  /// only as trustworthy as its weakest child. Both rules are enforced here,
  /// never in the UI.
  TrustState trustFor(Batch batch) {
    final relations = _repository.relationsForBatch(batch.id);

    final splitFrom = relations.where(
      (r) => r.type == RelationType.split && r.childBatchId == batch.id,
    );
    if (splitFrom.isNotEmpty) {
      final parent = batchById(splitFrom.first.parentBatchId);
      if (parent != null) return trustService.inheritOnSplit(parent);
    }

    final aggregatedFrom = relations.where(
      (r) => r.type == RelationType.aggregate && r.parentBatchId == batch.id,
    );
    if (aggregatedFrom.isNotEmpty) {
      final children = <Batch>[
        for (final r in aggregatedFrom) ?batchById(r.childBatchId),
      ];
      if (children.isNotEmpty) {
        final base = trustService.evaluate(batch);
        final childStates = [for (final c in children) trustService.evaluate(c)];
        final caveats = <String>[
          ...base.caveats,
          'Merged from ${children.length} lots; trust is the weakest child.',
        ];
        if (childStates.any((s) => s.isPrototypeAnchor)) {
          caveats.insert(
            0,
            'Integrity anchoring is on prototype mock infrastructure - not a '
            'production blockchain. Shown for demonstration only.',
          );
        }
        return TrustState(
          tier: trustService.mergeTier(children),
          claims: base.claims,
          caveats: caveats,
          passCount: childStates.fold(0, (sum, s) => sum + s.passCount),
          failCount: childStates.fold(0, (sum, s) => sum + s.failCount),
          custodyCount: childStates.fold(0, (sum, s) => sum + s.custodyCount),
          anchorCount: childStates.fold(0, (sum, s) => sum + s.anchorCount),
          isPrototypeAnchor: childStates.any((s) => s.isPrototypeAnchor),
        );
      }
    }

    return trustService.evaluate(batch);
  }

  /// Splits a batch into sub-batches (service-enforced quantity guards).
  List<Batch> splitBatchInto(Batch parent, List<double> parts) {
    final children = batchService.splitBatch(parent, parts);
    _persistBatches();
    _persistRelations();
    notifyListeners();
    return children;
  }

  /// Merges lots into one new batch; trust = weakest child's tier.
  Batch mergeBatchesFrom(List<Batch> children) {
    final merged = batchService.mergeBatches(children);
    _activeV2Batch = merged.copyWith(syncStatus: SyncStatus.synced);
    _repository.updateBatch(_activeV2Batch!);
    _persistBatches();
    _persistRelations();
    notifyListeners();
    return _activeV2Batch!;
  }

  /// Appends a correction without rewriting the audit trail.
  Batch correctBatch(
    Batch batch, {
    required String description,
    String? origin,
    String? honeyType,
    double? quantityKg,
  }) {
    final updated = batchService.recordCorrection(
      batch,
      description: description,
      origin: origin,
      honeyType: honeyType,
      quantityKg: quantityKg,
    );
    _persistBatches();
    notifyListeners();
    return updated;
  }

  /// Resolves any scanned or typed string to a batch / product / jar.
  ScanResolution resolveScan(String raw) {
    final payload = TraceQrService.parse(raw);
    if (payload != null) {
      if (payload.isJar) {
        final jar = _repository.jarById(payload.code);
        if (jar == null) {
          return const ScanResolutionUnknown(
            'This jar code is not in the local registry yet.',
          );
        }
        return ScanResolutionJar(jar);
      }
      if (payload.isTrace) {
        final product = productByCode(payload.code);
        if (product != null) return ScanResolutionProduct(product);
        final batch = batchByCode(payload.code);
        if (batch != null) return ScanResolutionBatch(batch);
        final viaPassport = batchForPassport(payload.code.toLowerCase());
        if (viaPassport != null) return ScanResolutionBatch(viaPassport);
        return const ScanResolutionUnknown(
          'This product code is not in the local registry yet.',
        );
      }
      return const ScanResolutionUnknown('Unsupported QR type.');
    }

    // Bare codes typed by hand (products, jars or batch codes).
    final upper = raw.trim().toUpperCase();
    if (upper.isNotEmpty) {
      final product = productByCode(upper);
      if (product != null) return ScanResolutionProduct(product);
      final jar = _repository.jarById(upper);
      if (jar != null) return ScanResolutionJar(jar);
      final batch = batchByCode(upper);
      if (batch != null) return ScanResolutionBatch(batch);
    }
    return const ScanResolutionUnknown(
      'No matching product, jar or batch was found.',
    );
  }

  /// The recorded journey of a batch, derived strictly from persisted
  /// audit / custody / lab / processing / anchor / relation records.
  List<BatchEvent> journeyFor(Batch batch) {
    final out = <BatchEvent>[];
    void add(
      BatchEventType type,
      String label,
      String actor,
      DateTime at,
      String description, [
      String? relatedCode,
    ]) {
      out.add(BatchEvent(
        type: type,
        label: label,
        actor: actor,
        at: at,
        description: description,
        relatedBatchCode: relatedCode,
      ));
    }

    for (final audit in eventsFor(batch)) {
      final type = switch (audit.type) {
        'CREATED' => BatchEventType.registered,
        'COLLECTED' => BatchEventType.collected,
        'LAB_PASS' => BatchEventType.labPass,
        'LAB_FAIL' => BatchEventType.labFail,
        'PROCESSING' => BatchEventType.processing,
        'ANCHORED' || 'PACKAGING_ANCHORED' => BatchEventType.anchored,
        'CORRECTION' => BatchEventType.corrected,
        'SPLIT_FROM' => BatchEventType.splitFrom,
        'AGGREGATED_FROM' => BatchEventType.aggregatedFrom,
        _ => BatchEventType.registered,
      };
      add(
        type,
        audit.type.replaceAll('_', ' ').toLowerCase(),
        audit.actor,
        audit.recordedAt,
        audit.description,
      );
    }
    for (final custody in custodyFor(batch)) {
      if (out.any((e) => e.at == custody.recordedAt)) continue;
      add(
        BatchEventType.collected,
        'custody',
        custody.toOrganizationId,
        custody.recordedAt,
        custody.note,
      );
    }
    for (final processing in processingFor(batch)) {
      add(
        BatchEventType.processing,
        'processing',
        processing.unit,
        processing.date,
        'Processing recorded at ${processing.unit}.',
      );
    }
    for (final relation in _repository.relationsForBatch(batch.id)) {
      if (relation.parentBatchId == batch.id) {
        final child = batchById(relation.childBatchId);
        add(
          BatchEventType.aggregatedFrom,
          'merging',
          'Organization / FPO',
          relation.createdAt,
          'Aggregated ${child?.code ?? relation.childBatchId} into this batch.',
          child?.code,
        );
      } else if (relation.childBatchId == batch.id) {
        final parent = batchById(relation.parentBatchId);
        add(
          BatchEventType.splitFrom,
          'split',
          'Organization / FPO',
          relation.createdAt,
          'This batch was split from ${parent?.code ?? relation.parentBatchId}.',
          parent?.code,
        );
      }
    }

    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  // ---------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------

  /// Drains every unsynced record (pending or failed) through the sync engine.
  ///
  /// Marks each item [SyncStatus.synced] on success and [SyncStatus.failed]
  /// (with an incremented attempt count + error) on failure, so the durable
  /// queue state survives restarts. Safe to call repeatedly: failures retry on
  /// the next pass with backoff through the per-item attempt counter.
  Future<bool> _syncPendingRecords() async {
    final queueHarvests = harvests
        .where((h) => h.syncStatus != SyncStatus.synced)
        .toList();
    final queueBatches = batches
        .where((b) => b.syncStatus != SyncStatus.synced)
        .toList();
    if (queueHarvests.isEmpty && queueBatches.isEmpty) return false;

    _syncing = true;
    var anyFailed = false;
    try {
      await _syncEngine.process(
        pendingHarvests: queueHarvests,
        pendingBatches: queueBatches,
        onHarvestSynced: (h) {
          _syncAttempts.remove(h.id);
          _syncErrors.remove(h.id);
          _repository.updateHarvest(h.copyWith(syncStatus: SyncStatus.synced));
        },
        onBatchSynced: (b) {
          _syncAttempts.remove(b.id);
          _syncErrors.remove(b.id);
          _repository.updateBatch(b.copyWith(syncStatus: SyncStatus.synced));
        },
        onHarvestFailed: (h) {
          anyFailed = true;
          _syncAttempts[h.id] = (_syncAttempts[h.id] ?? 0) + 1;
          _syncErrors[h.id] = _syncEngine.lastError ?? 'sync.rejected';
          _repository.updateHarvest(h.copyWith(syncStatus: SyncStatus.failed));
        },
        onBatchFailed: (b) {
          anyFailed = true;
          _syncAttempts[b.id] = (_syncAttempts[b.id] ?? 0) + 1;
          _syncErrors[b.id] = _syncEngine.lastError ?? 'sync.rejected';
          _repository.updateBatch(b.copyWith(syncStatus: SyncStatus.failed));
        },
      );
    } finally {
      _syncing = false;
    }

    _syncError = anyFailed ? (_syncErrors.values.isEmpty ? null : _syncErrors.values.last) : null;
    await _persistSyncState();
    _persistHarvests();
    _persistBatches();
    notifyListeners();
    return true;
  }

  /// Public entry point for a manual/forced sync (dev controls, resume).
  Future<bool> syncPendingNow() => _syncPendingRecords();

  /// Drops recorded sync failures and attempt counters (dev controls).
  void clearSyncErrors() {
    _syncError = null;
    _syncErrors = {};
    _syncAttempts = {};
    _persistSyncState();
    notifyListeners();
  }

  Future<void> _persistSyncState() async {
    await LocalStore.instance.saveSyncAttempts(_syncAttempts);
    await LocalStore.instance.saveSyncErrors(_syncErrors);
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

  /// Legacy anchor action (kept for older demo consumers). Honest by
  /// construction: it never fabricates a hash — [blockchainHash] stays empty
  /// until a REAL transaction hash is returned by the backend, and the status
  /// is reported as a local demo commitment only.
  void anchorBlockchain() {
    if (_batch.integrityAnchored) return;
    _addEvent(
      HoneyEvent(
        type: 'ANCHOR',
        actor: 'HoneyChain Integrity Layer',
        timestamp: _now(),
        status: 'Committed',
        description: 'Verification evidence committed to the on-device '
            'integrity log (demo). No blockchain hash is fabricated.',
      ),
    );
    _batch = _batch.copyWith(
      blockchainStatus: 'committed',
      blockchainHash: '',
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

  // ---------------------------------------------------------------------
  // Backend API + IoT simulator (real FastAPI connectivity)
  // ---------------------------------------------------------------------
  //
  // The app talks to `ApiConfig.baseUrl` (https in production, or the
  // http://localhost:8000 dev override). Every call is guarded so widget tests
  // (testMode) never touch the network, and failures degrade to an explicit
  // "backend offline / not signed in" state instead of fake statuses.

  late final ApiClient _apiClient = ApiClient(
    tokenProvider: () => ApiTokenStore.instance.token,
  );
  late final BackendIotService backendIotService = BackendIotService(_apiClient);
  late final PassportVerificationService passportVerificationService =
      PassportVerificationService(_apiClient);

  bool _backendChecked = false;
  bool _backendOnline = false;
  bool _backendBusy = false;
  String? _backendError;
  bool _backendSignedIn = false;
  String? _backendRole;
  List<IotDevice> _apiDevices = [];
  List<SimulatorDeviceStatus> _apiSimulatorStatus = [];
  List<BackendNotification> _apiNotifications = [];
  final Map<String, List<IotTelemetry>> _apiTelemetry = {};

  /// True when a backend base URL was compiled in (see [ApiConfig]).
  bool get backendConfigured => ApiConfig.isConfigured;

  bool get backendChecked => _backendChecked;
  bool get backendOnline => _backendOnline;
  bool get backendBusy => _backendBusy;
  String? get backendError => _backendError;

  /// True when a FastAPI session (JWT) is present.
  bool get backendSignedIn => _backendSignedIn;
  String get backendRole => _backendRole ?? '';
  String get backendDisplayRole => _backendRole ?? 'not signed in';

  List<IotDevice> get apiDevices => List.unmodifiable(_apiDevices);
  List<SimulatorDeviceStatus> get apiSimulatorStatus =>
      List.unmodifiable(_apiSimulatorStatus);
  List<BackendNotification> get apiNotifications =>
      List.unmodifiable(_apiNotifications);
  int get apiUnreadNotifications =>
      _apiNotifications.where((n) => !n.read).length;

  List<IotTelemetry> apiTelemetryFor(String deviceId) =>
      List.unmodifiable(_apiTelemetry[deviceId] ?? const []);

  /// Restores a persistent FastAPI session (JWT + role) after a restart so the
  /// backend sign-in survives the app being killed (identity lives in
  /// [ApiTokenStore]).
  void _restoreBackendSession() {
    final identity = ApiTokenStore.instance.identity;
    if (identity != null && identity.token.isNotEmpty) {
      _backendSignedIn = true;
      _backendRole = identity.role.isEmpty ? null : identity.role;
    }
  }

  /// Probes `/api/v1/health`. Safe to call from non-test code only.
  Future<void> _probeBackend() async {
    _backendChecked = true;
    if (testMode || !ApiConfig.isConfigured) {
      _backendOnline = false;
      _backendError = null;
      return;
    }
    try {
      await _apiClient.getJson('/api/v1/health');
      _backendOnline = true;
      _backendError = null;
    } on ApiException catch (error) {
      _backendOnline = false;
      _backendError = backendFailureFriendly(error);
    } on Exception {
      _backendOnline = false;
      _backendError = 'Backend could not be reached';
    }
  }

  /// Refreshes everything the IoT/alerts screens need from the backend.
  ///
  /// Idempotent and failure-tolerant: a single bad call marks the backend
  /// offline instead of leaving stale data presented as live.
  Future<bool> refreshBackendIoT() async {
    if (testMode || !ApiConfig.isConfigured) {
      _backendChecked = true;
      _backendOnline = false;
      return false;
    }
    await _probeBackend();
    if (!_backendOnline) {
      notifyListeners();
      return false;
    }

    _backendBusy = true;
    notifyListeners();
    final token = ApiTokenStore.instance.token;
    _backendSignedIn = token != null && token.isNotEmpty;
    try {
      if (_backendSignedIn) {
        _apiDevices = await backendIotService.registeredDevices();
        for (final device in _apiDevices) {
          try {
            _apiTelemetry[device.deviceId] =
                await backendIotService.deviceTelemetry(device.deviceId, limit: 10);
          } on ApiException {
            _apiTelemetry[device.deviceId] = [];
          }
        }
        _apiSimulatorStatus = await backendIotService.simulatorStatus();
        _apiNotifications = await backendIotService.notifications();
      } else {
        _apiDevices = [];
        _apiTelemetry.clear();
        _apiSimulatorStatus = [];
        _apiNotifications = [];
      }
      _backendError = _backendSignedIn ? null : 'Signed out - sign in to view backend data';
    } on ApiException catch (error) {
      _backendOnline = false;
      _backendError = backendFailureFriendly(error);
    } on Exception {
      _backendOnline = false;
      _backendError = 'Backend request failed';
    } finally {
      _backendBusy = false;
      notifyListeners();
    }
    return _backendOnline;
  }

  /// Logs in to the FastAPI backend with the demo/operator credentials and
  /// refreshes backend collections. Returns the role on success, null on
  /// failure ([backendError] carries the reason).
  Future<String?> backendLogin(String identifier, String password) async {
    if (testMode || !ApiConfig.isConfigured) return null;
    try {
      final repository = FastApiAuthRepository(_apiClient);
      final identity =
          await repository.login(identifier: identifier, password: password);
      _backendSignedIn = true;
      _backendRole = identity.role;
      await refreshBackendIoT();
      return identity.role;
    } on ApiException catch (error) {
      _backendError = backendFailureFriendly(error);
      notifyListeners();
      return null;
    } on Exception {
      _backendError = 'Backend login failed';
      notifyListeners();
      return null;
    }
  }

  Future<void> backendSignOut() async {
    await ApiTokenStore.instance.clear();
    _backendSignedIn = false;
    _backendRole = null;
    _apiDevices = [];
    _apiNotifications = [];
    _apiSimulatorStatus = [];
    _apiTelemetry.clear();
    notifyListeners();
  }

  /// Registers a simulator device. Returns the signed secrets (shown once).
  Future<Map<String, dynamic>?> registerSimulatorDevice({
    required String deviceName,
    String assignedHiveId = '',
  }) async {
    if (testMode || !_backendOnline || !_backendSignedIn) return null;
    try {
      final result = await backendIotService.registerDevice(
        deviceName: deviceName,
        assignedHiveId: assignedHiveId,
      );
      await refreshBackendIoT();
      return result;
    } on ApiException catch (error) {
      _backendError = backendFailureFriendly(error);
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> simulatorAction(
    String deviceId,
    String action, {
    String? mode,
    int burstCount = 10,
    TelemetryPayload? custom,
  }) async {
    if (testMode || !_backendOnline || !_backendSignedIn) return null;
    try {
      final result = await backendIotService.simulatorControl(
        deviceId,
        action,
        mode: mode,
        burstCount: burstCount,
        custom: custom,
      );
      await refreshBackendIoT();
      return result;
    } on ApiException catch (error) {
      _backendError = backendFailureFriendly(error);
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> simulatorMode(String deviceId, String mode) =>
      simulatorAction(deviceId, 'START', mode: mode);

  Future<Map<String, dynamic>?> simulatorFork(String deviceId) async {
    if (testMode || !_backendOnline || !_backendSignedIn) return null;
    try {
      final result = await backendIotService.simulatorFork(deviceId);
      await refreshBackendIoT();
      return result;
    } on ApiException catch (error) {
      _backendError = backendFailureFriendly(error);
      notifyListeners();
      return null;
    }
  }

  Future<void> markBackendNotificationRead(String notificationId) async {
    if (testMode || !_backendOnline || !_backendSignedIn) return;
    try {
      await backendIotService.markNotificationRead(notificationId);
      _apiNotifications = [
        for (final n in _apiNotifications)
          if (n.notificationId == notificationId)
            BackendNotification(
              notificationId: n.notificationId,
              hiveId: n.hiveId,
              batchId: n.batchId,
              deviceId: n.deviceId,
              category: n.category,
              severity: n.severity,
              reason: n.reason,
              recommendedAction: n.recommendedAction,
              source: n.source,
              title: n.title,
              body: n.body,
              createdAt: n.createdAt,
              read: true,
              isSimulated: n.isSimulated,
            )
          else
            n,
      ];
      notifyListeners();
    } on ApiException catch (error) {
      _backendError = backendFailureFriendly(error);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------
  // Beekeeper production path (server-backed collections)
  // ---------------------------------------------------------------------

  /// Typed view of the verified FastAPI backend (beekeeper path). Additive to
  /// the offline-first local store; never replaces it.
  late final HoneyApiService honeyApi = HoneyApiService(_apiClient);

  /// Typed view of the platform-oversight endpoints (`/api/v1/platform/...`).
  /// Only meaningful once the signed-in role is `platform_oversight`; the
  /// backend rejects anyone else with 403.
  late final PlatformApiService platformApi = PlatformApiService(_apiClient);

  List<ServerHive> _serverHives = [];
  List<ServerHarvest> _serverHarvests = [];
  List<ServerBatch> _serverBatches = [];
  ServerBlockchainHealth? _blockchainHealth;
  ServerBlockchainStatus? _blockchainStatus;
  ServerEvidenceBundle? _lastAnchoredBundle;
  List<ServerEvidenceBundle> _serverBundles = [];
  ServerOrgDashboard? _orgDashboard;
  String? _orgDashboardError;
  bool _orgDashboardBusy = false;
  String? _serverCollectionsError;
  bool _serverCollectionsBusy = false;

  /// Live backend identity (token store) after a beekeeper login.
  ApiIdentity? get backendIdentity => ApiTokenStore.instance.identity;

  /// Server-issued producer id (`HC-BK-XXXXXX`) from the signed-in session, or
  /// the seeded demo beekeeper's id when no backend session exists.
  String get producerId {
    final identity = backendIdentity;
    if (identity != null) return identity.producerId;
    return 'HC-BK-000001';
  }

  List<ServerHive> get serverHives => List.unmodifiable(_serverHives);
  List<ServerHarvest> get serverHarvests =>
      List.unmodifiable(_serverHarvests);
  List<ServerBatch> get serverBatches => List.unmodifiable(_serverBatches);
  ServerBlockchainHealth? get blockchainHealth => _blockchainHealth;
  ServerBlockchainStatus? get blockchainStatus => _blockchainStatus;
  ServerEvidenceBundle? get lastAnchoredBundle => _lastAnchoredBundle;
  List<ServerEvidenceBundle> get serverBundles =>
      List.unmodifiable(_serverBundles);
  String? get serverCollectionsError => _serverCollectionsError;
  bool get serverCollectionsBusy => _serverCollectionsBusy;

  /// Live backend-driven FPO dashboard metrics (null until the signed-in org
  /// round-trips successfully). Real numbers only — the UI falls back to the
  /// offline local view otherwise.
  ServerOrgDashboard? get orgDashboard => _orgDashboard;
  String? get orgDashboardError => _orgDashboardError;
  bool get orgDashboardBusy => _orgDashboardBusy;

  /// True when the shell should surface server data. Signed-in means a `/me`
  /// round-trip already succeeded, so the backend was reached; per-collection
  /// failures (e.g. an IoT endpoint scoped to another role) are reported via
  /// [serverCollectionsError] / [backendError] instead of hiding the UI.
  bool get backendModeActive => _backendSignedIn && ApiConfig.isConfigured;

  /// Maps a server hive to the local [Hive] shape the beekeeper UI renders.
  Hive hiveFromServer(ServerHive server) => Hive(
        id: server.id,
        name: server.hiveCode.isEmpty ? server.id : server.hiveCode,
        beekeeperId:
            server.beekeeperId.isEmpty ? currentBeekeeper.id : server.beekeeperId,
        organizationId: server.orgId,
        location: server.location,
        honeyType: 'Apiary',
        detail: 'backend · ${server.status}',
      );

  /// Harvest view of a server harvest row (same shape as local for listing).
  Harvest harvestFromServer(ServerHarvest server) => Harvest(
        id: server.id,
        hiveId: server.hiveId,
        beekeeperId: server.beekeeperId,
        harvestedAt: server.harvestedAt,
        honeyType: server.honeyType,
        quantityKg: server.quantityKg,
        syncStatus: SyncStatus.synced,
        status: server.collected ? HarvestStatus.collected : HarvestStatus.pending,
      );

  /// Pulls live blockchain health (public endpoint) plus the beekeeper's
  /// hives/harvests/batches and blockchain status (authed) from the backend.
  ///
  /// Failure-tolerant: one bad call records into [serverCollectionsError]
  /// without blanking already-cached collections.
  Future<bool> refreshServerCollections() async {
    if (testMode || !ApiConfig.isConfigured) {
      _blockchainHealth = null;
      _blockchainStatus = null;
      return false;
    }

    if (_serverCollectionsBusy) return false;
    _serverCollectionsBusy = true;
    _serverCollectionsError = null;
    notifyListeners();

    final errors = <String>[];

    try {
      _blockchainHealth = await honeyApi.blockchainHealth();
    } on ApiException catch (error) {
      errors.add('blockchain health: ${backendFailureFriendly(error)}');
    } on Exception {
      errors.add('blockchain health unavailable');
    }

    if (_backendSignedIn) {
      await _loadServerHives(errors);
      await _loadServerHarvests(errors);
      await _loadServerBatches(errors);
      await refreshOrgDashboard();
      if (_blockchainHealth?.isConnected ?? false) {
        try {
          _blockchainStatus = await honeyApi.blockchainStatus();
        } on ApiException catch (error) {
          errors.add('blockchain status: ${backendFailureFriendly(error)}');
        } on Exception {
          errors.add('blockchain status unavailable');
        }
      }
    }

    _serverCollectionsError = errors.isEmpty ? null : errors.join(' · ');
    _serverCollectionsBusy = false;
    notifyListeners();
    return errors.isEmpty && _backendSignedIn;
  }

  Future<void> _loadServerHives(List<String> errors) async {
    try {
      _serverHives = await honeyApi.listHives();
    } on ApiException catch (error) {
      errors.add('hives: ${backendFailureFriendly(error)}');
    } on Exception {
      errors.add('hives unavailable');
    }
  }

  Future<void> _loadServerHarvests(List<String> errors) async {
    try {
      _serverHarvests = await honeyApi.listHarvests();
    } on ApiException catch (error) {
      errors.add('harvests: ${backendFailureFriendly(error)}');
    } on Exception {
      errors.add('harvests unavailable');
    }
  }

  Future<void> _loadServerBatches(List<String> errors) async {
    try {
      _serverBatches = await honeyApi.listBatches();
    } on ApiException catch (error) {
      errors.add('batches: ${backendFailureFriendly(error)}');
    } on Exception {
      errors.add('batches unavailable');
    }
  }

  /// Fetches the signed-in org's aggregate dashboard from the backend. The
  /// org id comes from the user's own session ([ApiIdentity.organizationId]),
  /// so an FPO can only ever read their own org's numbers. Every metric is
  /// server-derived; counters stay at their true values (0 until real data).
  Future<bool> refreshOrgDashboard() async {
    if (testMode || !ApiConfig.isConfigured || !_backendSignedIn) {
      _orgDashboard = null;
      _orgDashboardError = null;
      return false;
    }
    final orgId = backendIdentity?.organizationId ?? '';
    if (orgId.isEmpty) return false;
    if (_orgDashboardBusy) return false;

    _orgDashboardBusy = true;
    _orgDashboardError = null;
    notifyListeners();
    try {
      _orgDashboard = await honeyApi.organizationDashboard(orgId);
      _orgDashboardBusy = false;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _orgDashboardError = backendFailureFriendly(error);
      _orgDashboardBusy = false;
      notifyListeners();
      return false;
    } on Exception {
      _orgDashboardError = 'org dashboard unavailable';
      _orgDashboardBusy = false;
      notifyListeners();
      return false;
    }
  }

  /// Logs a beekeeper into the FastAPI backend and connects the app shell
  /// (same gate as the demo login) so they land in HoneyChain with their real
  /// server hives/harvests refreshed. Returns the role, or null on failure
  /// ([backendError] carries the reason).
  Future<String?> beekeeperLogin({
    required String identifier,
    required String password,
  }) async {
    final role = await backendLogin(identifier, password);
    if (role == null) return null;
    _profile = _profile.copyWith(
      name: (backendIdentity?.name.isNotEmpty ?? false)
          ? backendIdentity!.name
          : _profile.name,
      phone: (backendIdentity?.email.isNotEmpty ?? false)
          ? backendIdentity!.email
          : _profile.phone,
    );
    LocalStore.instance.saveProfile(_profile);
    _loggedIn = true;
    LocalStore.instance.saveLoggedIn(true);
    if (role == 'beekeeper') {
      await refreshServerCollections();
    }
    notifyListeners();
    return role;
  }

  /// local record + push: keeps the offline-first local harvest AND, when
  /// signed into the backend, creates the harvest live (returns the server
  /// row with the real server id, so evidence can anchor against it).
  Future<ServerHarvest?> pushHarvestToBackend(Harvest harvest) async {
    if (testMode || !ApiConfig.isConfigured || !_backendSignedIn) return null;
    try {
      final server = await honeyApi.createHarvest(
        hiveId: harvest.hiveId,
        quantityKg: harvest.quantityKg,
        harvestedAt: harvest.harvestedAt,
        honeyType: harvest.honeyType,
        beekeeperId: backendIdentity?.id ?? '',
      );
      _repository.updateHarvest(harvest.copyWith(syncStatus: SyncStatus.synced));
      _serverHarvests = [
        for (final h in _serverHarvests)
          if (h.id != server.id) h,
        server,
      ];
      notifyListeners();
      return server;
    } on ApiException catch (error) {
      _serverCollectionsError = backendFailureFriendly(error);
      notifyListeners();
      return null;
    } on Exception {
      notifyListeners();
      return null;
    }
  }

  /// Resolves a code against the public backend passport endpoint. When no
  /// backend is compiled in the result is [VerifyOutcome.unresolved] — the
  /// app never synthesises a verification.
  Future<PassportVerificationResult> verifyPassport(String code) async {
    if (testMode || !ApiConfig.isConfigured) {
      return PassportVerificationResult.unresolved();
    }
    return verifyPassportOnline(passportVerificationService, code);
  }

  /// Creates a hive in the backend too (offline local copy is still kept).
  Future<ServerHive?> addHiveToBackend({
    required String name,
    String? location,
  }) async {
    if (testMode || !ApiConfig.isConfigured || !_backendSignedIn) return null;
    try {
      final server = await honeyApi.createHive(
        hiveCode: name,
        beekeeperId: backendIdentity?.id ?? '',
        location: location,
      );
      _serverHives = [
        for (final h in _serverHives)
          if (h.id != server.id) h,
        server,
      ];
      notifyListeners();
      return server;
    } on ApiException catch (error) {
      _serverCollectionsError = backendFailureFriendly(error);
      notifyListeners();
      return null;
    } on Exception {
      notifyListeners();
      return null;
    }
  }

  /// Anchors harvest evidence onto the live Fabric chain through the backend
  /// (`POST /api/v1/evidence/bundles` with `anchor: true`). [serverHarvestId]
  /// is the server harvest id after a successful push.
  Future<ServerEvidenceBundle?> anchorHarvestEvidence({
    required Harvest harvest,
    String? serverHarvestId,
    double? latitude,
    double? longitude,
  }) async {
    if (testMode || !ApiConfig.isConfigured || !_backendSignedIn) return null;
    try {
      final name = (backendIdentity?.name.isNotEmpty ?? false)
          ? backendIdentity!.name
          : (backendIdentity?.email ?? currentBeekeeper.name);
      final bundle = await honeyApi.createHarvestEvidenceBundle(
        entityRef: serverHarvestId ?? harvest.id,
        operator: name,
        deviceId: 'HC-APP-${backendIdentity?.id ?? 'mobile'}',
        quantityKg: harvest.quantityKg,
        honeyType: harvest.honeyType,
        harvestedAt: harvest.harvestedAt,
        latitude: latitude,
        longitude: longitude,
      );
      _lastAnchoredBundle = bundle;
      _serverBundles = [bundle, ..._serverBundles];
      notifyListeners();
      return bundle;
    } on ApiException catch (error) {
      _serverCollectionsError = backendFailureFriendly(error);
      notifyListeners();
      return null;
    } on Exception {
      notifyListeners();
      return null;
    }
  }

  /// Re-verifies the last anchored bundle against the backend (Merkle
  /// membership + ledger state).
  Future<ServerEvidenceVerify?> verifyLastBundle() async {
    final bundle = _lastAnchoredBundle;
    if (bundle == null || testMode || !ApiConfig.isConfigured) return null;
    try {
      final result = await honeyApi.verifyBundle(bundle.bundleId);
      notifyListeners();
      return result;
    } on ApiException catch (error) {
      _serverCollectionsError = backendFailureFriendly(error);
      notifyListeners();
      return null;
    } on Exception {
      notifyListeners();
      return null;
    }
  }

  /// Signs out of the backend and clears server-backed collections while
  /// returning the app to the demo screen.
  void beekeeperSignOut() {
    _serverHives = [];
    _serverHarvests = [];
    _serverBatches = [];
    _serverBundles = [];
    _lastAnchoredBundle = null;
    _blockchainHealth = null;
    _blockchainStatus = null;
    _orgDashboard = null;
    _orgDashboardError = null;
    _serverCollectionsError = null;
    if (ApiConfig.isConfigured) {
      unawaited(honeyApi.signOut());
    }
    _loggedIn = false;
    LocalStore.instance.saveLoggedIn(false);
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivity?.removeListener(_onConnectivityChanged);
    _connectivity?.dispose();
    super.dispose();
  }
}
