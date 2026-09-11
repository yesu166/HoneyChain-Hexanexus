import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/disease.dart';
import '../models/domain.dart';
import '../bee_health/models/bee_health_models.dart';

/// Local, offline-first persistence for essential beekeeper data.
///
/// Everything here survives app restarts with no network. The FastAPI +
/// Supabase backend will mirror these records later; until then they remain
/// safely stored on-device.
class LocalStore {
  LocalStore._();

  static final LocalStore instance = LocalStore._();

  static const _kProfile = 'honey.profile';
  static const _kLanguage = 'honey.language';
  static const _kLoggedIn = 'honey.loggedIn';
  static const _kActiveWorkspace = 'honey.activeWorkspace';
  static const _kBuyerId = 'honey.buyerId';
  static const _kHives = 'honey.hives';
  static const _kHarvests = 'honey.harvests';
  static const _kBatches = 'honey.batches';
  static const _kVerifications = 'honey.verifications';
  static const _kAlerts = 'honey.alerts';
  static const _kHealth = 'honey.healthChecks';
  static const _kBeeHealthEvents = 'honey.beeHealthEvents';
  static const _kTreatments = 'honey.treatments';
  static const _kFollowUps = 'honey.followUps';
  static const _kCustody = 'honey.custody';
  static const _kAnchors = 'honey.anchors';
  static const _kProcessing = 'honey.processing';
  static const _kRelations = 'honey.relations';
  static const _kProductBatches = 'honey.productBatches';
  static const _kPackagingBatches = 'honey.packagingBatches';
  static const _kJars = 'honey.jars';
  static const _kListings = 'honey.listings';
  static const _kRequests = 'honey.requests';
  static const _kPassports = 'honey.passports';
  static const _kSyncAttempts = 'honey.syncAttempts';
  static const _kSyncErrors = 'honey.syncErrors';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> saveProfile(BeekeeperProfile profile) async {
    await _set(_kProfile, jsonEncode(profile.toJson()));
  }

  BeekeeperProfile? loadProfile() {
    final raw = _get(_kProfile);
    if (raw == null) return null;
    return BeekeeperProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveLanguage(String code) => _set(_kLanguage, code);

  String? loadLanguage() => _get(_kLanguage);

  /// Buyer identity (organization / member name) used when creating jar
  /// allocations. Stored locally so purchases keep the buyer's identity
  /// without a hardcoded demo id.
  Future<void> saveBuyerId(String buyerId) => _set(_kBuyerId, buyerId);

  String? loadBuyerId() => _get(_kBuyerId);

  Future<void> saveLoggedIn(bool value) => _set(_kLoggedIn, value.toString());

  bool loadLoggedIn() => _get(_kLoggedIn) == 'true';

  Future<void> saveActiveWorkspace(String code) => _set(_kActiveWorkspace, code);

  String? loadActiveWorkspace() => _get(_kActiveWorkspace);

  Future<void> saveHives(List<Hive> hives) =>
      _set(_kHives, jsonEncode([for (final h in hives) h.toJson()]));

  List<Hive>? loadHives() {
    final raw = _get(_kHives);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) Hive.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveHarvests(List<Harvest> harvests) =>
      _set(_kHarvests, jsonEncode([for (final h in harvests) h.toJson()]));

  List<Harvest>? loadHarvests() {
    final raw = _get(_kHarvests);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) Harvest.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveBatches(List<Batch> batches) =>
      _set(_kBatches, jsonEncode([for (final b in batches) b.toJson()]));

  List<Batch>? loadBatches() {
    final raw = _get(_kBatches);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) Batch.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveVerifications(List<LabVerification> verifications) => _set(
    _kVerifications,
    jsonEncode([for (final v in verifications) v.toJson()]),
  );

  List<LabVerification>? loadVerifications() {
    final raw = _get(_kVerifications);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list) LabVerification.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> saveAlerts(List<HiveAlert> alerts) =>
      _set(_kAlerts, jsonEncode([for (final a in alerts) a.toJson()]));

  List<HiveAlert>? loadAlerts() {
    final raw = _get(_kAlerts);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list) HiveAlert.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> saveHealthChecks(List<HealthCheckEvent> events) =>
      _set(_kHealth, jsonEncode([for (final e in events) e.toJson()]));

  List<HealthCheckEvent>? loadHealthChecks() {
    final raw = _get(_kHealth);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list)
        HealthCheckEvent.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> saveBeeHealthEvents(List<BeeHealthEvent> events) =>
      _set(_kBeeHealthEvents, jsonEncode([for (final e in events) e.toJson()]));

  List<BeeHealthEvent>? loadBeeHealthEvents() {
    final raw = _get(_kBeeHealthEvents);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list) BeeHealthEvent.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> saveTreatments(List<TreatmentRecord> records) =>
      _set(_kTreatments, jsonEncode([for (final r in records) r.toJson()]));

  List<TreatmentRecord>? loadTreatments() {
    final raw = _get(_kTreatments);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list) TreatmentRecord.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> saveFollowUps(List<BeeHealthFollowUp> followUps) =>
      _set(_kFollowUps, jsonEncode([for (final f in followUps) f.toJson()]));

  List<BeeHealthFollowUp>? loadFollowUps() {
    final raw = _get(_kFollowUps);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [
      for (final e in list)
        BeeHealthFollowUp.fromJson(e as Map<String, dynamic>),
    ];
  }

  Future<void> saveCustody(List<CustodyEvent> events) =>
      _set(_kCustody, jsonEncode([for (final c in events) c.toJson()]));

  List<CustodyEvent>? loadCustody() {
    final raw = _get(_kCustody);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) CustodyEvent.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveAnchors(List<BlockchainAnchor> anchors) =>
      _set(_kAnchors, jsonEncode([for (final a in anchors) a.toJson()]));

  List<BlockchainAnchor>? loadAnchors() {
    final raw = _get(_kAnchors);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) BlockchainAnchor.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveProcessing(List<ProcessingEvent> events) =>
      _set(_kProcessing, jsonEncode([for (final p in events) p.toJson()]));

  List<ProcessingEvent>? loadProcessing() {
    final raw = _get(_kProcessing);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) ProcessingEvent.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveRelations(List<BatchRelation> relations) =>
      _set(_kRelations, jsonEncode([for (final r in relations) r.toJson()]));

  List<BatchRelation>? loadRelations() {
    final raw = _get(_kRelations);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) BatchRelation.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveProductBatches(List<ProductBatch> products) =>
      _set(_kProductBatches, jsonEncode([for (final p in products) p.toJson()]));

  List<ProductBatch>? loadProductBatches() {
    final raw = _get(_kProductBatches);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) ProductBatch.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> savePackagingBatches(List<PackagingBatch> batches) =>
      _set(_kPackagingBatches, jsonEncode([for (final b in batches) b.toJson()]));

  List<PackagingBatch>? loadPackagingBatches() {
    final raw = _get(_kPackagingBatches);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) PackagingBatch.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveJars(List<HoneyJar> jars) =>
      _set(_kJars, jsonEncode([for (final j in jars) j.toJson()]));

  List<HoneyJar>? loadJars() {
    final raw = _get(_kJars);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) HoneyJar.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveListings(List<MarketplaceListing> listings) =>
      _set(_kListings, jsonEncode([for (final l in listings) l.toJson()]));

  List<MarketplaceListing>? loadListings() {
    final raw = _get(_kListings);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) MarketplaceListing.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> saveRequests(List<PurchaseRequest> requests) =>
      _set(_kRequests, jsonEncode([for (final r in requests) r.toJson()]));

  List<PurchaseRequest>? loadRequests() {
    final raw = _get(_kRequests);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) PurchaseRequest.fromJson(e as Map<String, dynamic>)];
  }

  Future<void> savePassports(List<QRPassport> passports) =>
      _set(_kPassports, jsonEncode([for (final p in passports) p.toJson()]));

  List<QRPassport>? loadPassports() {
    final raw = _get(_kPassports);
    if (raw == null) return null;
    final list = jsonDecode(raw) as List;
    return [for (final e in list) QRPassport.fromJson(e as Map<String, dynamic>)];
  }

  /// Durable sync retry bookkeeping: per-record attempt counts and last error.
  Future<void> saveSyncAttempts(Map<String, int> attempts) =>
      _set(_kSyncAttempts, jsonEncode(attempts));

  Map<String, int> loadSyncAttempts() {
    final raw = _get(_kSyncAttempts);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {
      for (final e in decoded.entries) '${e.key}': (e.value as num).toInt(),
    };
  }

  Future<void> saveSyncErrors(Map<String, String> errors) =>
      _set(_kSyncErrors, jsonEncode(errors));

  Map<String, String> loadSyncErrors() {
    final raw = _get(_kSyncErrors);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {for (final e in decoded.entries) '${e.key}': '${e.value}'};
  }

  String? _get(String key) => _prefs?.getString(key);

  Future<void> _set(String key, String value) async {
    if (_prefs != null) {
      await _prefs!.setString(key, value);
    }
  }
}
