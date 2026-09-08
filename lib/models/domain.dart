enum UserRole { beekeeper, fpo, lab, processor, admin, buyer, consumer }

enum OrganizationType { institution, cluster, fpo, lab, processor }

enum RiskLevel { healthy, attentionRequired, highRisk }

enum BatchStatus {
  created,
  collected,
  labPending,
  labVerified,
  labFailed,
  processing,
  listed,
  completed,
}

enum VerificationStatus { pending, pass, fail, needsFurtherTesting }

/// How much of a batch's history has been independently verified.
///
/// A beekeeper's own records are [selfDeclared]; custody events, laboratory
/// testing and integrity anchors raise the tier. The tier is a statement of
/// *which proof exists*, never a certificate of purity or quality.
enum TrustTier {
  selfDeclared,
  organizationVerified,
  labVerified,
  blockchainAnchored,
}

extension TrustTierX on TrustTier {
  /// Higher rank = more independent proof. Used to enforce weakest-link
  /// merges and split inheritance.
  int get rank => index + 1;

  String get label => switch (this) {
        TrustTier.selfDeclared => 'Beekeeper reported',
        TrustTier.organizationVerified => 'Organization verified',
        TrustTier.labVerified => 'Lab verified',
        TrustTier.blockchainAnchored => 'Integrity anchored',
      };

  String get who => switch (this) {
        TrustTier.selfDeclared => 'Beekeeper',
        TrustTier.organizationVerified => 'Organization / FPO',
        TrustTier.labVerified => 'Independent laboratory',
        TrustTier.blockchainAnchored => 'Integrity layer',
      };
}

enum RelationType { aggregate, split }

/// Whether a locally created record was synchronized to the backend.
enum SyncStatus { synced, pending, failed }

/// Parses a persisted [SyncStatus] name, falling back to [SyncStatus.synced].
SyncStatus parseSyncStatus(String? name) => switch (name) {
      'pending' => SyncStatus.pending,
      'failed' => SyncStatus.failed,
      _ => SyncStatus.synced,
    };

/// Optional display state of a honey batch from the beekeeper's perspective.
/// Kept as a plain string so it can be extended without enum migration.
enum BatchDisplayStatus { pending, inLab, verified, failed }

/// Lifecycle of a harvest from the beekeeper's perspective.
/// A harvest starts [pending] and becomes [collected] once the organization /
/// FPO takes possession for batch creation.
enum HarvestStatus { pending, collected }

/// Pack size for a packaged product batch (from a consolidated parent batch).
enum ProductSize { size100g, size250g, size500ml, size1kg }

extension ProductSizeX on ProductSize {
  String get label => switch (this) {
        ProductSize.size100g => '100 g',
        ProductSize.size250g => '250 g',
        ProductSize.size500ml => '500 g',
        ProductSize.size1kg => '1 kg',
      };

  int get grams => switch (this) {
        ProductSize.size100g => 100,
        ProductSize.size250g => 250,
        ProductSize.size500ml => 500,
        ProductSize.size1kg => 1000,
      };

  static ProductSize fromGrams(int grams) => switch (grams) {
        100 => ProductSize.size100g,
        250 => ProductSize.size250g,
        500 => ProductSize.size500ml,
        1000 => ProductSize.size1kg,
        _ => ProductSize.size500ml,
      };
}

enum AlertType {
  temperature,
  humidity,
  harvest,
  codeCreate,
  verification,
  disease,
  iot,
}

enum AlertSeverity { info, care, urgent }

class BeekeeperProfile {
  const BeekeeperProfile({
    required this.name,
    required this.memberId,
    required this.organizationName,
    required this.location,
    this.phone,
  });
  final String name;
  final String memberId;
  final String organizationName;
  final String location;
  final String? phone;

  BeekeeperProfile copyWith({String? name, String? memberId, String? organizationName, String? location, String? phone}) =>
      BeekeeperProfile(
        name: name ?? this.name,
        memberId: memberId ?? this.memberId,
        organizationName: organizationName ?? this.organizationName,
        location: location ?? this.location,
        phone: phone ?? this.phone,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'memberId': memberId,
        'organizationName': organizationName,
        'location': location,
        'phone': phone,
      };

  factory BeekeeperProfile.fromJson(Map<String, dynamic> json) => BeekeeperProfile(
        name: json['name'] as String? ?? '',
        memberId: json['memberId'] as String? ?? '',
        organizationName: json['organizationName'] as String? ?? '',
        location: json['location'] as String? ?? '',
        phone: json['phone'] as String?,
      );
}

class HiveAlert {
  const HiveAlert({
    required this.id,
    required this.type,
    required this.severity,
    this.hiveId,
    this.batchId,
    this.batchLabel,
    required this.createdAt,
    this.isRead = false,
  });
  final String id;
  final AlertType type;
  final AlertSeverity severity;
  final String? hiveId;

  /// Human label of the related batch (e.g. "Batch #24").
  final String? batchLabel;
  final String? batchId;
  final DateTime createdAt;
  final bool isRead;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'severity': severity.name,
        'hiveId': hiveId,
        'batchId': batchId,
        'batchLabel': batchLabel,
        'createdAt': createdAt.toIso8601String(),
        'isRead': isRead,
      };

  factory HiveAlert.fromJson(Map<String, dynamic> json) => HiveAlert(
        id: json['id'] as String? ?? '',
        type: AlertType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => AlertType.temperature,
        ),
        severity: AlertSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => AlertSeverity.care,
        ),
        hiveId: json['hiveId'] as String?,
        batchId: json['batchId'] as String?,
        batchLabel: json['batchLabel'] as String?,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        isRead: json['isRead'] as bool? ?? false,
      );
}

class User {
  const User({required this.id, required this.name, required this.role, required this.organizationId});
  final String id;
  final String name;
  final UserRole role;
  final String organizationId;
}

class Organization {
  const Organization({required this.id, required this.name, required this.type, required this.clusterId});
  final String id;
  final String name;
  final OrganizationType type;
  final String clusterId;
}

class Cluster {
  const Cluster({required this.id, required this.name, required this.state});
  final String id;
  final String name;
  final String state;
}

class Hive {
  const Hive({
    required this.id,
    required this.name,
    required this.beekeeperId,
    required this.organizationId,
    required this.location,
    required this.honeyType,
    this.detail = '',
    this.photoCredit = '',
  });
  final String id;
  final String name;
  final String beekeeperId;
  final String organizationId;
  final String location;
  final String honeyType;

  /// Friendly farm/place name shown next to the hive number (e.g. Mango Orchard).
  final String detail;

  /// Optional caption for the hive photo area.
  final String photoCredit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'beekeeperId': beekeeperId,
        'organizationId': organizationId,
        'location': location,
        'honeyType': honeyType,
        'detail': detail,
        'photoCredit': photoCredit,
      };

  factory Hive.fromJson(Map<String, dynamic> json) => Hive(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        beekeeperId: json['beekeeperId'] as String? ?? '',
        organizationId: json['organizationId'] as String? ?? '',
        location: json['location'] as String? ?? '',
        honeyType: json['honeyType'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        photoCredit: json['photoCredit'] as String? ?? '',
      );
}

class HiveReading {
  const HiveReading({required this.id, required this.hiveId, required this.recordedAt, required this.temperatureC, required this.humidityPercent, required this.weightKg});
  final String id;
  final String hiveId;
  final DateTime recordedAt;
  final double temperatureC;
  final double humidityPercent;
  final double weightKg;
}

enum ReadingStatus { healthy, high, low }

enum WeightStatus { growing, steady, dropping }

class HiveInsight {
  const HiveInsight({
    required this.hiveId,
    required this.healthScore,
    required this.riskLevel,
    required this.riskExplanation,
    required this.productivityInsight,
    required this.inspectionRecommendation,
    this.tempStatus = ReadingStatus.healthy,
    this.humidityStatus = ReadingStatus.healthy,
    this.weightStatus = WeightStatus.steady,
    this.adviceCode = 'inspect',
  });
  final String hiveId;
  final int healthScore;
  final RiskLevel riskLevel;
  final String riskExplanation;
  final String productivityInsight;
  final String inspectionRecommendation;

  /// Simple, non-technical reading statuses for the beekeeper.
  final ReadingStatus tempStatus;
  final ReadingStatus humidityStatus;
  final WeightStatus weightStatus;

  /// One of: inspect | ventilation | cool.
  final String adviceCode;

  HiveInsight copyWith({
    int? healthScore,
    RiskLevel? riskLevel,
    String? riskExplanation,
    String? productivityInsight,
    String? inspectionRecommendation,
    ReadingStatus? tempStatus,
    ReadingStatus? humidityStatus,
    WeightStatus? weightStatus,
    String? adviceCode,
  }) =>
      HiveInsight(
        hiveId: hiveId,
        healthScore: healthScore ?? this.healthScore,
        riskLevel: riskLevel ?? this.riskLevel,
        riskExplanation: riskExplanation ?? this.riskExplanation,
        productivityInsight: productivityInsight ?? this.productivityInsight,
        inspectionRecommendation:
            inspectionRecommendation ?? this.inspectionRecommendation,
        tempStatus: tempStatus ?? this.tempStatus,
        humidityStatus: humidityStatus ?? this.humidityStatus,
        weightStatus: weightStatus ?? this.weightStatus,
        adviceCode: adviceCode ?? this.adviceCode,
      );
}

class Harvest {
  const Harvest({
    required this.id,
    required this.hiveId,
    required this.beekeeperId,
    required this.harvestedAt,
    required this.honeyType,
    required this.quantityKg,
    this.syncStatus = SyncStatus.synced,
    this.status = HarvestStatus.pending,
  });
  final String id;
  final String hiveId;
  final String beekeeperId;
  final DateTime harvestedAt;
  final String honeyType;
  final double quantityKg;
  final SyncStatus syncStatus;

  /// Whether the organization / FPO has collected this harvest into a batch.
  final HarvestStatus status;

  bool get collected => status == HarvestStatus.collected;
  int get quantityGrams => (quantityKg * 1000).round();

  Harvest copyWith({
    SyncStatus? syncStatus,
    HarvestStatus? status,
  }) => Harvest(
        id: id,
        hiveId: hiveId,
        beekeeperId: beekeeperId,
        harvestedAt: harvestedAt,
        honeyType: honeyType,
        quantityKg: quantityKg,
        syncStatus: syncStatus ?? this.syncStatus,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hiveId': hiveId,
        'beekeeperId': beekeeperId,
        'harvestedAt': harvestedAt.toIso8601String(),
        'honeyType': honeyType,
        'quantityKg': quantityKg,
        'syncStatus': syncStatus.name,
        'status': status.name,
      };

  factory Harvest.fromJson(Map<String, dynamic> json) => Harvest(
        id: json['id'] as String? ?? '',
        hiveId: json['hiveId'] as String? ?? '',
        beekeeperId: json['beekeeperId'] as String? ?? '',
        harvestedAt:
            DateTime.tryParse(json['harvestedAt'] as String? ?? '') ??
            DateTime.now(),
        honeyType: json['honeyType'] as String? ?? '',
        quantityKg: (json['quantityKg'] as num? ?? 0).toDouble(),
        syncStatus: parseSyncStatus(json['syncStatus'] as String?),
        status: json['status'] == 'collected'
            ? HarvestStatus.collected
            : HarvestStatus.pending,
      );
}

class Batch {
  const Batch({
    required this.id,
    required this.code,
    required this.organizationId,
    required this.honeyType,
    required this.origin,
    required this.quantityKg,
    required this.createdAt,
    required this.status,
    this.syncStatus = SyncStatus.synced,
    this.displayStatus,
  });
  final String id;
  final String code;
  final String organizationId;
  final String honeyType;
  final String origin;
  final double quantityKg;
  final DateTime createdAt;
  final BatchStatus status;
  final SyncStatus syncStatus;

  /// Beekeeper-facing state: pending / inLab / verified / failed.
  final BatchDisplayStatus? displayStatus;

  int get quantityGrams => (quantityKg * 1000).round();

  Batch copyWith({
    BatchStatus? status,
    double? quantityKg,
    SyncStatus? syncStatus,
    BatchDisplayStatus? displayStatus,
    String? origin,
    String? honeyType,
  }) => Batch(
    id: id,
    code: code,
    organizationId: organizationId,
    honeyType: honeyType ?? this.honeyType,
    origin: origin ?? this.origin,
    quantityKg: quantityKg ?? this.quantityKg,
    createdAt: createdAt,
    status: status ?? this.status,
    syncStatus: syncStatus ?? this.syncStatus,
    displayStatus: displayStatus ?? this.displayStatus,
  );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'organizationId': organizationId,
        'honeyType': honeyType,
        'origin': origin,
        'quantityKg': quantityKg,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'syncStatus': syncStatus.name,
        'displayStatus': displayStatus?.name,
      };

  factory Batch.fromJson(Map<String, dynamic> json) => Batch(
        id: json['id'] as String? ?? '',
        code: json['code'] as String? ?? '',
        organizationId: json['organizationId'] as String? ?? '',
        honeyType: json['honeyType'] as String? ?? '',
        origin: json['origin'] as String? ?? '',
        quantityKg: (json['quantityKg'] as num? ?? 0).toDouble(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        status: BatchStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => BatchStatus.created,
        ),
        syncStatus: parseSyncStatus(json['syncStatus'] as String?),
        displayStatus: json['displayStatus'] == null
            ? null
            : BatchDisplayStatus.values.firstWhere(
                (d) => d.name == json['displayStatus'],
                orElse: () => BatchDisplayStatus.pending,
              ),
      );
}

class BatchHarvest {
  const BatchHarvest({required this.batchId, required this.harvestId, required this.quantityKg});
  final String batchId;
  final String harvestId;
  final double quantityKg;
}

class BatchRelation {
  const BatchRelation({
    required this.id,
    required this.parentBatchId,
    required this.childBatchId,
    required this.type,
    required this.createdAt,
  });
  final String id;
  final String parentBatchId;
  final String childBatchId;
  final RelationType type;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'parentBatchId': parentBatchId,
    'childBatchId': childBatchId,
    'type': type.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory BatchRelation.fromJson(Map<String, dynamic> json) => BatchRelation(
    id: json['id'] as String? ?? '',
    parentBatchId: json['parentBatchId'] as String? ?? '',
    childBatchId: json['childBatchId'] as String? ?? '',
    type: RelationType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => RelationType.split,
    ),
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

/// Processing record produced from a consolidated batch.
/// Created by the organization / FPO when the parent batch moves to the
/// processing unit. Reused as an event record for the future Fabric layer.
class ProcessingEvent {
  const ProcessingEvent({
    required this.id,
    required this.batchId,
    required this.unit,
    required this.date,
    required this.status,
  });
  final String id;
  final String batchId;
  final String unit;
  final DateTime date;
  final String status; // PENDING | COMPLETED

  Map<String, dynamic> toJson() => {
    'id': id,
    'batchId': batchId,
    'unit': unit,
    'date': date.toIso8601String(),
    'status': status,
  };

  factory ProcessingEvent.fromJson(Map<String, dynamic> json) =>
      ProcessingEvent(
        id: json['id'] as String? ?? '',
        batchId: json['batchId'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        status: json['status'] as String? ?? 'PENDING',
      );
}

/// A packaged product created from a parent batch (e.g. HC-TN-00128-A, 500ml).
/// One consumer QR is generated per product batch.
class ProductBatch {
  const ProductBatch({
    required this.id,
    required this.productCode,
    required this.parentBatchId,
    required this.size,
    required this.createdAt,
    this.packagingStatus = PackagingStatus.packaged,
  });
  final String id;
  final String productCode;
  final String parentBatchId;
  final ProductSize size;
  final DateTime createdAt;
  final PackagingStatus packagingStatus;

  Map<String, dynamic> toJson() => {
    'id': id,
    'productCode': productCode,
    'parentBatchId': parentBatchId,
    'size': size.name,
    'createdAt': createdAt.toIso8601String(),
    'packagingStatus': packagingStatus.name,
  };

  factory ProductBatch.fromJson(Map<String, dynamic> json) => ProductBatch(
    id: json['id'] as String? ?? '',
    productCode: json['productCode'] as String? ?? '',
    parentBatchId: json['parentBatchId'] as String? ?? '',
    size: switch (json['size']) {
      'size100g' => ProductSize.size100g,
      'size250g' => ProductSize.size250g,
      'size1kg' => ProductSize.size1kg,
      _ => ProductSize.size500ml,
    },
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.now(),
    packagingStatus: PackagingStatus.values.firstWhere(
      (s) => s.name == json['packagingStatus'],
      orElse: () => PackagingStatus.packaged,
    ),
  );
}

enum PackagingStatus { packaged }

/// Snapshot of what is (and is not) proven about a batch.
class TrustState {
  const TrustState({
    required this.tier,
    required this.claims,
    this.caveats = const [],
    this.passCount = 0,
    this.failCount = 0,
    this.custodyCount = 0,
    this.anchorCount = 0,
    this.isPrototypeAnchor = false,
  });

  final TrustTier tier;

  /// Positive statements backed by actual records in the store.
  final List<String> claims;

  /// Honest limits of the current evidence ("does NOT prove ...").
  final List<String> caveats;

  final int passCount;
  final int failCount;
  final int custodyCount;
  final int anchorCount;

  /// True when the only anchor present sits on prototype (mock)
  /// infrastructure, so consumers must be told anchoring is not live.
  final bool isPrototypeAnchor;
}

/// Stages of a batch's recorded journey, rendered from persisted audit /
/// custody / lab / anchor / relation records (never fabricated).
enum BatchEventType {
  registered,
  collected,
  labPass,
  labFail,
  processing,
  anchored,
  corrected,
  splitFrom,
  aggregatedFrom,
  packaged,
}

class BatchEvent {
  const BatchEvent({
    required this.type,
    required this.label,
    required this.actor,
    required this.at,
    required this.description,
    this.relatedBatchCode,
  });
  final BatchEventType type;
  final String label;
  final String actor;
  final DateTime at;
  final String description;
  final String? relatedBatchCode;
}

class EvidenceFile {
  const EvidenceFile({required this.id, required this.name, required this.mimeType, required this.uploadedAt});
  final String id;
  final String name;
  final String mimeType;
  final DateTime uploadedAt;
}

class LabVerification {
  const LabVerification({required this.id, required this.batchId, required this.labOrganizationId, required this.status, required this.testedAt, required this.summary, this.evidence = const []});
  final String id;
  final String batchId;
  final String labOrganizationId;
  final VerificationStatus status;
  final DateTime testedAt;
  final String summary;
  final List<EvidenceFile> evidence;

  Map<String, dynamic> toJson() => {
        'id': id,
        'batchId': batchId,
        'labOrganizationId': labOrganizationId,
        'status': status.name,
        'testedAt': testedAt.toIso8601String(),
        'summary': summary,
        'evidence': [
          for (final e in evidence) {'name': e.name},
        ],
      };

  factory LabVerification.fromJson(Map<String, dynamic> json) => LabVerification(
        id: json['id'] as String? ?? '',
        batchId: json['batchId'] as String? ?? '',
        labOrganizationId: json['labOrganizationId'] as String? ?? '',
        status: VerificationStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => VerificationStatus.pending,
        ),
        testedAt: DateTime.tryParse(json['testedAt'] as String? ?? '') ?? DateTime.now(),
        summary: json['summary'] as String? ?? '',
        evidence: [
          for (final e in (json['evidence'] as List? ?? []))
            if (e is Map && e['name'] != null)
              EvidenceFile(id: e['name'] as String, name: e['name'] as String, mimeType: 'application/pdf', uploadedAt: DateTime.now()),
        ],
      );
}

class CustodyEvent {
  const CustodyEvent({
    required this.id,
    required this.batchId,
    required this.fromOrganizationId,
    required this.toOrganizationId,
    required this.recordedAt,
    required this.note,
  });
  final String id;
  final String batchId;
  final String fromOrganizationId;
  final String toOrganizationId;
  final DateTime recordedAt;
  final String note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'batchId': batchId,
    'fromOrganizationId': fromOrganizationId,
    'toOrganizationId': toOrganizationId,
    'recordedAt': recordedAt.toIso8601String(),
    'note': note,
  };

  factory CustodyEvent.fromJson(Map<String, dynamic> json) => CustodyEvent(
    id: json['id'] as String? ?? '',
    batchId: json['batchId'] as String? ?? '',
    fromOrganizationId: json['fromOrganizationId'] as String? ?? '',
    toOrganizationId: json['toOrganizationId'] as String? ?? '',
    recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? '') ?? DateTime.now(),
    note: json['note'] as String? ?? '',
  );
}

class BlockchainAnchor {
  const BlockchainAnchor({
    required this.id,
    required this.batchId,
    required this.eventType,
    required this.anchorId,
    required this.anchoredAt,
    required this.isMock,
    this.packagingBatchId,
    this.details = const {},
  });
  final String id;
  final String batchId;
  final String eventType;
  final String anchorId;
  final DateTime anchoredAt;
  final bool isMock;
  final String? packagingBatchId;
  final Map<String, dynamic> details;

  Map<String, dynamic> toJson() => {
    'id': id,
    'batchId': batchId,
    'eventType': eventType,
    'anchorId': anchorId,
    'anchoredAt': anchoredAt.toIso8601String(),
    'isMock': isMock,
    'packagingBatchId': packagingBatchId,
    'details': details,
  };

  factory BlockchainAnchor.fromJson(Map<String, dynamic> json) => BlockchainAnchor(
    id: json['id'] as String? ?? '',
    batchId: json['batchId'] as String? ?? '',
    eventType: json['eventType'] as String? ?? '',
    anchorId: json['anchorId'] as String? ?? '',
    anchoredAt: DateTime.tryParse(json['anchoredAt'] as String? ?? '') ?? DateTime.now(),
    isMock: json['isMock'] as bool? ?? true,
    packagingBatchId: json['packagingBatchId'] as String?,
    details: (json['details'] as Map<String, dynamic>?) ?? const {},
  );
}

class MarketplaceListing {
  const MarketplaceListing({
    required this.id,
    required this.batchId,
    required this.quantityKg,
    required this.pricePerKg,
    required this.isActive,
    this.remainingQuantityKg,
  });
  final String id;
  final String batchId;
  final double quantityKg;
  final double pricePerKg;
  final bool isActive;
  final double? remainingQuantityKg;

  double get effectiveRemainingKg => remainingQuantityKg ?? quantityKg;
  int get remainingQuantityGrams => (effectiveRemainingKg * 1000).round();

  MarketplaceListing copyWith({
    double? quantityKg,
    double? pricePerKg,
    bool? isActive,
    double? remainingQuantityKg,
  }) => MarketplaceListing(
    id: id,
    batchId: batchId,
    quantityKg: quantityKg ?? this.quantityKg,
    pricePerKg: pricePerKg ?? this.pricePerKg,
    isActive: isActive ?? this.isActive,
    remainingQuantityKg: remainingQuantityKg ?? this.remainingQuantityKg,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'batchId': batchId,
    'quantityKg': quantityKg,
    'pricePerKg': pricePerKg,
    'isActive': isActive,
    'remainingQuantityKg': remainingQuantityKg,
  };

  factory MarketplaceListing.fromJson(Map<String, dynamic> json) => MarketplaceListing(
    id: json['id'] as String? ?? '',
    batchId: json['batchId'] as String? ?? '',
    quantityKg: (json['quantityKg'] as num? ?? 0).toDouble(),
    pricePerKg: (json['pricePerKg'] as num? ?? 0).toDouble(),
    isActive: json['isActive'] as bool? ?? true,
    remainingQuantityKg: (json['remainingQuantityKg'] as num?)?.toDouble(),
  );
}

class PurchaseRequest {
  const PurchaseRequest({required this.id, required this.listingId, required this.buyerName, required this.quantityKg, required this.message, required this.createdAt});
  final String id;
  final String listingId;
  final String buyerName;
  final double quantityKg;
  final String message;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'listingId': listingId,
    'buyerName': buyerName,
    'quantityKg': quantityKg,
    'message': message,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PurchaseRequest.fromJson(Map<String, dynamic> json) => PurchaseRequest(
    id: json['id'] as String? ?? '',
    listingId: json['listingId'] as String? ?? '',
    buyerName: json['buyerName'] as String? ?? '',
    quantityKg: (json['quantityKg'] as num? ?? 0).toDouble(),
    message: json['message'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class QRPassport {
  const QRPassport({required this.slug, required this.batchId, required this.createdAt});
  final String slug;
  final String batchId;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'slug': slug,
    'batchId': batchId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory QRPassport.fromJson(Map<String, dynamic> json) => QRPassport(
    slug: json['slug'] as String? ?? '',
    batchId: json['batchId'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class AuditEvent {
  const AuditEvent({required this.id, required this.batchId, required this.type, required this.actor, required this.recordedAt, required this.description});
  final String id;
  final String batchId;
  final String type;
  final String actor;
  final DateTime recordedAt;
  final String description;

  Map<String, dynamic> toJson() => {
    'id': id,
    'batchId': batchId,
    'type': type,
    'actor': actor,
    'recordedAt': recordedAt.toIso8601String(),
    'description': description,
  };

  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
    id: json['id'] as String? ?? '',
    batchId: json['batchId'] as String? ?? '',
    type: json['type'] as String? ?? '',
    actor: json['actor'] as String? ?? '',
    recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? '') ?? DateTime.now(),
    description: json['description'] as String? ?? '',
  );
}

class PackagingBatch {
  const PackagingBatch({
    required this.packagingBatchId,
    required this.sourceBatchId,
    required this.buyerId,
    required this.quantityUsedGrams,
    required this.jarSizeGrams,
    required this.jarCount,
    required this.packagingDate,
    required this.status,
    this.blockchainAnchorId,
  });

  final String packagingBatchId;
  final String sourceBatchId;
  final String buyerId;
  final int quantityUsedGrams;
  final int jarSizeGrams;
  final int jarCount;
  final DateTime packagingDate;
  final String status; // 'CREATED' | 'ANCHORED'
  final String? blockchainAnchorId;

  PackagingBatch copyWith({
    String? status,
    String? blockchainAnchorId,
  }) => PackagingBatch(
    packagingBatchId: packagingBatchId,
    sourceBatchId: sourceBatchId,
    buyerId: buyerId,
    quantityUsedGrams: quantityUsedGrams,
    jarSizeGrams: jarSizeGrams,
    jarCount: jarCount,
    packagingDate: packagingDate,
    status: status ?? this.status,
    blockchainAnchorId: blockchainAnchorId ?? this.blockchainAnchorId,
  );

  Map<String, dynamic> toJson() => {
    'packagingBatchId': packagingBatchId,
    'sourceBatchId': sourceBatchId,
    'buyerId': buyerId,
    'quantityUsedGrams': quantityUsedGrams,
    'jarSizeGrams': jarSizeGrams,
    'jarCount': jarCount,
    'packagingDate': packagingDate.toIso8601String(),
    'status': status,
    'blockchainAnchorId': blockchainAnchorId,
  };

  factory PackagingBatch.fromJson(Map<String, dynamic> json) => PackagingBatch(
    packagingBatchId: json['packagingBatchId'] as String? ?? '',
    sourceBatchId: json['sourceBatchId'] as String? ?? '',
    buyerId: json['buyerId'] as String? ?? '',
    quantityUsedGrams: (json['quantityUsedGrams'] as num? ?? 0).toInt(),
    jarSizeGrams: (json['jarSizeGrams'] as num? ?? 500).toInt(),
    jarCount: (json['jarCount'] as num? ?? 0).toInt(),
    packagingDate: DateTime.tryParse(json['packagingDate'] as String? ?? '') ?? DateTime.now(),
    status: json['status'] as String? ?? 'CREATED',
    blockchainAnchorId: json['blockchainAnchorId'] as String?,
  );
}

class HoneyJar {
  const HoneyJar({
    required this.jarId,
    required this.packagingBatchId,
    required this.sourceBatchId,
    required this.harvestIds,
    required this.hiveIds,
    required this.beekeeperId,
    required this.beekeeperName,
    required this.organizationId,
    required this.buyerId,
    required this.quantityGrams,
    required this.packageSize,
    required this.createdAt,
    required this.qrPayload,
    this.blockchainAnchorId,
  });

  final String jarId; // e.g. JAR-HC-000001
  final String packagingBatchId;
  final String sourceBatchId;
  final List<String> harvestIds;
  final List<String> hiveIds;
  final String beekeeperId;
  final String beekeeperName;
  final String organizationId;
  final String buyerId;
  final int quantityGrams;
  final String packageSize;
  final DateTime createdAt;
  final String qrPayload; // e.g. honeychain://jar/JAR-HC-000001
  final String? blockchainAnchorId;

  HoneyJar copyWith({
    String? blockchainAnchorId,
  }) => HoneyJar(
    jarId: jarId,
    packagingBatchId: packagingBatchId,
    sourceBatchId: sourceBatchId,
    harvestIds: harvestIds,
    hiveIds: hiveIds,
    beekeeperId: beekeeperId,
    beekeeperName: beekeeperName,
    organizationId: organizationId,
    buyerId: buyerId,
    quantityGrams: quantityGrams,
    packageSize: packageSize,
    createdAt: createdAt,
    qrPayload: qrPayload,
    blockchainAnchorId: blockchainAnchorId ?? this.blockchainAnchorId,
  );

  Map<String, dynamic> toJson() => {
    'jarId': jarId,
    'packagingBatchId': packagingBatchId,
    'sourceBatchId': sourceBatchId,
    'harvestIds': harvestIds,
    'hiveIds': hiveIds,
    'beekeeperId': beekeeperId,
    'beekeeperName': beekeeperName,
    'organizationId': organizationId,
    'buyerId': buyerId,
    'quantityGrams': quantityGrams,
    'packageSize': packageSize,
    'createdAt': createdAt.toIso8601String(),
    'qrPayload': qrPayload,
    'blockchainAnchorId': blockchainAnchorId,
  };

  factory HoneyJar.fromJson(Map<String, dynamic> json) => HoneyJar(
    jarId: json['jarId'] as String? ?? '',
    packagingBatchId: json['packagingBatchId'] as String? ?? '',
    sourceBatchId: json['sourceBatchId'] as String? ?? '',
    harvestIds: (json['harvestIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    hiveIds: (json['hiveIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    beekeeperId: json['beekeeperId'] as String? ?? '',
    beekeeperName: json['beekeeperName'] as String? ?? '',
    organizationId: json['organizationId'] as String? ?? '',
    buyerId: json['buyerId'] as String? ?? '',
    quantityGrams: (json['quantityGrams'] as num? ?? 500).toInt(),
    packageSize: json['packageSize'] as String? ?? '500g',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    qrPayload: json['qrPayload'] as String? ?? '',
    blockchainAnchorId: json['blockchainAnchorId'] as String?,
  );
}
