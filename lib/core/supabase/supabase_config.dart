/// Build-time configuration injected via `--dart-define`:
///
/// ```sh
/// flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///             --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
/// ```
///
/// Nothing secret is committed here; the publishable key is client-safe by
/// design and still must never be treated as a server credential.
class SupabaseConfig {
  SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');

  static const String publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// True only when both the project URL and the publishable key were
  /// compiled in. Offline/demo mode is kept fully functional when unset.
  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}