import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:honeychain/core/api/api_exception.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/services/ask_my_bee/ask_my_bee_api.dart';
import 'package:honeychain/services/ask_my_bee/ask_my_bee_controller.dart';

String _identity(String key) => key;

class _FakeApi implements AskMyBeeApi {
  _FakeApi({this.replies = const []});

  final List<AskChatReply> replies;
  ApiException? nextError;
  Object? nextUnexpected;
  final List<List<AskChatMessage>> sent = [];
  int calls = 0;

  @override
  Future<AskChatReply> sendChat(List<AskChatMessage> messages,
      {String? language}) async {
    calls++;
    sent.add(messages);
    final err = nextError;
    if (err != null) throw err;
    final boom = nextUnexpected;
    if (boom != null) throw boom;
    if (calls <= replies.length) return replies[calls - 1];
    return const AskChatReply(reply: 'pong', toolCount: 0);
  }

  @override
  Future<AskBackendStatus> fetchStatus() async =>
      const AskBackendStatus(enabled: true, configured: true, model: 'test');
}

class _GatedApi implements AskMyBeeApi {
  Completer<AskChatReply>? next = Completer<AskChatReply>();

  @override
  Future<AskChatReply> sendChat(List<AskChatMessage> messages,
      {String? language}) =>
      next!.future;

  @override
  Future<AskBackendStatus> fetchStatus() async =>
      const AskBackendStatus(enabled: true, configured: true);
}

class _OffApi implements AskMyBeeApi {
  @override
  Future<AskChatReply> sendChat(List<AskChatMessage> messages,
      {String? language}) async =>
      const AskChatReply(reply: 'x', toolCount: 0);

  @override
  Future<AskBackendStatus> fetchStatus() async =>
      const AskBackendStatus(enabled: false, configured: false, model: '');
}

void main() {
  setUp(() {
    // Behaves like the app in test mode: no network, no Supabase.
    HoneyChainStore.testMode = true;
  });

  group('AskMyBeeController basics', () {
    test('starts idle with no entries and no error', () {
      final c = AskMyBeeController(null, tr: _identity);
      expect(c.state, AskMyBeeState.idle);
      expect(c.entries, isEmpty);
      expect(c.busy, isFalse);
      expect(c.offline, isTrue); // no backend compiled in
    });

    test('empty and whitespace text is ignored', () async {
      final c = AskMyBeeController(_FakeApi(),
          tr: _identity, offlineCheck: () => false);
      expect(await c.send('   '), isFalse);
      expect(await c.send(''), isFalse);
      expect(c.entries, isEmpty);
      expect(c.state, AskMyBeeState.idle);
    });

    test('an api null reports offline and surfaces ask.offline', () async {
      final c = AskMyBeeController(null, tr: _identity);
      expect(await c.send('hello'), isFalse);
      expect(c.state, AskMyBeeState.error);
      expect(c.lastError, 'ask.offline');
    });

    test('a true offlineCheck blocks the request too', () async {
      final api = _FakeApi();
      final c = AskMyBeeController(api, tr: _identity, offlineCheck: () => true);
      expect(await c.send('hello'), isFalse);
      expect(c.state, AskMyBeeState.error);
      expect(c.lastError, 'ask.offline');
      expect(api.calls, 0);
    });

    test('happy path appends user + assistant entries and returns idle',
        () async {
      final api = _FakeApi(
        replies: const [
          AskChatReply(reply: 'You have 2 hives.', toolCount: 1),
        ],
      );
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      final ok = await c.send('Show my hives');
      expect(ok, isTrue);
      expect(c.entries, hasLength(2));
      expect(c.entries.first.role, 'user');
      expect(c.entries.first.content, 'Show my hives');
      expect(c.entries.last.role, 'assistant');
      expect(c.entries.last.content, 'You have 2 hives.');
      expect(c.entries.last.toolCount, 1);
      expect(c.state, AskMyBeeState.idle);
      expect(api.sent, hasLength(1));
      expect(api.sent.first.first.content, 'Show my hives');
      expect(api.sent.first.first.role, 'user');
    });

    test('toolCount is preserved on the assistant entry', () async {
      final api = _FakeApi(
        replies: const [AskChatReply(reply: 'Done.', toolCount: 3)],
      );
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      await c.send('Record inspection');
      expect(c.entries.last.toolCount, 3);
    });
  });

  group('AskMyBeeController errors', () {
    test('429 maps to ask.rate.limited', () async {
      final api = _FakeApi()
        ..nextError = const ApiException(
            ApiExceptionKind.unknown, 'rate limited', statusCode: 429);
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      expect(await c.send('hello'), isFalse);
      expect(c.state, AskMyBeeState.error);
      expect(c.lastError, 'ask.rate.limited');
    });

    test('timeout maps to ask.timeout, not ask.offline', () async {
      final api = _FakeApi()
        ..nextError = const ApiException(
            ApiExceptionKind.timeout, 'Request timed out');
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      await c.send('hello');
      expect(c.lastError, 'ask.timeout');
    });

    test('network maps to ask.offline', () async {
      final api = _FakeApi()
        ..nextError = const ApiException(
            ApiExceptionKind.network, 'No connection');
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      await c.send('hello');
      expect(c.lastError, 'ask.offline');
    });

    test('401/403 map to ask.unauthorized', () async {
      final api = _FakeApi()
        ..nextError = const ApiException(
            ApiExceptionKind.auth, 'Token expired', statusCode: 401);
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      await c.send('hello');
      expect(c.lastError, 'ask.unauthorized');
    });

    test('validation surfaces the server message', () async {
      final api = _FakeApi()
        ..nextError = const ApiException(
            ApiExceptionKind.validation, 'too long', statusCode: 422);
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      await c.send('hello');
      expect(c.lastError, 'too long');
    });

    test('unexpected failures fall back to ask.error', () async {
      final api = _FakeApi()..nextUnexpected = StateError('boom');
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      await c.send('hello');
      expect(c.state, AskMyBeeState.error);
      expect(c.lastError, 'ask.error');
    });
  });

  group('AskMyBeeController concurrency', () {
    test('a second send while busy is rejected', () async {
      final api = _GatedApi();
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      final first = c.send('first');
      expect(c.busy, isTrue);
      expect(await c.send('second'), isFalse);
      api.next!.complete(const AskChatReply(reply: 'ok', toolCount: 0));
      expect(await first, isTrue);
      expect(c.entries, hasLength(2));
      expect(c.state, AskMyBeeState.idle);
    });

    test('cancelPending drops the in-flight reply and returns to idle',
        () async {
      final api = _GatedApi();
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      final first = c.send('first');
      c.cancelPending();
      expect(c.state, AskMyBeeState.idle);
      api.next!.complete(const AskChatReply(reply: 'late', toolCount: 0));
      expect(await first, isFalse);
      expect(c.entries, hasLength(1)); // user entry only
      expect(c.entries.last.role, 'user');
      expect(c.state, AskMyBeeState.idle);
    });
  });

  group('AskMyBeeController confirmation flow', () {
    test('awaitingConfirmation detects a restated write', () async {
      final api = _FakeApi(
        replies: const [
          AskChatReply(reply: 'Shall I confirm 1.0 kg to Hive A?', toolCount: 0),
        ],
      );
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      await c.send('record 1 kg');
      expect(c.awaitingConfirmation, isTrue);
    });

    test('awaitingConfirmation is false for a plain answer', () async {
      final api = _FakeApi(
        replies: const [
          AskChatReply(reply: 'Hive A has 3 frames.', toolCount: 0),
        ],
      );
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      await c.send('hive status');
      expect(c.awaitingConfirmation, isFalse);
    });

    test('confirmAction sends the explicit yes message', () async {
      final api = _FakeApi();
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      expect(await c.confirmAction(), isTrue);
      expect(api.sent.first.last.content, 'ask.confirm.yes.send');
    });

    test('declineAction sends the explicit no message', () async {
      final api = _FakeApi();
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      expect(await c.declineAction(), isTrue);
      expect(api.sent.first.last.content, 'ask.confirm.no.send');
    });
  });

  group('AskMyBeeController lifecycle', () {
    test('setListening enters listening and clears back to idle', () async {
      final c = AskMyBeeController(_FakeApi(),
          tr: _identity, offlineCheck: () => false);
      await c.setListening(true);
      expect(c.state, AskMyBeeState.listening);
      await c.setListening(false);
      expect(c.state, AskMyBeeState.idle);
    });

    test('reset wipes session and error', () async {
      final api = _FakeApi()
        ..nextError = const ApiException(
            ApiExceptionKind.unknown, 'x', statusCode: 500);
      final c = AskMyBeeController(api,
          tr: _identity, offlineCheck: () => false);
      await c.send('hello');
      expect(c.state, AskMyBeeState.error);
      c.reset();
      expect(c.entries, isEmpty);
      expect(c.lastError, isNull);
      expect(c.state, AskMyBeeState.idle);
    });

    test('refreshStatus stores backend status', () async {
      final c = AskMyBeeController(_FakeApi(),
          tr: _identity, offlineCheck: () => false);
      expect(c.backendStatus, isNull);
      await c.refreshStatus();
      expect(c.backendStatus, isNotNull);
      expect(c.backendStatus!.enabled, isTrue);
      expect(c.backendDisabled, isFalse);
    });

    test('backendDisabled when the server says it is off', () async {
      final c = AskMyBeeController(_OffApi(),
          tr: _identity, offlineCheck: () => false);
      await c.refreshStatus();
      expect(c.backendDisabled, isTrue);
    });
  });
}