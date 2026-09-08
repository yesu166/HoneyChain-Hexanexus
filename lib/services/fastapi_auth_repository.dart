import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import 'api_token_store.dart';

/// Login / session against the FastAPI backend.
///
/// The backend is the only place passwords and roles live. This service just
/// stores the returned JWT for the sync gateway and connectivity badge.
///
/// [ApiClient.tokenProvider] should be wired to `ApiTokenStore.instance.token`
/// so the `GET /me` call (used to build the persisted profile) is authorized.
class FastApiAuthRepository {
  FastApiAuthRepository(this._client);

  final ApiClient _client;

  /// Exchanges email/phone + password for a JWT and persists the session.
  /// Throws [ApiException] on failure (invalid credentials -> auth kind).
  Future<ApiIdentity> login({
    required String identifier,
    required String password,
  }) async {
    final body = await _client.postJson('/api/v1/auth/login', body: {
      'identifier': identifier,
      'password': password,
    });
    final token = body['access_token'] as String? ?? '';
    if (token.isEmpty) {
      throw const ApiException(
        ApiExceptionKind.unknown,
        'Backend did not return a session token.',
      );
    }
    // Persist the token first so /me (authorized via tokenProvider) succeeds.
    await ApiTokenStore.instance.save(
      ApiIdentity(
        token: token,
        id: '',
        email: identifier,
        name: '',
        role: '',
      ),
    );
    final me = await _client.postJson('/api/v1/auth/me');
    final identity = ApiIdentity(
      token: token,
      id: _asString(me['id']),
      email: _asString(me['email']),
      name: _asString(me['name']),
      role: _asString(me['role']),
      organizationId: _asString(me['org_id']),
    );
    await ApiTokenStore.instance.save(identity);
    return identity;
  }

  Future<void> signOut() async {
    await ApiTokenStore.instance.clear();
  }

  static String _asString(Object? value) => value == null ? '' : '$value';
}