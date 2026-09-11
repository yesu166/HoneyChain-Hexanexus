import '../core/api/api_client.dart';
import 'api_token_store.dart';
import 'fastapi_auth_repository.dart';

/// Typed views of the FastAPI backend collections used by the beekeeper path.
///
/// These DTOs mirror the backend snake_case JSON contracts (see
/// `backend/app/schemas/{hive,harvest,batch,evidence}.py`) and deliberately do
/// NOT reuse the local Flutter domain models, whose fields are camelCase and
/// offline-first by design. Mapping to the local models happens in the store.
class ServerHive {
  const ServerHive({
    required this.id,
    required this.hiveCode,
    required this.beekeeperId,
    required this.orgId,
    required this.status,
    required this.clientId,
    this.location = '',
    this.createdAt,
  });

  final String id;
  final String hiveCode;
  final String beekeeperId;
  final String orgId;
  final String status;
  final String clientId;
  final String location;
  final DateTime? createdAt;

  factory ServerHive.fromJson(Map<String, dynamic> json) => ServerHive(
        id: _str(json['id']),
        hiveCode: _str(json['hive_code']),
        beekeeperId: _str(json['beekeeper_id']),
        orgId: _str(json['org_id']),
        status: _str(json['status']),
        clientId: _str(json['client_id']),
        location: _str(json['location']),
        createdAt: _date(json['created_at']),
      );
}

class ServerHarvest {
  const ServerHarvest({
    required this.id,
    required this.hiveId,
    required this.beekeeperId,
    required this.harvestedAt,
    required this.quantityKg,
    required this.honeyType,
    required this.clientId,
    required this.collected,
  });

  final String id;
  final String hiveId;
  final String beekeeperId;
  final DateTime harvestedAt;
  final double quantityKg;
  final String honeyType;
  final String clientId;
  final bool collected;

  factory ServerHarvest.fromJson(Map<String, dynamic> json) => ServerHarvest(
        id: _str(json['id']),
        hiveId: _str(json['hive_id']),
        beekeeperId: _str(json['beekeeper_id']),
        harvestedAt: _date(json['harvested_at']) ?? DateTime.now(),
        quantityKg: _num(json['quantity_kg']),
        honeyType: _str(json['honey_type']),
        clientId: _str(json['client_id']),
        collected: json['collected'] as bool? ?? false,
      );
}

class ServerBatch {
  const ServerBatch({
    required this.id,
    required this.batchCode,
    required this.status,
    required this.honeyType,
    required this.quantityKg,
    required this.origin,
    required this.organizationId,
    required this.trustTier,
    required this.clientId,
    this.createdAt,
  });

  final String id;
  final String batchCode;
  final String status;
  final String honeyType;
  final double quantityKg;
  final String origin;
  final String organizationId;
  final String trustTier;
  final String clientId;
  final DateTime? createdAt;

  factory ServerBatch.fromJson(Map<String, dynamic> json) => ServerBatch(
        id: _str(json['id']),
        batchCode: _str(json['batch_code']),
        status: _str(json['status']),
        honeyType: _str(json['honey_type']),
        quantityKg: _num(json['quantity_kg']),
        origin: _str(json['origin']),
        organizationId: _str(json['organization_id']),
        trustTier: _str(json['trust_tier']),
        clientId: _str(json['client_id']),
        createdAt: _date(json['created_at']),
      );
}

/// Evidence bundle as created by `POST /api/v1/evidence/bundles`. The [anchor]
/// map carries the live ledger commitment (tx_hash / state / network / ...)
/// whenever `anchor: true` resolved against the Fabric chain.
class ServerEvidenceBundle {
  const ServerEvidenceBundle({
    required this.bundleId,
    required this.entityType,
    required this.entityRef,
    required this.leafCount,
    required this.rootHash,
    required this.anchor,
    required this.evidence,
    this.operator = '',
    this.createdAt,
  });

  final String bundleId;
  final String entityType;
  final String entityRef;
  final String operator;
  final int leafCount;
  final String rootHash;
  final Map<String, dynamic> anchor;
  final List<Map<String, dynamic>> evidence;
  final DateTime? createdAt;

  bool get isAnchored => anchor['state'] == 'CONFIRMED';
  String get txHash => _str(anchor['tx_hash']);
  String get network => _str(anchor['network']);

  factory ServerEvidenceBundle.fromJson(Map<String, dynamic> json) =>
      ServerEvidenceBundle(
        bundleId: _str(json['bundle_id']),
        entityType: _str(json['entity_type']),
        entityRef: _str(json['entity_ref']),
        operator: _str(json['operator']),
        leafCount: json['leaf_count'] as int? ?? 0,
        rootHash: _str(json['root_hash']),
        anchor: (json['anchor'] as Map<String, dynamic>?) ?? const {},
        evidence: (json['evidence'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        createdAt: _date(json['created_at']),
      );
}

class ServerEvidenceVerify {
  const ServerEvidenceVerify({
    required this.bundleId,
    required this.evidenceIntact,
    required this.anchored,
    required this.evidenceCount,
    this.entityType,
    this.entityRef,
    this.rootHash,
    this.recomputedRoot,
    this.anchorState,
  });

  final String bundleId;
  final String? entityType;
  final String? entityRef;
  final String? rootHash;
  final String? recomputedRoot;
  final bool evidenceIntact;
  final dynamic anchorState;
  final bool anchored;
  final int evidenceCount;

  factory ServerEvidenceVerify.fromJson(Map<String, dynamic> json) =>
      ServerEvidenceVerify(
        bundleId: _str(json['bundle_id']),
        entityType: json['entity_type'] as String?,
        entityRef: json['entity_ref'] as String?,
        rootHash: json['root_hash'] as String?,
        recomputedRoot: json['recomputed_root'] as String?,
        evidenceIntact: json['evidence_intact'] as bool? ?? false,
        anchorState: json['anchor_state'],
        anchored: json['anchored'] as bool? ?? false,
        evidenceCount: json['evidence_count'] as int? ?? 0,
      );
}

/// Public `GET /api/v1/blockchain/health` payload (no auth required). For the
/// Fabric adapter it reflects a real health query against the live network.
class ServerBlockchainHealth {
  const ServerBlockchainHealth({
    required this.adapter,
    required this.status,
    this.network = '',
    this.channel = '',
    this.chaincode = '',
    this.chaincodeVersion,
    this.chaincodeSequence,
    this.peer = '',
    this.mspId = '',
    this.lastVerifiedAt,
    this.error,
  });

  final String adapter;
  final String status;
  final String network;
  final String channel;
  final String chaincode;
  final int? chaincodeVersion;
  final int? chaincodeSequence;
  final String peer;
  final String mspId;
  final String? lastVerifiedAt;
  final String? error;

  bool get isConnected =>
      status.toLowerCase() == 'connected' || status.toLowerCase() == 'live';

  factory ServerBlockchainHealth.fromJson(Map<String, dynamic> json) =>
      ServerBlockchainHealth(
        adapter: _str(json['adapter']),
        status: _str(json['status']),
        network: _str(json['network']),
        channel: _str(json['channel']),
        chaincode: _str(json['chaincode']),
        chaincodeVersion: _int(json['chaincode_version']),
        chaincodeSequence: _int(json['chaincode_sequence']),
        peer: _str(json['peer']),
        mspId: _str(json['msp_id']),
        lastVerifiedAt: json['last_verified_at'] as String?,
        error: json['error'] as String?,
      );
}

/// Authed `GET /api/v1/blockchain/status` payload: adapter + tracked
/// transactions + the live Fabric health block.
class ServerBlockchainStatus {
  const ServerBlockchainStatus({
    required this.adapter,
    required this.ledger,
    required this.tracker,
    required this.transactions,
    this.fabric,
  });

  final String adapter;
  final String ledger;

  /// `{ 'transactions': int, ... }` from the gateway tracker.
  final Map<String, dynamic> tracker;
  final List<Map<String, dynamic>> transactions;

  /// Live Fabric health (present for the real Fabric adapter).
  final Map<String, dynamic>? fabric;

  int get transactionCount => tracker['transactions'] as int? ?? transactions.length;

  factory ServerBlockchainStatus.fromJson(Map<String, dynamic> json) =>
      ServerBlockchainStatus(
        adapter: _str(json['adapter']),
        ledger: _str(json['ledger']),
        tracker: (json['tracker'] as Map<String, dynamic>?) ?? const {},
        transactions: (json['transactions'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(),
        fabric: json['fabric'] as Map<String, dynamic>?,
      );
}

/// Beekeeper-path operations against the verified FastAPI backend.
///
/// Backend layer is protected infrastructure — this service only READS/WRITES
/// through the existing verified API contracts; it never touches Fabric itself.
class HoneyApiService {
  HoneyApiService(this._client);

  final ApiClient _client;

  // ------------------------------------------------------------------- auth
  Future<ApiIdentity> login({
    required String identifier,
    required String password,
  }) =>
      FastApiAuthRepository(_client).login(
        identifier: identifier,
        password: password,
      );

  Future<void> signOut() => FastApiAuthRepository(_client).signOut();

  // ------------------------------------------------------------------ hives
  Future<List<ServerHive>> listHives() async {
    final rows = await _client.getListJson('/api/v1/hives');
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ServerHive.fromJson)
        .toList();
  }

  Future<ServerHive> createHive({
    required String hiveCode,
    String beekeeperId = '',
    String? location,
    String clientId = '',
  }) async {
    final body = await _client.postJson('/api/v1/hives', body: {
      'hive_code': hiveCode,
      'beekeeper_id': beekeeperId,
      'status': 'active',
      'client_id': clientId,
      if (location != null && location.trim().isNotEmpty) 'location': location,
    });
    return ServerHive.fromJson(body);
  }

  // ---------------------------------------------------------------- harvests
  Future<List<ServerHarvest>> listHarvests() async {
    final rows = await _client.getListJson('/api/v1/harvests');
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ServerHarvest.fromJson)
        .toList();
  }

  Future<ServerHarvest> createHarvest({
    required String hiveId,
    required double quantityKg,
    DateTime? harvestedAt,
    String honeyType = 'Not specified',
    String beekeeperId = '',
    String clientId = '',
  }) async {
    final body = await _client.postJson('/api/v1/harvests', body: {
      'hive_id': hiveId,
      'beekeeper_id': beekeeperId,
      'quantity_kg': quantityKg,
      'honey_type': honeyType,
      'client_id': clientId,
      if (harvestedAt != null) 'harvested_at': harvestedAt.toIso8601String(),
    });
    return ServerHarvest.fromJson(body);
  }

  // ----------------------------------------------------------------- batches
  Future<List<ServerBatch>> listBatches() async {
    final rows = await _client.getListJson('/api/v1/batches');
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ServerBatch.fromJson)
        .toList();
  }

  // -------------------------------------------------------- evidence (anchor)
  Future<ServerEvidenceBundle> createHarvestEvidenceBundle({
    required String entityRef,
    required String operator,
    required double quantityKg,
    required String honeyType,
    DateTime? harvestedAt,
    String deviceId = '',
    double? latitude,
    double? longitude,
    bool anchor = true,
    String clientId = '',
  }) async {
    final capturedAt =
        (harvestedAt ?? DateTime.now()).toIso8601String();
    return createEvidenceBundle(
      entityType: 'harvest',
      entityRef: entityRef,
      operator: operator,
      deviceId: deviceId,
      anchor: anchor,
      evidence: [
        {
          'kind': 'gps',
          'value': latitude != null && longitude != null
              ? '$latitude,$longitude'
              : 'gps-available',
          'captured_at': capturedAt,
          'latitude': latitude,
          'longitude': longitude,
          'content_hash': '',
        },
        {
          'kind': 'timestamp',
          'value': capturedAt,
          'captured_at': capturedAt,
          'content_hash': '',
        },
        {
          'kind': 'operator_note',
          'value':
              'Harvest $quantityKg kg of $honeyType recorded in HC mobile app',
          'captured_at': capturedAt,
          'content_hash': '',
        },
      ],
    );
  }

  Future<ServerEvidenceBundle> createEvidenceBundle({
    required String entityType,
    required String entityRef,
    required List<Map<String, dynamic>> evidence,
    String operator = '',
    String deviceId = '',
    bool anchor = true,
  }) async {
    final body = await _client.postJson('/api/v1/evidence/bundles', body: {
      'entity_type': entityType,
      'entity_ref': entityRef,
      'operator': operator,
      'device_id': deviceId,
      'anchor': anchor,
      'include_telemetry': false,
      'evidence': evidence,
    });
    return ServerEvidenceBundle.fromJson(body);
  }

  Future<ServerEvidenceVerify> verifyBundle(String bundleId) async {
    final body =
        await _client.postJson('/api/v1/evidence/bundles/$bundleId/verify');
    return ServerEvidenceVerify.fromJson(body);
  }

  // ----------------------------------------------------------- blockchain
  Future<ServerBlockchainHealth> blockchainHealth() async {
    final body = await _client.getJson('/api/v1/blockchain/health');
    return ServerBlockchainHealth.fromJson(body);
  }

  Future<ServerBlockchainStatus> blockchainStatus() async {
    final body = await _client.getJson('/api/v1/blockchain/status');
    return ServerBlockchainStatus.fromJson(body);
  }

  // -------------------------------------------------------------- custody
  Future<Map<String, dynamic>> addCustodyEvent({
    required String batchId,
    required String action,
    String notes = '',
    String? actor,
    DateTime? occurredAt,
  }) async {
    return _client.postJson(
      '/api/v1/batches/$batchId/custody-events',
      body: {
        'action': action,
        'notes': notes,
        if (actor != null && actor.isNotEmpty) 'actor': actor,
        if (occurredAt != null) 'occurred_at': occurredAt.toIso8601String(),
      },
    );
  }
}

String _str(Object? value) => value == null ? '' : '$value';

double _num(Object? value) {
  if (value is int) return value.toDouble();
  if (value is double) return value;
  return double.tryParse('$value') ?? 0;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}