import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:honeychain/core/api/api_client.dart';
import 'package:honeychain/core/api/api_exception.dart';
import 'package:honeychain/services/honey_api_service.dart';

void main() {
  HoneyApiService serviceWith(MockClient mock) =>
      HoneyApiService(ApiClient(httpClient: mock, baseUrl: 'https://api.test.in'));

  group('hives', () {
    test('listHives parses snake_case rows', () async {
      final service = serviceWith(MockClient((request) async {
        expect(request.url.path, '/api/v1/hives');
        return http.Response(
          jsonEncode([
            {
              'id': 'h-1',
              'hive_code': 'HC-LIVE-001',
              'beekeeper_id': 'u-1',
              'org_id': 'org-1',
              'status': 'active',
              'client_id': 'cli-1',
              'created_at': '2026-09-10T10:00:00+00:00',
            },
          ]),
          200,
        );
      }));

      final hives = await service.listHives();
      expect(hives, hasLength(1));
      expect(hives.single.id, 'h-1');
      expect(hives.single.hiveCode, 'HC-LIVE-001');
      expect(hives.single.orgId, 'org-1');
      expect(hives.single.createdAt, isNotNull);
    });

    test('createHive posts hive_code and parses the created row', () async {
      final service = serviceWith(MockClient((request) async {
        expect(request.url.path, '/api/v1/hives');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['hive_code'], 'Mango Apiary');
        expect(body['beekeeper_id'], 'u-9');
        expect(body['location'], 'Nilgiris');
        expect(body['status'], 'active');
        return http.Response(
          jsonEncode({
            'id': 'h-9',
            'hive_code': 'Mango Apiary',
            'beekeeper_id': 'u-9',
            'org_id': '',
            'status': 'active',
            'client_id': '',
          }),
          201,
        );
      }));

      final hive = await service.createHive(
        hiveCode: 'Mango Apiary',
        beekeeperId: 'u-9',
        location: 'Nilgiris',
      );
      expect(hive.id, 'h-9');
      expect(hive.hiveCode, 'Mango Apiary');
    });
  });

  group('harvests', () {
    test('createHarvest posts the beekeeper harvest payload', () async {
      final service = serviceWith(MockClient((request) async {
        expect(request.url.path, '/api/v1/harvests');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['hive_id'], 'h-1');
        expect(body['beekeeper_id'], 'u-1');
        expect(body['quantity_kg'], 12.5);
        expect(body['honey_type'], 'Eucalyptus');
        expect(body['harvested_at'], isNotEmpty);
        return http.Response(
          jsonEncode({
            'id': 'harvest-9',
            'hive_id': 'h-1',
            'beekeeper_id': 'u-1',
            'harvested_at': '2026-09-10T10:00:00+00:00',
            'quantity_kg': 12.5,
            'honey_type': 'Eucalyptus',
            'client_id': '',
            'collected': false,
          }),
          201,
        );
      }));

      final harvest = await service.createHarvest(
        hiveId: 'h-1',
        beekeeperId: 'u-1',
        quantityKg: 12.5,
        honeyType: 'Eucalyptus',
        harvestedAt: DateTime.utc(2026, 9, 10, 10),
      );
      expect(harvest.id, 'harvest-9');
      expect(harvest.quantityKg, 12.5);
      expect(harvest.collected, isFalse);
    });

    test('listHarvests parses the server rows', () async {
      final service = serviceWith(MockClient((request) async {
        expect(request.url.path, '/api/v1/harvests');
        return http.Response(
          jsonEncode([
            {
              'id': 'harvest-1',
              'hive_id': 'h-1',
              'beekeeper_id': 'u-1',
              'harvested_at': '2026-09-09T10:00:00+00:00',
              'quantity_kg': 8.0,
              'honey_type': 'Wildflower',
              'client_id': '',
              'collected': true,
            },
          ]),
          200,
        );
      }));

      final harvests = await service.listHarvests();
      expect(harvests.single.honeyType, 'Wildflower');
      expect(harvests.single.collected, isTrue);
    });
  });

  group('batches', () {
    test('listBatches parses BatchRead rows', () async {
      final service = serviceWith(MockClient((request) async {
        expect(request.url.path, '/api/v1/batches');
        return http.Response(
          jsonEncode([
            {
              'id': 'b-1',
              'batch_code': 'HC-LIVE-9001',
              'status': 'collected',
              'honey_type': 'Eucalyptus',
              'quantity_kg': 20.0,
              'origin': 'Nilgiris',
              'organization_id': 'org-1',
              'trust_tier': 'blockchain_anchored',
              'client_id': '',
            },
          ]),
          200,
        );
      }));

      final batches = await service.listBatches();
      expect(batches.single.batchCode, 'HC-LIVE-9001');
      expect(batches.single.trustTier, 'blockchain_anchored');
      expect(batches.single.quantityKg, 20.0);
    });
  });

  group('evidence (anchor)', () {
    test('createHarvestEvidenceBundle anchors on Fabric and parses tx', () async {
      final service = serviceWith(MockClient((request) async {
        expect(request.url.path, '/api/v1/evidence/bundles');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['entity_type'], 'harvest');
        expect(body['entity_ref'], 'harvest-9');
        expect(body['anchor'], isTrue);
        expect(body['evidence'], hasLength(3));
        final kinds =
            (body['evidence'] as List).map((e) => e['kind']).toSet();
        expect(
          kinds,
          containsAll(['gps', 'timestamp', 'operator_note']),
        );
        return http.Response(
          jsonEncode({
            'bundle_id': 'bundle-abc123',
            'entity_type': 'harvest',
            'entity_ref': 'harvest-9',
            'operator': 'Demo Beekeeper',
            'leaf_count': 3,
            'root_hash': 'deadbeef',
            'anchor': {
              'tx_ref': 'tx-ref-1',
              'operation': 'submit_anchor',
              'state': 'CONFIRMED',
              'tx_hash': 'fabric-tx-123',
              'network': 'fabric:mychannel',
              'block_number': 42,
            },
            'evidence': [],
          }),
          200,
        );
      }));

      final bundle = await service.createHarvestEvidenceBundle(
        entityRef: 'harvest-9',
        operator: 'Demo Beekeeper',
        quantityKg: 12.5,
        honeyType: 'Eucalyptus',
      );
      expect(bundle.bundleId, 'bundle-abc123');
      expect(bundle.isAnchored, isTrue);
      expect(bundle.txHash, 'fabric-tx-123');
      expect(bundle.network, 'fabric:mychannel');
    });

    test('verifyBundle parses the audit result', () async {
      final service = serviceWith(MockClient((request) async {
        expect(request.url.path, '/api/v1/evidence/bundles/bundle-1/verify');
        return http.Response(
          jsonEncode({
            'bundle_id': 'bundle-1',
            'entity_type': 'harvest',
            'entity_ref': 'harvest-9',
            'root_hash': 'deadbeef',
            'recomputed_root': 'deadbeef',
            'evidence_intact': true,
            'anchor_state': 'CONFIRMED',
            'anchored': true,
            'evidence_count': 3,
          }),
          200,
        );
      }));

      final result = await service.verifyBundle('bundle-1');
      expect(result.anchored, isTrue);
      expect(result.evidenceIntact, isTrue);
      expect(result.evidenceCount, 3);
    });
  });

  group('blockchain', () {
    test('blockchainHealth parses live Fabric health', () async {
      final service = serviceWith(MockClient((request) async {
        expect(request.url.path, '/api/v1/blockchain/health');
        return http.Response(
          jsonEncode({
            'adapter': 'fabric',
            'status': 'connected',
            'network': 'fabric:mychannel',
            'channel': 'mychannel',
            'chaincode': 'honeychain',
            'chaincode_version': 2.0,
            'chaincode_sequence': 6,
            'peer': 'peer0.org1.example.com:7051',
            'msp_id': 'Org1MSP',
            'last_verified_at': '2026-09-10T10:00:00+00:00',
            'error': null,
          }),
          200,
        );
      }));

      final health = await service.blockchainHealth();
      expect(health.isConnected, isTrue);
      expect(health.channel, 'mychannel');
      expect(health.chaincode, 'honeychain');
      expect(health.chaincodeSequence, 6);
    });

    test('blockchainStatus carries tracker + fabric block', () async {
      final service = serviceWith(MockClient((request) async {
        expect(request.url.path, '/api/v1/blockchain/status');
        return http.Response(
          jsonEncode({
            'adapter': 'fabric',
            'ledger': 'fabric',
            'tracker': {'transactions': 4},
            'transactions': [],
            'fabric': {'status': 'connected', 'channel': 'mychannel'},
          }),
          200,
        );
      }));

      final status = await service.blockchainStatus();
      expect(status.transactionCount, 4);
      expect(status.fabric?['channel'], 'mychannel');
    });
  });

  group('errors', () {
    test('expired session surfaces ApiException(auth)', () async {
      final service = serviceWith(MockClient(
          (_) async => http.Response(jsonEncode({'detail': 'Unauthorized'}), 401)));
      await expectLater(
        service.listHives(),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiExceptionKind.auth)),
      );
    });
  });
}