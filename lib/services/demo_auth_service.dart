import '../core/supabase/supabase_client.dart';

/// Minimal Supabase auth entry points used by the developer/diagnostics screen.
///
/// Demo credentials match the seeded auth users in
/// `supabase/migrations/004_seed_demo_data.sql`. Production login flows
/// (phone/OTP, OAuth) belong to the authentication repository workstream and
/// are intentionally not wired here.
class DemoAuthService {
  DemoAuthService._();

  static const beekeeperEmail = 'demo@honeychain.in';
  static const orgEmail = 'org@honeychain.in';
  static const demoPassword = 'HoneyChainDemo!1';

  static Future<bool> signInBeekeeper() => _signIn(beekeeperEmail);

  static Future<bool> signInOrganization() => _signIn(orgEmail);

  static Future<bool> _signIn(String email) async {
    final client = HoneySupabase.maybeClient();
    if (client == null) return false;
    try {
      await client.auth.signInWithPassword(
        email: email,
        password: demoPassword,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> signOut() async {
    final client = HoneySupabase.maybeClient();
    if (client == null) return;
    await client.auth.signOut();
  }

  static String? signedInEmail() {
    final client = HoneySupabase.maybeClient();
    return client?.auth.currentUser?.email;
  }
}