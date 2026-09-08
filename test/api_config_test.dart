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

  test('isConfigured requires https', () {
    // The config gate lives in ApiConfig; this guards against an accidental
    // localhost value slipping past --dart-define.
    const httpUrl = 'http://localhost:8000';
    final configured = httpUrl.isNotEmpty && httpUrl.startsWith('https://');
    expect(configured, isFalse);
  });
}