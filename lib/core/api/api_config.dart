/// Build-time backend configuration injected via `--dart-define`:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=https://api.honeychain.in
/// flutter run --dart-define=API_BASE_URL=http://localhost:8000
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000  (Android emulator -> host)
/// flutter run --dart-define=API_BASE_URL=http://13.127.118.165:8000 \
///   --dart-define=HTTP_DEV_HOSTS=13.127.118.165              (prototype build)
/// flutter build apk --dart-define=API_BASE_URL=https://api.honeychain.in
/// ```
///
/// Policy: production/staging URLs must be HTTPS. A plain-HTTP base is only
/// accepted for local development (localhost / 127.0.0.1 / the Android
/// emulator host alias 10.0.2.2) or for hosts explicitly enumerated in a
/// `--dart-define=HTTP_DEV_HOSTS` comma-separated allowlist (prototype phase:
/// the EC2 backend is plain HTTP until TLS is added). No other http:// URL
/// passes the gate.
///
/// The mobile app never contains server credentials. When no API base is
/// compiled in, the app stays fully functional in offline/demo mode; when a
/// URL is compiled in but rejected, [startUpIssue] lets `main()` fail fast
/// instead of silently running without a backend.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  /// Comma-separated host allowlist that is permitted to use plain HTTP.
  ///
  /// Only meaningful for the prototype phase when the FastAPI backend runs on
  /// a bare HTTP EC2 endpoint. Empty in production builds. `http://` to any
  /// host not on this list (and not a local-dev host) is rejected.
  static const String httpDevHosts = String.fromEnvironment('HTTP_DEV_HOSTS');

  /// True only when a usable backend URL was compiled in (https, or an
  /// http://localhost / http://127.0.0.1 / HTTP_DEV_HOSTS prototype override).
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
        'allowed for localhost, 127.0.0.1, the Android emulator host '
        '10.0.2.2 or a host in --dart-define=HTTP_DEV_HOSTS. Rebuild with a '
        'valid --dart-define=API_BASE_URL= or add the host to HTTP_DEV_HOSTS.';
  }

  /// Policy check shared with the compile-time gate (also unit-testable):
  /// HTTPS is always allowed; plain HTTP is only allowed for local dev hosts
  /// or explicitly allowlisted prototype hosts.
  static bool isAllowedBaseUrl(String url) {
    if (url.isEmpty) return false;
    if (url.startsWith('https://')) return true;
    return isLocalDevUrl(url) || _isInHttpDevHosts(url);
  }

  /// True when [url] is plain HTTP to a host listed in [httpDevHosts].
  static bool _isInHttpDevHosts(String url) {
    if (httpDevHosts.isEmpty) return false;
    if (!url.toLowerCase().startsWith('http://')) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return httpDevHosts
        .split(',')
        .map((h) => h.trim().toLowerCase())
        .where((h) => h.isNotEmpty)
        .contains(host);
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