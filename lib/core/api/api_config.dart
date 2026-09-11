/// Build-time backend configuration injected via `--dart-define`:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=https://api.honeychain.in
/// flutter run --dart-define=API_BASE_URL=http://localhost:8000
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000  (Android emulator -> host)
/// flutter build apk --dart-define=API_BASE_URL=https://api.honeychain.in
/// ```
///
/// Policy: production/staging URLs must be HTTPS. A plain-HTTP base is only
/// accepted for local development (localhost / 127.0.0.1 / the Android
/// emulator host alias 10.0.2.2) so the app can talk to a locally running
/// FastAPI backend; no other http:// URL passes the gate.
///
/// The mobile app never contains server credentials. When no API base is
/// compiled in, the app stays fully functional in offline/demo mode; when a
/// URL is compiled in but rejected, [startUpIssue] lets `main()` fail fast
/// instead of silently running without a backend.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  /// True only when a usable backend URL was compiled in (https, or an
  /// http://localhost / http://127.0.0.1 dev override).
  static bool get isConfigured => isAllowedBaseUrl(baseUrl);

  /// True only when the compiled base is the local dev backend override.
  static bool get isLocalDev => isLocalDevUrl(baseUrl);

  /// Non-null only when a URL was compiled in but the policy gate rejected it.
  /// `main()` uses this to fail fast with a clear dev error.
  static String? get startUpIssue {
    if (baseUrl.isEmpty) return null;
    if (isAllowedBaseUrl(baseUrl)) return null;
    return 'API_BASE_URL="$baseUrl" was rejected by the HoneyChain config '
        'gate. Production/staging must use https://; plain http:// is only '
        'allowed for localhost, 127.0.0.1 or the Android emulator host '
        '10.0.2.2. Rebuild with a valid --dart-define=API_BASE_URL=.';
  }

  /// Policy check shared with the compile-time gate (also unit-testable):
  /// HTTPS is always allowed; plain HTTP is only allowed for local dev hosts.
  static bool isAllowedBaseUrl(String url) {
    if (url.isEmpty) return false;
    if (url.startsWith('https://')) return true;
    return isLocalDevUrl(url);
  }

  static bool isLocalDevUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http://localhost') ||
        lower.startsWith('http://127.0.0.1') ||
        lower == 'http://10.0.2.2' ||
        lower.startsWith('http://10.0.2.2:');
  }

  /// Base URL with the trailing slash removed for path joining.
  static String get normalizedBaseUrl {
    if (baseUrl.endsWith('/')) return baseUrl.substring(0, baseUrl.length - 1);
    return baseUrl;
  }
}