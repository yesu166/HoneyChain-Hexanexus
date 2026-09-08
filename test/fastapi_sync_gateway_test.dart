import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:honeychain/core/api/api_client.dart';
import 'package:honeychain/core/api/api_exception.dart';
import 'package:honeychain/models/domain.dart';
import 'package:honeychain/services/fastapi_sync_gateway.dart';

Harvest _harvest({String id = 'h-1'}) => Harvest(
      id: id,
      hiveId: 'hive-1',
      beekeeperId: 'bk-1',
      harvestedAt: DateTime.utc(2026, 9, 8, 10),
      honeyType: 'Multifloral',
      quantityKg: 8.5,
      syncStatus: SyncStatus.pending,
    );

Batch _batch({String id = 'b-1'}) => Batch(
      id: id,
      code: 'HC-2026-TN-0001',
      organizationId: 'org-1',
      honeyType: 'Multifloral',
      origin: 'Kotagiri',
      quantityKg: 8.5,
      createdAt: DateTime.utc(2026, 9, 8, 11),
      status: BatchStatus.created,
      syncStatus: SyncStatus.pending,
    );

ApiClient _api(MockClient mock) =>
    ApiClient(httpClient: mock, baseUrl: 'https://api.test.in');

void main() {
  test('pushHarvest sends a harvest sync item', () async {
    final api = _api(MockClient((request) async {
      expect(request.url.path, '/api/v1/sync/push');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final item = (body['items'] as List).first as Map<String, dynamic>;
      expect(item['entity'], 'harvest');
      expect(item['client_id'], 'h-1');
      final data = item['data'] as Map<String, dynamic>;
      expect(data['quantity_kg'], 8.5);
      return http.Response(
        jsonEncode({
          'accepted': [
            {'entity': 'harvest', 'client_id': 'h-1', 'accepted': true, 'backend_id': 'remote-1'}
          ],
          'rejected': []
        }),
        200,
      );
    }));
    final gateway = FastApiSyncGateway(api);
    final result = await gateway.pushHarvest(_harvest());
    expect(result.success, isTrue);
    expect(result.backendId, 'remote-1');
  });

  test('pushBatch sends a batch sync item', () async {
    final api = _api(MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final item = (body['items'] as List).first as Map<String, dynamic>;
      expect(item['entity'], 'batch');
      expect((item['data'] as Map<String, dynamic>)['batch_code'], 'HC-2026-TN-0001');
      return http.Response(
        jsonEncode({
          'accepted': [
            {'entity': 'batch', 'client_id': 'b-1', 'accepted': true, 'backend_id': 'remote-b'}
          ],
          'rejected': []
        }),
        200,
      );
    }));
    final result = await FastApiSyncGateway(api).pushBatch(_batch());
    expect(result.success, isTrue);
    expect(result.backendId, 'remote-b');
  });

  test('rejected item yields SyncResult.failure (queue retains it)', () async {
    final api = _api(MockClient((_) async => http.Response(
          jsonEncode({
            'accepted': [],
            'rejected': [
              {'client_id': 'h-1', 'accepted': false, 'error': 'hive not in your scope'}
            ]
          }),
          200,
        )));
    final result = await FastApiSyncGateway(api).pushHarvest(_harvest());
    expect(result.success, isFalse);
  });

  test('network failure propagates ApiException for SyncEngine to retry', () async {
    final api = ApiClient(
      httpClient: MockClient((_) async {
        throw const SocketException('offline');
      }),
      baseUrl: 'https://api.test.in',
    );
    expect(
      () => FastApiSyncGateway(api).pushHarvest(_harvest()),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.network)),
    );
    // The client id is NOT recorded as accepted, so a later pass retries it.
    final recovered = _api(MockClient((_) async => http.Response(
          jsonEncode({
            'accepted': [
              {'client_id': 'h-1', 'accepted': true, 'backend_id': 'remote-1'}
            ],
            'rejected': []
          }),
          200,
        )));
    final result = await FastApiSyncGateway(recovered).pushHarvest(_harvest());
    expect(result.success, isTrue);
  });

  test('replay of the same client id is not double-pushed', () async {
    var pushes = 0;
    final api = _api(MockClient((request) async {
      pushes++;
      return http.Response(
        jsonEncode({
          'accepted': [
            {'client_id': 'h-1', 'accepted': true, 'backend_id': 'remote-1'}
          ],
          'rejected': []
        }),
        200,
      );
    }));
    final gateway = FastApiSyncGateway(api);
    await gateway.pushHarvest(_harvest());
    await gateway.pushHarvest(_harvest());
    expect(pushes, 1);
  });
}