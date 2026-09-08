import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:honeychain/core/api/api_client.dart';
import 'package:honeychain/core/api/api_exception.dart';

void main() {
  ApiClient clientWith(MockClient mock) =>
      ApiClient(httpClient: mock, baseUrl: 'https://api.test.in');

  test('GET parses JSON object', () async {
    final api = clientWith(MockClient((request) async {
      expect(request.url.toString(), 'https://api.test.in/api/v1/health');
      return http.Response(jsonEncode({'status': 'ok'}), 200);
    }));
    final body = await api.getJson('/api/v1/health');
    expect(body['status'], 'ok');
  });

  test('POST sends bearer token when provider set', () async {
    final api = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer abc');
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
      baseUrl: 'https://api.test.in',
      tokenProvider: () => 'abc',
    );
    await api.postJson('/api/v1/sync/push', body: {'items': []});
  });

  test('POST defaults to JSON Content-Type', () async {
    final api = clientWith(MockClient((request) async {
      expect(request.headers['Content-Type'], startsWith('application/json'));
      return http.Response('', 204);
    }));
    await api.postJson('/api/v1/sync/pull', body: {});
  });

  test('401 maps to auth', () async {
    final api = clientWith(MockClient((_) async =>
        http.Response(jsonEncode({'detail': 'Token expired'}), 401)));
    expect(
      () => api.getJson('/api/v1/auth/me'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiExceptionKind.auth)
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.friendly.contains('Session expired'), 'friendly', true),
      ),
    );
  });

  test('404 maps to notFound', () async {
    final api = clientWith(MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'Product not found'}), 404)));
    expect(
      () => api.getJson('/api/v1/passport/BAD'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.notFound)),
    );
  });

  test('422 extracts the first validation message', () async {
    final api = clientWith(MockClient((_) async => http.Response(
        jsonEncode({
          'detail': [
            {'msg': 'batch_code: String should have at least 1 character'}
          ]
        }),
        422)));
    expect(
      () => api.getJson('/api/v1/batches'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.validation)
          .having((e) => e.message, 'message', contains('batch_code'))),
    );
  });

  test('5xx maps to server', () async {
    final api = clientWith(
        MockClient((_) async => http.Response('boom', 503)));
    expect(
      () => api.getJson('/api/v1/sync/pull'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.server)),
    );
  });

  test('SocketException maps to network', () async {
    final api = ApiClient(
      httpClient: MockClient((_) async {
        throw const SocketException('Connection refused');
      }),
      baseUrl: 'https://api.test.in',
    );
    expect(
      () => api.getJson('/api/v1/health'),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.network)),
    );
  });
}