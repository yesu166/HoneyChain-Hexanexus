import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:honeychain/core/api/api_client.dart';
import 'package:honeychain/core/api/api_exception.dart';
import 'package:honeychain/services/backend_iot_service.dart';

void main() {
  BackendIotService serviceWith(MockClient mock) =>
      BackendIotService(ApiClient(httpClient: mock, baseUrl: 'https://api.test.in'));

  final deviceJson = {
    'device_id': 'HC-SIM-abcdef1234',
    'device_name': 'Hive-4 sensor',
    'device_type': 'hive-sensor',
    'firmware_version': '1.0.0',
    'device_status': 'ONLINE',
    'assigned_hive_id': 'hive-004',
    'assigned_apiary_id': null,
    'organization_id': 'ORG-TN-001',
    'last_seen': null,
    'created_at': '2026-09-09T10:00:00+00:00',
    'sequence': 7,
    'event_count': 7,
    'battery_percent': 96.0,
    'signal_strength': -61.0,
    'mode': 'NORMAL',
    'is_simulated': true,
    'configuration': {},
  };

  test('registeredDevices parses the device registry', () async {
    final service = serviceWith(MockClient((request) async {
      expect(request.url.path, '/api/v1/iot/devices');
      return http.Response(jsonEncode([deviceJson]), 200);
    }));
    final devices = await service.registeredDevices();
    expect(devices, hasLength(1));
    final device = devices.single;
    expect(device.deviceId, 'HC-SIM-abcdef1234');
    expect(device.assignedHiveId, 'hive-004');
    expect(device.isSimulated, isTrue);
    expect(device.isOnline, isTrue);
    expect(device.mode, 'NORMAL');
  });

  test('deviceTelemetry sends the limit query and parses events', () async {
    final service = serviceWith(MockClient((request) async {
      expect(request.url.path, '/api/v1/iot/devices/HC-1/telemetry');
      expect(request.url.queryParameters['limit'], '5');
      return http.Response(jsonEncode([
        {
          'event_id': 'ev-1',
          'device_id': 'HC-1',
          'sequence': 2,
          'timestamp': '2026-09-09T10:00:00+00:00',
          'payload': {
            'temperature_c': 38.5,
            'humidity_percent': 74.0,
            'hive_weight_kg': 21.4,
            'bee_activity': 42.0,
            'acoustic_frequency_hz': 262.0,
            'battery_percent': 96.0,
            'signal_strength': -61.0,
            'extra': {'note': 'x'},
          },
          'payload_hash': 'deadbeef',
          'previous_event_hash': '',
          'is_simulated': true,
          'created_at': '2026-09-09T10:01:00+00:00',
        },
      ]), 200);
    }));
    final events = await service.deviceTelemetry('HC-1', limit: 5);
    expect(events, hasLength(1));
    expect(events.single.payload.temperatureC, 38.5);
    expect(events.single.payload.hiveWeightKg, 21.4);
  });

  test('simulatorControl posts action and mode', () async {
    final service = serviceWith(MockClient((request) async {
      expect(request.url.path, '/api/v1/iot/simulator/control');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['device_id'], 'HC-1');
      expect(body['action'], 'START');
      expect(body['mode'], 'ANOMALY');
      return http.Response(
          jsonEncode({'device_id': 'HC-1', 'action': 'START', 'mode': 'ANOMALY'}),
          200);
    }));
    final result = await service.simulatorControl('HC-1', 'START', mode: 'ANOMALY');
    expect(result['action'], 'START');
  });

  test('simulatorStatus parses pending_events', () async {
    final service = serviceWith(MockClient((_) async => http.Response(jsonEncode([
          {'device_id': 'HC-1', 'mode': 'OFFLINE', 'device_status': 'OFFLINE', 'pending_events': 4}
        ]), 200)));
    final status = await service.simulatorStatus();
    expect(status.single.pendingEvents, 4);
    expect(status.single.mode, 'OFFLINE');
  });

  test('notifications unwraps items and retains severity', () async {
    final service = serviceWith(MockClient((_) async => http.Response(
        jsonEncode({
          'items': [
            {
              'notification_id': 'n-1',
              'hive_id': 'hive-004',
              'device_id': 'HC-1',
              'category': 'telemetry',
              'severity': 'warning',
              'reason': 'High temperature',
              'recommended_action': 'Inspect the hive',
              'source': 'iot',
              'title': 'High temperature',
              'body': '',
              'created_at': '2026-09-09T10:00:00+00:00',
              'read': false,
              'is_simulated': true,
            },
          ],
          'unread_count': 1,
        }),
        200)));
    final notes = await service.notifications();
    expect(notes, hasLength(1));
    expect(notes.single.category, 'telemetry');
    expect(notes.single.severity, 'warning');
    expect(notes.single.recommendedAction, 'Inspect the hive');
  });

  test('markNotificationRead hits the read endpoint', () async {
    final service = serviceWith(MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v1/notifications/n-42/read');
      return http.Response(jsonEncode({'notification_id': 'n-42', 'read': true}), 200);
    }));
    final result = await service.markNotificationRead('n-42');
    expect(result['read'], isTrue);
  });

  test('unauthorized access surfaces an auth ApiException', () async {
    final service = serviceWith(MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'Token expired'}), 401)));
    expect(
      () => service.registeredDevices(),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.auth)),
    );
  });

  test('backendFailureFriendly turns network errors into guidance', () {
    const error =
        ApiException(ApiExceptionKind.network, 'whatever');
    expect(backendFailureFriendly(error), contains('Backend unreachable'));
  });
}