import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../models/iot.dart';

/// Client for the backend IoT + notification endpoints
/// (`backend/app/api/routes/iot.py`, `.../notifications.py`).
///
/// Thin layer over [ApiClient]: maps HTTP to typed models, throws
/// [ApiException] unchanged so the store can translate them into
/// "backend offline / rejected" states instead of raw errors.
class BackendIotService {
  BackendIotService(this._client);

  final ApiClient _client;

  // ------------------------------------------------------------- registry
  Future<List<IotDevice>> registeredDevices() async {
    final rows = await _client.getListJson('/api/v1/iot/devices');
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) IotDevice.fromJson(row),
    ];
  }

  Future<Map<String, dynamic>> registerDevice({
    required String deviceName,
    String deviceType = 'hive-sensor',
    String firmwareVersion = '1.0.0',
    String assignedHiveId = '',
    String assignedApiaryId = '',
  }) async {
    return _client.postJson('/api/v1/iot/devices', body: {
      'device_name': deviceName,
      'device_type': deviceType,
      'firmware_version': firmwareVersion,
      if (assignedHiveId.isNotEmpty) 'assigned_hive_id': assignedHiveId,
      if (assignedApiaryId.isNotEmpty) 'assigned_apiary_id': assignedApiaryId,
    });
  }

  // ------------------------------------------------------------ telemetry
  Future<List<IotTelemetry>> deviceTelemetry(
    String deviceId, {
    int limit = 20,
  }) async {
    final rows = await _client.getListJson(
      '/api/v1/iot/devices/$deviceId/telemetry?limit=$limit',
    );
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) IotTelemetry.fromJson(row),
    ];
  }

  Future<Map<String, dynamic>> deviceLedger(String deviceId) async {
    return _client.getJson('/api/v1/iot/devices/$deviceId/ledger');
  }

  // ----------------------------------------------------------- simulator
  Future<Map<String, dynamic>> simulatorControl(
    String deviceId,
    String action, {
    String? mode,
    int burstCount = 10,
    TelemetryPayload? custom,
  }) async {
    return _client.postJson('/api/v1/iot/simulator/control', body: {
      'device_id': deviceId,
      'action': action,
      'mode': ?mode,
      if (action == 'GENERATE_EVENT') 'burst_count': burstCount,
      'custom_payload': ?custom?.toJson(),
    });
  }

  Future<Map<String, dynamic>> simulatorMode(String deviceId, String mode) async {
    return _client.postJson('/api/v1/iot/simulator/mode', body: {
      'device_id': deviceId,
      'mode': mode,
    });
  }

  Future<List<SimulatorDeviceStatus>> simulatorStatus() async {
    final rows = await _client.getListJson('/api/v1/iot/simulator/status');
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) SimulatorDeviceStatus.fromJson(row),
    ];
  }

  Future<Map<String, dynamic>> simulatorFork(String deviceId) async {
    return _client.postJson(
      '/api/v1/iot/simulator/fork',
      body: {'device_id': deviceId},
    );
  }

  // ------------------------------------------------------- notifications
  Future<List<BackendNotification>> notifications() async {
    final body = await _client.getJson('/api/v1/notifications');
    final items = body['items'];
    if (items is! List) return const [];
    return [
      for (final row in items)
        if (row is Map<String, dynamic>) BackendNotification.fromJson(row),
    ];
  }

  Future<Map<String, dynamic>> markNotificationRead(String notificationId) async {
    return _client.postJson('/api/v1/notifications/$notificationId/read');
  }

  Future<Map<String, dynamic>> staleCheck() async {
    return _client.postJson('/api/v1/notifications/stale-check');
  }
}

/// Human/prettier error for a failed backend call. [ApiException] keeps the
/// transport detail; this normalizes the four cases the UI actually cares
/// about. Never throws.
String backendFailureFriendly(ApiException error) {
  return switch (error.kind) {
    ApiExceptionKind.network => 'Backend unreachable (is FastAPI running?)',
    ApiExceptionKind.timeout => 'Backend timed out',
    ApiExceptionKind.auth => 'Not signed in - backend rejected the session',
    ApiExceptionKind.forbidden =>
      'Permission denied by backend (${error.message})',
    ApiExceptionKind.notFound => 'Not found on backend',
    ApiExceptionKind.validation => 'Rejected by backend: ${error.message}',
    _ => 'Backend error (${error.statusCode ?? '?'})',
  };
}