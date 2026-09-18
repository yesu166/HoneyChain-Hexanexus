import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:honeychain/core/api/api_client.dart';
import 'package:honeychain/data/auth.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/services/passport_verification_service.dart';

/// Regression tests for the consumer scan -> ONLINE passport fallback.
///
/// `resolveScan` only sees the on-device registry; a consumer scanning a REAL
/// jar must still reach the backend passport endpoint instead of dead-ending
/// on "not in the local registry".
void main() {
  group('passportCodeFromScan', () {
    test('extracts the code from app QR schemes', () {
      expect(
        HoneyChainStore.passportCodeFromScan('honeychain://trace/HC-B-9'),
        'HC-B-9',
      );
      expect(
        HoneyChainStore.passportCodeFromScan('honeychain://jar/JAR-1'),
        'JAR-1',
      );
    });

    test('extracts the code from a passport URL', () {
      expect(
        HoneyChainStore.passportCodeFromScan(
          'https://verify.honeychain.in/passport/HC-B-77',
        ),
        'HC-B-77',
      );
    });

    test('passes bare codes through untouched', () {
      expect(
        HoneyChainStore.passportCodeFromScan('  HC-TN-00128 '),
        'HC-TN-00128',
      );
      expect(HoneyChainStore.passportCodeFromScan(''), isNull);
    });
  });

  group('verifyScannedPassport online fallback', () {
    PassportVerificationService serviceWith(MockClient mock) =>
        PassportVerificationService(ApiClient(
          httpClient: mock,
          baseUrl: 'https://example.test',
        ));

    test('QR scheme payload resolves the embedded code online', () async {
      final requestedCodes = <String>[];
      final service = serviceWith(MockClient((request) async {
        requestedCodes.add(request.url.path);
        return http.Response(
          jsonEncode({
            'subject': 'batch',
            'subject_code': 'HC-SERVER-1',
            'batch_code': 'HC-SERVER-1',
            'trust_tier': 'blockchain_anchored',
            'anchor': {
              'data_hash': 'sha256:abc',
              'tx_hash': 'tx-9',
              'chain_status': 'anchored',
            },
          }),
          200,
        );
      }));

      final store = HoneyChainStore.instance;
      final result = await store.verifyScannedPassportWith(
        service,
        'honeychain://trace/HC-SERVER-1',
      );

      expect(result.verified, isTrue);
      expect(result.proof!.batchCode, 'HC-SERVER-1');
      expect(requestedCodes.single, '/api/v1/passport/HC-SERVER-1');
    });

    test('unknown code surfaces notFound, never a fabricated verification',
        () async {
      final service = serviceWith(MockClient((_) async =>
          http.Response(jsonEncode({'detail': 'Product not found'}), 404)));

      final store = HoneyChainStore.instance;
      final result =
          await store.verifyScannedPassportWith(service, 'HC-UNKNOWN-42');

      expect(result.outcome, VerifyOutcome.notFound);
      expect(result.verified, isFalse);
    });

    test('unreadable input errors honestly', () async {
      final store = HoneyChainStore.instance;
      final result = await store.verifyScannedPassportWith(
        serviceWith(MockClient((_) async => http.Response('[]', 200))),
        '',
      );
      expect(result.outcome, VerifyOutcome.error);
      expect(result.verified, isFalse);
    });
  });

  group('login routes the session to the role-owned workspace', () {
    // Workspace routing is a pure mapping; the backend role decides the
    // landing workspace so an FPO/lab/buyer never lands in the beekeeper
    // shell. See HoneyChainStore.beekeeperLogin + _RootGate in main.dart.
    test('workspace backendRole mapping covers every org role', () {
      // beekeeper + consumer are null-gated (demo personas), the org roles
      // map to their own workspace and platform oversight to its shell.
      expect(Workspace.platform.backendRole, 'platform_oversight');
      expect(Workspace.organization.backendRole, 'fpo');
      expect(Workspace.lab.backendRole, 'lab');
      expect(Workspace.buyer.backendRole, 'buyer');
      expect(Workspace.processor.backendRole, 'processor');
      expect(Workspace.beekeeper.backendRole, 'beekeeper');
    });
  });
}
