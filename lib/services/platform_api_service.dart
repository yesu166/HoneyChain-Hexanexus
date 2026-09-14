import '../core/api/api_client.dart';

/// Typed views of the FastAPI platform-oversight endpoints
/// (`/api/v1/platform/...` and `/api/v1/platform/stats`).
///
/// These DTOs mirror the backend snake_case JSON contracts (see
/// `backend/app/schemas/org.py`) and are NOT the local Flutter domain models.
/// The backend remains authoritative for organization lifecycle, membership and
/// audit data — this service only reads/writes through the verified contracts.

// --------------------------------------------------------------------------
// Models
// --------------------------------------------------------------------------

class PlatformOrganization {
  const PlatformOrganization({
    required this.id,
    required this.organizationKey,
    required this.name,
    required this.type,
    required this.status,
    this.country = '',
    this.state = '',
    this.district = '',
    this.address = '',
    this.postalCode = '',
    this.contactEmail = '',
    this.contactPhone = '',
    this.registrationNo = '',
    this.location = '',
    this.clientId = '',
  });

  final String id;
  final String organizationKey;
  final String name;
  final String type;
  final String status;
  final String country;
  final String state;
  final String district;
  final String address;
  final String postalCode;
  final String contactEmail;
  final String contactPhone;
  final String registrationNo;
  final String location;
  final String clientId;

  bool get isActive => status == 'ACTIVE';

  factory PlatformOrganization.fromJson(Map<String, dynamic> json) =>
      PlatformOrganization(
        id: _str(json['id']),
        organizationKey: _str(json['organization_key']),
        name: _str(json['name']),
        type: _str(json['type']),
        status: _str(json['status']),
        country: _str(json['country']),
        state: _str(json['state']),
        district: _str(json['district']),
        address: _str(json['address']),
        postalCode: _str(json['postal_code']),
        contactEmail: _str(json['contact_email']),
        contactPhone: _str(json['contact_phone']),
        registrationNo: _str(json['registration_no']),
        location: _str(json['location']),
        clientId: _str(json['client_id']),
      );
}

class PlatformMember {
  const PlatformMember({
    required this.id,
    this.email = '',
    this.name = '',
    this.phone = '',
    this.role = '',
    this.orgId = '',
    this.status = 'ACTIVE',
    this.producerId = '',
  });

  final String id;
  final String email;
  final String name;
  final String phone;
  final String role;
  final String orgId;
  final String status;
  final String producerId;

  bool get isActive => status == 'ACTIVE';
  bool get isSuspended => status == 'SUSPENDED';

  factory PlatformMember.fromJson(Map<String, dynamic> json) => PlatformMember(
        id: _str(json['id']),
        email: _str(json['email']),
        name: _str(json['name']),
        phone: _str(json['phone']),
        role: _str(json['role']),
        orgId: _str(json['org_id']),
        status: _str(json['status']),
        producerId: _str(json['producer_id']),
      );
}

class PlatformBeekeeper {
  const PlatformBeekeeper({
    required this.id,
    this.name = '',
    this.phone = '',
    this.producerId = '',
    this.organizationId = '',
    this.orgKey = '',
    this.orgName = '',
    this.isIndependent = true,
    this.clientId = '',
  });

  final String id;
  final String name;
  final String phone;
  final String producerId;
  final String organizationId;
  final String orgKey;
  final String orgName;
  final bool isIndependent;
  final String clientId;

  factory PlatformBeekeeper.fromJson(Map<String, dynamic> json) =>
      PlatformBeekeeper(
        id: _str(json['id']),
        name: _str(json['name']),
        phone: _str(json['phone']),
        producerId: _str(json['producer_id']),
        organizationId: _str(json['organization_id']),
        orgKey: _str(json['org_key']),
        orgName: _str(json['org_name']),
        isIndependent: json['is_independent'] as bool? ?? true,
        clientId: _str(json['client_id']),
      );
}

class PlatformAdminInvite {
  const PlatformAdminInvite({
    required this.id,
    this.organizationKey = '',
    this.email = '',
    this.role = 'fpo',
    this.token = '',
    this.status = 'PENDING',
    this.createdAt = '',
  });

  final String id;
  final String organizationKey;
  final String email;
  final String role;
  final String token;
  final String status;
  final String createdAt;

  factory PlatformAdminInvite.fromJson(Map<String, dynamic> json) =>
      PlatformAdminInvite(
        id: _str(json['id']),
        organizationKey: _str(json['organization_key']),
        email: _str(json['email']),
        role: _str(json['role']),
        token: _str(json['token']),
        status: _str(json['status']),
        createdAt: _str(json['created_at']),
      );

  PlatformAdminInvite copyWithStatus(String status) => PlatformAdminInvite(
        id: id,
        organizationKey: organizationKey,
        email: email,
        role: role,
        token: token,
        status: status,
        createdAt: createdAt,
      );
}

class PlatformAuditEvent {
  const PlatformAuditEvent({
    required this.id,
    this.actorUserId = '',
    this.actorRole = '',
    this.action = '',
    this.targetType = '',
    this.targetKey = '',
    this.detail = const {},
    this.createdAt = '',
  });

  final String id;
  final String actorUserId;
  final String actorRole;
  final String action;
  final String targetType;
  final String targetKey;
  final Map<String, dynamic> detail;
  final String createdAt;

  factory PlatformAuditEvent.fromJson(Map<String, dynamic> json) =>
      PlatformAuditEvent(
        id: _str(json['id']),
        actorUserId: _str(json['actor_user_id']),
        actorRole: _str(json['actor_role']),
        action: _str(json['action']),
        targetType: _str(json['target_type']),
        targetKey: _str(json['target_key']),
        detail: (json['detail'] as Map<String, dynamic>?) ?? const {},
        createdAt: _str(json['created_at']),
      );
}

class PlatformStats {
  const PlatformStats({
    this.registeredBeekeepers = 0,
    this.organizations = 0,
    this.hives = 0,
    this.harvests = 0,
    this.honeyHarvestedKg = 0,
    this.batches = 0,
    this.labTests = 0,
    this.certificates = 0,
    this.iotDevices = 0,
    this.telemetryEvents = 0,
  });

  final int registeredBeekeepers;
  final int organizations;
  final int hives;
  final int harvests;
  final double honeyHarvestedKg;
  final int batches;
  final int labTests;
  final int certificates;
  final int iotDevices;
  final int telemetryEvents;

  factory PlatformStats.fromJson(Map<String, dynamic> json) => PlatformStats(
        registeredBeekeepers: _int(json['registered_beekeepers']),
        organizations: _int(json['organizations']),
        hives: _int(json['hives']),
        harvests: _int(json['harvests']),
        honeyHarvestedKg: _num(json['honey_harvested_kg']),
        batches: _int(json['batches']),
        labTests: _int(json['lab_tests']),
        certificates: _int(json['certificates']),
        iotDevices: _int(json['iot_devices']),
        telemetryEvents: _int(json['telemetry_events']),
      );
}

// --------------------------------------------------------------------------
// Service
// --------------------------------------------------------------------------

/// Platform-oversight operations against the verified FastAPI backend.
///
/// Backend layer is protected infrastructure — this service only READS/WRITES
/// through the existing verified API contracts; it never touches the database
/// or Fabric directly, and never fabricates numbers.
class PlatformApiService {
  PlatformApiService(this._client);

  final ApiClient _client;

  // ----------------------------------------------------------- organizations
  Future<List<PlatformOrganization>> listOrganizations() async {
    final rows = await _client.getListJson('/api/v1/platform/organizations');
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PlatformOrganization.fromJson)
        .toList();
  }

  Future<PlatformOrganization> createOrganization({
    required String name,
    String type = 'FPO',
    String country = '',
    String state = '',
    String district = '',
    String address = '',
    String postalCode = '',
    String contactEmail = '',
    String contactPhone = '',
    String registrationNo = '',
    String clientId = '',
  }) async {
    final body = await _client.postJson('/api/v1/platform/organizations', body: {
      'name': name,
      'type': type,
      'country': country,
      'state': state,
      'district': district,
      'address': address,
      'postal_code': postalCode,
      'contact_email': contactEmail,
      'contact_phone': contactPhone,
      'registration_no': registrationNo,
      'client_id': clientId,
    });
    return PlatformOrganization.fromJson(body);
  }

  /// Lifecycle transitions: activate | suspend | deactivate.
  Future<PlatformOrganization> setOrganizationStatus(
    String orgKey,
    String action,
  ) async {
    final body =
        await _client.postJson('/api/v1/platform/organizations/$orgKey/$action');
    return PlatformOrganization.fromJson(body);
  }

  // ---------------------------------------------------------------- admins
  Future<PlatformAdminInvite> inviteAdmin({
    required String orgKey,
    required String email,
    String role = 'fpo',
  }) async {
    final body = await _client.postJson(
      '/api/v1/platform/organizations/$orgKey/admins',
      body: {'email': email, 'role': role},
    );
    return PlatformAdminInvite.fromJson(body);
  }

  Future<PlatformAdminInvite> revokeAdminInvite(
    String orgKey,
    String inviteId,
  ) async {
    final body = await _client.postJson(
      '/api/v1/platform/organizations/$orgKey/admins/$inviteId/revoke',
    );
    return PlatformAdminInvite.fromJson(body);
  }

  // --------------------------------------------------------------- members
  Future<List<PlatformMember>> listMembers(String orgKey) async {
    final rows =
        await _client.getListJson('/api/v1/platform/organizations/$orgKey/members');
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PlatformMember.fromJson)
        .toList();
  }

  Future<List<PlatformBeekeeper>> listBeekeepers({String? orgKey}) async {
    final query = (orgKey == null || orgKey.isEmpty)
        ? ''
        : '?org_key=${Uri.encodeQueryComponent(orgKey)}';
    final rows = await _client.getListJson('/api/v1/platform/beekeepers$query');
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PlatformBeekeeper.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> assignBeekeeper(
    String orgKey,
    String userId,
  ) async {
    return _client.postJson(
      '/api/v1/platform/organizations/$orgKey/beekeepers',
      body: {'user_id': userId},
    );
  }

  /// Membership transitions: revoke | suspend | reinstate.
  Future<Map<String, dynamic>> memberAction(
    String orgKey,
    String userId,
    String action,
  ) async {
    return _client.postJson(
      '/api/v1/platform/organizations/$orgKey/members/$userId/$action',
    );
  }

  // ------------------------------------------------------------------ audit
  Future<List<PlatformAuditEvent>> listAudit({int limit = 100}) async {
    final rows = await _client.getListJson('/api/v1/platform/audit?limit=$limit');
    return rows
        .whereType<Map<String, dynamic>>()
        .map(PlatformAuditEvent.fromJson)
        .toList();
  }

  // ------------------------------------------------------------------ stats
  Future<PlatformStats> platformStats() async {
    final body = await _client.getJson('/api/v1/platform/stats');
    return PlatformStats.fromJson(body);
  }
}

// --------------------------------------------------------------------------
// Helpers
// --------------------------------------------------------------------------

String _str(Object? value) => value == null ? '' : '$value';

int _int(Object? value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

double _num(Object? value) {
  if (value is int) return value.toDouble();
  if (value is double) return value;
  return double.tryParse('$value') ?? 0;
}