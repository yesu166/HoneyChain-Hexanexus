import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/screens/ask_my_bee_screen.dart';
import 'package:honeychain/services/ask_my_bee/ask_my_bee_api.dart';
import 'package:honeychain/services/ask_my_bee/ask_my_bee_controller.dart';
import 'package:honeychain/services/speech/speech_service.dart';
import 'package:honeychain/services/speech/text_to_speech_service.dart';

class _ChatApi implements AskMyBeeApi {
  final List<AskChatReply> replies = const [];
  final List<List<AskChatMessage>> sent = [];
  int calls = 0;

  @override
  Future<AskChatReply> sendChat(List<AskChatMessage> messages,
      {String? language}) async {
    calls++;
    sent.add(messages);
    if (calls <= replies.length) return replies[calls - 1];
    return const AskChatReply(reply: 'Got it.', toolCount: 0);
  }

  @override
  Future<AskBackendStatus> fetchStatus() async =>
      const AskBackendStatus(enabled: true, configured: true);
}

class _FakeSpeech implements SpeechRecognitionService {
  final bool supported = true;
  final _controller = StreamController<String>();
  final List<String?> localeIds = [];

  @override
  bool get isSupported => supported;

  @override
  String? get lastResult => null;

  @override
  Future<SpeechProbe> probe({String? localeId}) async => const SpeechProbe(
        permission: SpeechPermissionStatus.granted,
        available: true,
        effectiveLocale: 'ta-IN',
      );

  @override
  Stream<String> listen({String? localeId}) {
    localeIds.add(localeId);
    return _controller.stream;
  }

  @override
  void cancel() {
    if (!_controller.isClosed) _controller.close();
  }

  void emit(String text) => _controller.add(text);

  void fail(SpeechFailure failure) {
    _controller.addError(failure);
    _controller.close();
  }

  void done() => _controller.close();
}

class _QuietTts implements TextToSpeechService {
  @override
  bool get isSupported => false;

  @override
  bool speak(String text, {String? languageCode}) => false;

  @override
  void stop() {}
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() {
    HoneyChainStore.testMode = true;
  });

  group('locale helpers', () {
    test('speechLocaleId maps known languages and defaults to en-IN', () {
      expect(speechLocaleId('en'), 'en-IN');
      expect(speechLocaleId('ta'), 'ta-IN');
      expect(speechLocaleId('hi'), 'hi-IN');
      expect(speechLocaleId('bn'), 'bn-IN');
      expect(speechLocaleId('xx'), 'en-IN');
    });

    test('ttsLanguageId mirrors speechLocaleId', () {
      expect(ttsLanguageId('ta'), 'ta-IN');
      expect(ttsLanguageId('mr'), 'mr-IN');
      expect(ttsLanguageId('en'), 'en-IN');
    });

    test('speechLocaleId/ttsLanguageId cover all 7 app languages', () {
      for (final lang in ['en', 'ta', 'hi', 'bn', 'pa', 'ml', 'mr']) {
        final id = speechLocaleId(lang);
        expect(id.split('-').first, lang, reason: '$lang => $id');
        expect(ttsLanguageId(lang), id);
      }
    });
  });

  group('Ask My Bee speech', () {
    testWidgets('recognized text flows into the assistant conversation',
        (tester) async {
      final speech = _FakeSpeech();
      final api = _ChatApi();
      final controller = AskMyBeeController(api,
          offlineCheck: () => false);

      await tester.pumpWidget(_wrap(AskMyBeeScreen(
        controller: controller,
        speech: speech,
        tts: _QuietTts(),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Listening… speak now'), findsOneWidget);
      expect(speech.localeIds, ['en-IN']);

      speech.emit('two kilograms');
      speech.done();
      await tester.pumpAndSettle();

      expect(find.text('"two kilograms"'), findsNothing); // preview cleared
      expect(find.text('two kilograms'), findsOneWidget); // user bubble
      expect(find.text('Got it.'), findsOneWidget); // assistant bubble
      expect(api.sent, hasLength(1));
      expect(api.sent.first.first.content, 'two kilograms');
    });

    testWidgets('a permission error shows a snackbar and returns to idle',
        (tester) async {
      final speech = _FakeSpeech();
      final controller = AskMyBeeController(_ChatApi(),
          offlineCheck: () => false);

      await tester.pumpWidget(_wrap(AskMyBeeScreen(
        controller: controller,
        speech: speech,
        tts: _QuietTts(),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      speech.fail(const SpeechFailure(SpeechFailureKind.permissionDenied));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.textContaining('Microphone permission denied'),
        findsOneWidget,
      );
      expect(controller.state, AskMyBeeState.idle);
      expect(controller.entries, isEmpty);
    });

    testWidgets('a no-speech result shows a snackbar without sending',
        (tester) async {
      final speech = _FakeSpeech();
      final api = _ChatApi();
      final controller = AskMyBeeController(api,
          offlineCheck: () => false);

      await tester.pumpWidget(_wrap(AskMyBeeScreen(
        controller: controller,
        speech: speech,
        tts: _QuietTts(),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      speech.done();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('No speech heard. Try again or type instead.'),
          findsOneWidget);
      expect(api.sent, isEmpty);
      expect(controller.state, AskMyBeeState.idle);
    });
  });
}