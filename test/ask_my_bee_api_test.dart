import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:honeychain/core/api/api_client.dart';
import 'package:honeychain/core/api/api_exception.dart';
import 'package:honeychain/services/ask_my_bee/ask_my_bee_api.dart';

void main() {
  AskMyBeeHttpApi apiWith(MockClient mock) => AskMyBeeHttpApi(
        ApiClient(httpClient: mock, baseUrl: 'https://api.test.in'),
      );

  test('sendChat posts the transcript and parses the reply', () async {
    final api = apiWith(MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.test.in/api/v1/ai/chat');
      final sent = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = sent['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(messages.first, {'role': 'user', 'content': 'Show my hives'});
      expect(messages.last, {'role': 'assistant', 'content': 'You have 2 hives.'});
      return http.Response(
        jsonEncode({
          'reply': 'Hive A has 3 frames of brood.',
          'tool_count': 1,
          'request_id': 'req-1',
        }),
        200,
      );
    }));

    final reply = await api.sendChat(const [
      AskChatMessage(role: 'user', content: 'Show my hives'),
      AskChatMessage(role: 'assistant', content: 'You have 2 hives.'),
    ]);
    expect(reply.reply, 'Hive A has 3 frames of brood.');
    expect(reply.toolCount, 1);
    expect(reply.requestId, 'req-1');
  });

  test('sendChat tolerates a missing tool_count', () async {
    final api = apiWith(MockClient(
        (_) async => http.Response(jsonEncode({'reply': 'ok'}), 200)));
    final reply = await api.sendChat(
        const [AskChatMessage(role: 'user', content: 'Hello')]);
    expect(reply.reply, 'ok');
    expect(reply.toolCount, 0);
  });

  test('sendChat rejects a body without a reply string', () async {
    final api = apiWith(MockClient(
        (_) async => http.Response(jsonEncode({'request_id': 'r'}), 200)));
    expect(
      () => api.sendChat(const [AskChatMessage(role: 'user', content: 'Hi')]),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.unknown)),
    );
  });

  test('429 maps to ApiException with status code 429', () async {
    final api = apiWith(MockClient((_) async => http.Response(
        jsonEncode({'detail': 'rate limited'}), 429)));
    expect(
      () => api.sendChat(const [AskChatMessage(role: 'user', content: 'Hi')]),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 429)),
    );
  });

  test('401 maps to auth', () async {
    final api = apiWith(MockClient((_) async => http.Response(
        jsonEncode({'detail': 'Token expired'}), 401)));
    expect(
      () => api.sendChat(const [AskChatMessage(role: 'user', content: 'Hi')]),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.auth)),
    );
  });

  test('5xx maps to server', () async {
    final api = apiWith(MockClient((_) async => http.Response('boom', 503)));
    expect(
      () => api.sendChat(const [AskChatMessage(role: 'user', content: 'Hi')]),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.server)),
    );
  });

  test('fetchStatus parses enabled / configured / model', () async {
    final api = apiWith(MockClient((request) async {
      expect(request.url.toString(), 'https://api.test.in/api/v1/ai/status');
      return http.Response(
        jsonEncode({'enabled': true, 'configured': true, 'model': 'gemini-2.5-flash'}),
        200,
      );
    }));
    final status = await api.fetchStatus();
    expect(status.enabled, isTrue);
    expect(status.configured, isTrue);
    expect(status.model, 'gemini-2.5-flash');
  });

  test('fetchStatus defaults to disabled when fields are missing', () async {
    final api = apiWith(MockClient((_) async => http.Response('{}', 200)));
    final status = await api.fetchStatus();
    expect(status.enabled, isFalse);
    expect(status.configured, isFalse);
    expect(status.model, isEmpty);
  });

  test('network failure maps to network', () async {
    final api = apiWith(MockClient((_) async {
      throw const SocketException('Connection refused');
    }));
    expect(
      () => api.sendChat(const [AskChatMessage(role: 'user', content: 'Hi')]),
      throwsA(isA<ApiException>()
          .having((e) => e.kind, 'kind', ApiExceptionKind.network)),
    );
  });
}