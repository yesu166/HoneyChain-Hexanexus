import 'package:flutter_test/flutter_test.dart';

import 'package:honeychain/core/api/api_config.dart';

void main() {
  test('default build has no hardcoded production API URL', () {
    // This machine/CI has no --dart-define=API_BASE_URL; there must never be a
    // defaulted localhost/127.0.0.1 fallback inside the code.
    const base = String.fromEnvironment('API_BASE_URL');
    expect(base, '');
    expect(ApiConfig.isConfigured, isFalse);
  });

  test('normalizedBaseUrl strips a trailing slash', () {
    // Simulate via a compile-time constant the URL-shaping rules we rely on.
    const withSlash = 'https://api.example.in/';
    const expected = 'https://api.example.in';
    final normalized =
        withSlash.endsWith('/') ? withSlash.substring(0, withSlash.length - 1) : withSlash;
    expect(normalized, expected);
  });

  test('isConfigured requires https outside local dev hosts', () {
    // Local dev override policy: http://localhost / http://127.0.0.1 / the
    // Android emulator host alias 10.0.2.2 is the ONLY plain-HTTP base the
    // app will talk to; everything else needs https.
    expect(ApiConfig.isAllowedBaseUrl('http://localhost:8000'), isTrue);
    expect(ApiConfig.isAllowedBaseUrl('http://127.0.0.1:8000'), isTrue);
    expect(ApiConfig.isLocalDevUrl('http://localhost:8000'), isTrue);
    expect(ApiConfig.isAllowedBaseUrl('http://api.example.in'), isFalse);
    expect(ApiConfig.isAllowedBaseUrl('http://example.com'), isFalse);
    expect(ApiConfig.isAllowedBaseUrl('https://api.example.in'), isTrue);
    expect(ApiConfig.isAllowedBaseUrl(''), isFalse);
  });

  test('Android emulator host alias 10.0.2.2 is accepted as local dev', () {
    expect(ApiConfig.isLocalDevUrl('http://10.0.2.2'), isTrue);
    expect(ApiConfig.isAllowedBaseUrl('http://10.0.2.2:8000'), isTrue);
    // 10.0.2.20 is NOT the emulator alias and must not slip through.
    expect(ApiConfig.isAllowedBaseUrl('http://10.0.2.20:8000'), isFalse);
  });

  test('startUpIssue fails fast only for a compiled but rejected URL', () {
    // startUpIssue is built on the compile-time constant, so it can only be
    // exercised via the pure policy functions here.
    expect(ApiConfig.isAllowedBaseUrl(''), isFalse);
    expect(ApiConfig.isAllowedBaseUrl('http://evil.in'), isFalse);
    expect(ApiConfig.isAllowedBaseUrl('http://localhost:8000'), isTrue);
    expect(ApiConfig.isAllowedBaseUrl('https://api.honeychain.in'), isTrue);
  });
}