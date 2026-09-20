/// Typed mirrors of the backend IoT + notification schemas
/// (`backend/app/schemas/iot.py`, `.../notification.py`).
///
/// Field names intentionally match the API exactly; parsing tolerates missing
/// optional fields but never invented values, so the UI cannot present data
/// the backend did not produce.
class IotDevice {
  const IotDevice({
    required this.deviceId,
    required this.deviceName,
    required this.deviceType,
    required this.firmwareVersion,
    required this.deviceStatus,
    this.assignedHiveId,
    this.assignedApiaryId,
    required this.organizationId,
    this.lastSeen,
    required this.createdAt,
    required this.sequence,
    required this.eventCount,
    this.batteryPercent,
    this.signalStrength,
    required this.mode,
    required this.isSimulated,
    this.configuration = const {},
  });

  final String deviceId;
  final String deviceName;
  final String deviceType;
  final String firmwareVersion;
  final String deviceStatus;
  final String? assignedHiveId;
  final String? assignedApiaryId;
  final String organizationId;
  final String? lastSeen;
  final String createdAt;
  final int sequence;
  final int eventCount;
  final double? batteryPercent;
  final double? signalStrength;
  final String mode;
  final bool isSimulated;
  final Map<String, dynamic> configuration;

  bool get isOnline => deviceStatus == 'ONLINE' || deviceStatus == 'SYNCING';

  factory IotDevice.fromJson(Map<String, dynamic> json) => IotDevice(
        deviceId: json['device_id'] as String? ?? '',
        deviceName: json['device_name'] as String? ?? '',
        deviceType: json['device_type'] as String? ?? '',
        firmwareVersion: json['firmware_version'] as String? ?? '',
        deviceStatus: json['device_status'] as String? ?? 'OFFLINE',
        assignedHiveId: json['assigned_hive_id'] as String?,
        assignedApiaryId: json['assigned_apiary_id'] as String?,
        organizationId: json['organization_id'] as String? ?? '',
        lastSeen: json['last_seen'] as String?,
        createdAt: json['created_at'] as String? ?? '',
        sequence: json['sequence'] as int? ?? 0,
        eventCount: json['event_count'] as int? ?? 0,
        batteryPercent: _asDouble(json['battery_percent']),
        signalStrength: _asDouble(json['signal_strength']),
        mode: json['mode'] as String? ?? 'STOPPED',
        isSimulated: json['is_simulated'] as bool? ?? true,
        configuration:
            json['configuration'] as Map<String, dynamic>? ?? const {},
      );
}

class IotTelemetry {
  const IotTelemetry({
    required this.eventId,
    required this.deviceId,
    required this.sequence,
    required this.timestamp,
    required this.payload,
    required this.payloadHash,
    required this.previousEventHash,
    required this.isSimulated,
  });

  final String eventId;
  final String deviceId;
  final int sequence;
  final String timestamp;
  final TelemetryPayload payload;
  final String payloadHash;
  final String previousEventHash;
  final bool isSimulated;

  factory IotTelemetry.fromJson(Map<String, dynamic> json) => IotTelemetry(
        eventId: json['event_id'] as String? ?? '',
        deviceId: json['device_id'] as String? ?? '',
        sequence: json['sequence'] as int? ?? 0,
        timestamp: json['timestamp'] as String? ?? '',
        payload: TelemetryPayload.fromJson(
          json['payload'] as Map<String, dynamic>? ?? const {},
        ),
        payloadHash: json['payload_hash'] as String? ?? '',
        previousEventHash: json['previous_event_hash'] as String? ?? '',
        isSimulated: json['is_simulated'] as bool? ?? true,
      );
}

class TelemetryPayload {
  const TelemetryPayload({
    this.temperatureC,
    this.humidityPercent,
    this.hiveWeightKg,
    this.beeActivity,
    this.acousticFrequencyHz,
    this.batteryPercent,
    this.signalStrength,
    this.extra = const {},
  });

  final double? temperatureC;
  final double? humidityPercent;
  final double? hiveWeightKg;
  final double? beeActivity;
  final double? acousticFrequencyHz;
  final double? batteryPercent;
  final double? signalStrength;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        if (temperatureC != null) 'temperature_c': temperatureC,
        if (humidityPercent != null) 'humidity_percent': humidityPercent,
        if (hiveWeightKg != null) 'hive_weight_kg': hiveWeightKg,
        if (beeActivity != null) 'bee_activity': beeActivity,
        if (acousticFrequencyHz != null)
          'acoustic_frequency_hz': acousticFrequencyHz,
        if (batteryPercent != null) 'battery_percent': batteryPercent,
        if (signalStrength != null) 'signal_strength': signalStrength,
        'extra': extra,
      };

  factory TelemetryPayload.fromJson(Map<String, dynamic> json) =>
      TelemetryPayload(
        temperatureC: _asDouble(json['temperature_c']),
        humidityPercent: _asDouble(json['humidity_percent']),
        hiveWeightKg: _asDouble(json['hive_weight_kg']),
        beeActivity: _asDouble(json['bee_activity']),
        acousticFrequencyHz: _asDouble(json['acoustic_frequency_hz']),
        batteryPercent: _asDouble(json['battery_percent']),
        signalStrength: _asDouble(json['signal_strength']),
        extra: json['extra'] as Map<String, dynamic>? ?? const {},
      );
}

class SimulatorDeviceStatus {
  const SimulatorDeviceStatus({
    required this.deviceId,
    required this.mode,
    required this.deviceStatus,
    required this.pendingEvents,
    this.lastEventAt,
    this.mlStatus = 'NORMAL',
    this.mlScore,
    this.mlAnomaly = false,
    this.mlEvidence = const [],
    this.mlReason = '',
    this.mlRecommendation = '',
    this.mlPersistenceObservations = 0,
  });

  final String deviceId;
  final String mode;
  final String deviceStatus;
  final int pendingEvents;
  final String? lastEventAt;
  final String mlStatus;
  final double? mlScore;
  final bool mlAnomaly;
  final List<String> mlEvidence;
  final String mlReason;
  final String mlRecommendation;
  final int mlPersistenceObservations;

  factory SimulatorDeviceStatus.fromJson(Map<String, dynamic> json) {
    final ml = json['ml'] is Map
        ? Map<String, dynamic>.from(json['ml'] as Map)
        : const <String, dynamic>{};
    return SimulatorDeviceStatus(
      deviceId: json['device_id'] as String? ?? '',
      mode: json['mode'] as String? ?? 'STOPPED',
      deviceStatus: json['device_status'] as String? ?? 'OFFLINE',
      pendingEvents: json['pending_events'] as int? ?? 0,
      lastEventAt: json['last_event_at'] as String?,
      mlStatus: ml['status'] as String? ?? 'NORMAL',
      mlScore: _asDouble(ml['score']),
      mlAnomaly: ml['ml_anomaly'] as bool? ?? false,
      mlEvidence: (ml['evidence'] as List?)
              ?.whereType<String>()
              .toList() ??
          const [],
      mlReason: ml['reason'] as String? ?? '',
      mlRecommendation: ml['recommendation'] as String? ?? '',
      mlPersistenceObservations:
          ml['persistence_observations'] as int? ?? 0,
    );
  }
}

class BackendNotification {
  const BackendNotification({
    required this.notificationId,
    this.hiveId,
    this.batchId,
    this.deviceId,
    required this.category,
    required this.severity,
    required this.reason,
    required this.recommendedAction,
    required this.source,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    required this.isSimulated,
  });

  final String notificationId;
  final String? hiveId;
  final String? batchId;
  final String? deviceId;
  final String category;
  final String severity;
  final String reason;
  final String recommendedAction;
  final String source;
  final String title;
  final String body;
  final String createdAt;
  final bool read;
  final bool isSimulated;

  factory BackendNotification.fromJson(Map<String, dynamic> json) =>
      BackendNotification(
        notificationId: json['notification_id'] as String? ?? '',
        hiveId: json['hive_id'] as String?,
        batchId: json['batch_id'] as String?,
        deviceId: json['device_id'] as String?,
        category: json['category'] as String? ?? '',
        severity: json['severity'] as String? ?? 'info',
        reason: json['reason'] as String? ?? '',
        recommendedAction: json['recommended_action'] as String? ?? '',
        source: json['source'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        createdAt: json['created_at'] as String? ?? '',
        read: json['read'] as bool? ?? false,
        isSimulated: json['is_simulated'] as bool? ?? true,
      );
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}