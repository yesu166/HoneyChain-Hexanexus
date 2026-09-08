/// Build-time backend configuration injected via `--dart-define`:
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=https://api.honeychain.in
/// flutter build apk --dart-define=API_BASE_URL=...
/// ```
///
/// The mobile app never contains server credentials. When no API base is
/// compiled in, the app stays fully functional in offline/demo mode.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  /// True only when a production backend URL was compiled in.
  static bool get isConfigured => baseUrl.isNotEmpty && baseUrl.startsWith('https://');

  /// Base URL with the trailing slash removed for path joining.
  static String get normalizedBaseUrl {
    if (baseUrl.endsWith('/')) return baseUrl.substring(0, baseUrl.length - 1);
    return baseUrl;
  }
}