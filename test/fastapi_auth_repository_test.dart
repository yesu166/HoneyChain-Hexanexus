import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:honeychain/core/api/api_client.dart';
import 'package:honeychain/core/api/api_exception.dart';
import 'package:honeychain/services/api_token_store.dart';
import 'package:honeychain/services/fastapi_auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiTokenStore.instance.init();
  });

  ApiClient api(MockClient mock) => ApiClient(
        httpClient: mock,
        baseUrl: 'https://api.test.in',
        tokenProvider: () => ApiTokenStore.instance.token,
      );

  test('login exchanges credentials for a JWT and persists identity', () async {
    final client = api(MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['identifier'], 'demo@honeychain.in');
        expect(body['password'], 'secret');
        return http.Response(
            jsonEncode({'access_token': 'jwt.abc'}), 200);
      }
      if (request.url.path == '/api/v1/auth/me') {
        expect(request.headers['Authorization'], 'Bearer jwt.abc');
        return http.Response(
          jsonEncode({
            'id': 'u-1',
            'email': 'demo@honeychain.in',
            'name': 'Demo Beekeeper',
            'role': 'beekeeper',
            'org_id': 'org-1',
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    }));

    final identity = await FastApiAuthRepository(client).login(
      identifier: 'demo@honeychain.in',
      password: 'secret',
    );

    expect(identity.token, 'jwt.abc');
    expect(identity.role, 'beekeeper');
    expect(identity.email, 'demo@honeychain.in');
    // survives restart (persisted)
    final restored = ApiTokenStore.instance.identity;
    expect(restored, isNotNull);
    expect(restored!.token, 'jwt.abc');
    expect(restored.name, 'Demo Beekeeper');
  });

  test('invalid credentials surface ApiException(auth)', () async {
    final client = api(MockClient((_) async =>
        http.Response(jsonEncode({'detail': 'Invalid credentials'}), 401)));
    expect(
      () => FastApiAuthRepository(client).login(identifier: 'x', password: 'y'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.auth)),
    );
  });

  test('signOut clears persisted token', () async {
    final client = api(MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        return http.Response(jsonEncode({'access_token': 'jwt.abc'}), 200);
      }
      return http.Response(
        jsonEncode({'id': 'u', 'email': 'e', 'name': 'N', 'role': 'fpo'}),
        200,
      );
    }));
    final repo = FastApiAuthRepository(client);
    await repo.login(identifier: 'e', password: 'p');
    expect(ApiTokenStore.instance.token, 'jwt.abc');

    await repo.signOut();
    expect(ApiTokenStore.instance.token, isNull);
    expect(ApiTokenStore.instance.identity, isNull);
  });
}
