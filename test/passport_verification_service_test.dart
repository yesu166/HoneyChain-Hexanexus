import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:honeychain/core/api/api_client.dart';
import 'package:honeychain/core/api/api_exception.dart';
import 'package:honeychain/services/passport_verification_service.dart';

/// The passport verification service is the real provenance path: it must map
/// server responses to honest verify outcomes and never fabricate a proof.
void main() {
  PassportVerificationService serviceWith(MockClient mock) =>
      PassportVerificationService(ApiClient(
        httpClient: mock,
        baseUrl: 'https://example.test',
      ));

  Map<String, dynamic> anchoredPayload() => {
        'subject': 'batch',
        'subject_code': 'HC-B-001',
        'batch_code': 'HC-B-001',
        'honey_type': 'Wild Forest',
        'origin': 'Nilgiris, Tamil Nadu',
        'quantity_kg': 12.5,
        'trust_tier': 'blockchain_anchored',
        'anchor': {
          'data_hash': 'sha256:abc123',
          'tx_hash': 'tx-chain-001',
          'chain_status': 'anchored',
          'anchored_at': '2026-09-10T10:00:00Z',
        },
      };

  test('verified passport parses the real anchor and trust tier', () async {
    final service = serviceWith(MockClient((request) async {
      expect(request.url.path, '/api/v1/passport/HC-B-001');
      return http.Response(jsonEncode(anchoredPayload()), 200);
    }));

    final result = await verifyPassportOnline(service, 'HC-B-001');
    expect(result.verified, isTrue);
    expect(result.proof!.trustTier, 'blockchain_anchored');
    expect(result.proof!.isAnchored, isTrue);
    expect(result.proof!.anchor.dataHash, 'sha256:abc123');
    expect(result.proof!.anchor.txHash, 'tx-chain-001');
    expect(result.proof!.batchCode, 'HC-B-001');
  });

  test('URL-encodes the subject code', () async {
    final service = serviceWith(MockClient((request) async {
      expect(request.url.path, '/api/v1/passport/HC%2BB-B-1');
      return http.Response(jsonEncode(anchoredPayload()), 200);
    }));

    final result = await verifyPassportOnline(service, 'HC+B-B-1');
    expect(result.verified, isTrue);
  });

  test('404 resolves to not-found, never to verified', () async {
    final service = serviceWith(MockClient((_) async =>
        http.Response(jsonEncode({'detail': 'Not found'}), 404)));

    final result = await verifyPassportOnline(service, 'NOPE');
    expect(result.outcome, VerifyOutcome.notFound);
    expect(result.verified, isFalse);
  });

  test('429 resolves to rate-limited', () async {
    final service = serviceWith(MockClient((_) async =>
        http.Response(jsonEncode({'detail': 'Too many'}), 429)));

    final result = await verifyPassportOnline(service, 'HC-B-001');
    expect(result.outcome, VerifyOutcome.rateLimited);
    expect(result.verified, isFalse);
  });

  test('transport failure resolves to unreachable', () async {
    final service = serviceWith(MockClient((_) async =>
        throw const ApiException(ApiExceptionKind.network, '')));

    final result = await verifyPassportOnline(service, 'HC-B-001');
    expect(result.outcome, VerifyOutcome.unreachable);
    expect(result.message, isNotEmpty);
    expect(result.verified, isFalse);
  });

  test('server error resolves to unreachable', () async {
    final service = serviceWith(
        MockClient((_) async => http.Response('boom', 503)));

    final result = await verifyPassportOnline(service, 'HC-B-001');
    expect(result.outcome, VerifyOutcome.unreachable);
  });

  test('canonical proof JSON is deterministic', () {
    // Same parse twice from two equivalent payloads must produce identical
    // canonical strings, and the anchor hash must be included.
    final a = PassportProof.fromJson(anchoredPayload());
    final b = PassportProof.fromJson(anchoredPayload());
    expect(canonicalProofJson(a), canonicalProofJson(b));
    expect(canonicalProofJson(a), contains('tx-chain-001'));
  });

  test('a not-anchored passport stays honest (chain_status none)', () async {
    final payload = anchoredPayload()..['anchor'] = {'chain_status': 'none'};
    final service = serviceWith(MockClient(
        (_) async => http.Response(jsonEncode(payload), 200)));

    final result = await verifyPassportOnline(service, 'HC-B-001');
    expect(result.verified, isTrue);
    expect(result.proof!.isAnchored, isFalse);
    expect(result.proof!.anchor.status, PassportAnchorStatus.none);
  });
}