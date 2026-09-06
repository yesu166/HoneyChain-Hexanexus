class HoneyEvent {
  final String type;
  final String actor;
  final String timestamp;
  final String status;
  final String description;

  const HoneyEvent({
    required this.type,
    required this.actor,
    required this.timestamp,
    required this.status,
    required this.description,
  });
}

class HoneyBatch {
  final String id;
  final String beekeeper;
  final String origin;
  final String honeyType;
  final String harvestDate;
  final double quantity;

  final String custodyStatus;
  final String labStatus;
  final String authenticityStatus;
  final String blockchainStatus;

  final Map<String, String> labResults;
  final String blockchainHash;
  final List<HoneyEvent> events;

  const HoneyBatch({
    required this.id,
    required this.beekeeper,
    required this.origin,
    required this.honeyType,
    required this.harvestDate,
    required this.quantity,
    this.custodyStatus = 'pending',
    this.labStatus = 'pending',
    this.authenticityStatus = 'pending',
    this.blockchainStatus = 'pending',
    this.labResults = const {},
    this.blockchainHash = '',
    this.events = const [],
  });

  bool get custodyAccepted => custodyStatus == 'accepted';
  bool get labVerified => labStatus == 'verified';
  bool get authenticityVerified => authenticityStatus == 'verified';
  bool get integrityAnchored => blockchainStatus == 'anchored';

  /// Concise overall lifecycle status label (used by legacy role screens).
  String get status {
    if (integrityAnchored) return 'Anchored';
    if (labVerified && authenticityVerified) return 'Verified';
    if (custodyAccepted) return 'In Transit';
    return 'Registered';
  }
  bool get fullyVerified =>
      custodyAccepted &&
      labVerified &&
      authenticityVerified &&
      integrityAnchored;

  HoneyBatch copyWith({
    String? id,
    String? beekeeper,
    String? origin,
    String? honeyType,
    String? harvestDate,
    double? quantity,
    String? custodyStatus,
    String? labStatus,
    String? authenticityStatus,
    String? blockchainStatus,
    Map<String, String>? labResults,
    String? blockchainHash,
    List<HoneyEvent>? events,
  }) {
    return HoneyBatch(
      id: id ?? this.id,
      beekeeper: beekeeper ?? this.beekeeper,
      origin: origin ?? this.origin,
      honeyType: honeyType ?? this.honeyType,
      harvestDate: harvestDate ?? this.harvestDate,
      quantity: quantity ?? this.quantity,
      custodyStatus: custodyStatus ?? this.custodyStatus,
      labStatus: labStatus ?? this.labStatus,
      authenticityStatus: authenticityStatus ?? this.authenticityStatus,
      blockchainStatus: blockchainStatus ?? this.blockchainStatus,
      labResults: labResults ?? this.labResults,
      blockchainHash: blockchainHash ?? this.blockchainHash,
      events: events ?? this.events,
    );
  }
}
