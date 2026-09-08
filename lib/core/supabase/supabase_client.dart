import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Lazily initializes the Supabase client when build-time configuration is
/// present. Without configuration the app runs in pure offline/demo mode and
/// never touches network.
class HoneySupabase {
  HoneySupabase._();

  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized || !SupabaseConfig.isConfigured) return;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    _initialized = true;
  }

  /// The initialized client, or null when Supabase is not configured (or has
  /// not been initialized yet). Callers must handle null gracefully.
  static SupabaseClient? maybeClient() {
    if (!_initialized || !SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }
}