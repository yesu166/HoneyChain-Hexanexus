import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../core/supabase/supabase_client.dart';
import '../core/supabase/supabase_config.dart';
import 'api_token_store.dart';
import 'fastapi_sync_gateway.dart';
import 'supabase_sync_gateway.dart';
import 'sync_service.dart';

/// Returns the sync gateway appropriate for the build:
///
/// * a [FastApiSyncGateway] when a production `API_BASE_URL` is compiled in
///   (Flutter -> HTTPS -> FastAPI -> Supabase);
/// * a real [SupabaseSyncGateway] when only direct Supabase `--dart-define`
///   configuration is present (transitional mode), reusing the server-side RLS
///   writes;
/// * the in-memory [MockSyncGateway] otherwise (demo / tests), which is
///   idempotent so the offline queue still behaves like a real backend.
SyncGateway createSyncGateway() {
  if (ApiConfig.isConfigured) {
    return FastApiSyncGateway(
      ApiClient(tokenProvider: () => ApiTokenStore.instance.token),
    );
  }
  if (SupabaseConfig.isConfigured) {
    final client = HoneySupabase.maybeClient();
    if (client != null) return SupabaseSyncGateway(client);
  }
  return MockSyncGateway();
}