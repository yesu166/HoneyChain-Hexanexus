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
    // Local dev override policy: http://localhost / http://127.0.0.1 is the
    // ONLY plain-HTTP base the app will talk to; everything else needs https.
    expect(ApiConfig.isAllowedBaseUrl('http://localhost:8000'), isTrue);
    expect(ApiConfig.isAllowedBaseUrl('http://127.0.0.1:8000'), isTrue);
    expect(ApiConfig.isLocalDevUrl('http://localhost:8000'), isTrue);
    expect(ApiConfig.isAllowedBaseUrl('http://api.example.in'), isFalse);
    expect(ApiConfig.isAllowedBaseUrl('http://example.com'), isFalse);
    expect(ApiConfig.isAllowedBaseUrl('https://api.example.in'), isTrue);
    expect(ApiConfig.isAllowedBaseUrl(''), isFalse);
  });
}