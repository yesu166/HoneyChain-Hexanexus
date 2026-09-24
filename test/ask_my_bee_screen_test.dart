import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honeychain/core/api/api_exception.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/screens/ask_my_bee_screen.dart';
import 'package:honeychain/services/ask_my_bee/ask_my_bee_api.dart';
import 'package:honeychain/services/ask_my_bee/ask_my_bee_controller.dart';
import 'package:honeychain/services/speech/speech_service.dart';
import 'package:honeychain/services/speech/text_to_speech_service.dart';

class _FakeApi implements AskMyBeeApi {
  _FakeApi({this.replies = const []});

  final List<AskChatReply> replies;
  ApiException? nextError;
  final List<List<AskChatMessage>> sent = [];
  int calls = 0;

  @override
  Future<AskChatReply> sendChat(List<AskChatMessage> messages) async {
    calls++;
    sent.add(messages);
    final err = nextError;
    if (err != null) throw err;
    if (calls <= replies.length) return replies[calls - 1];
    return const AskChatReply(reply: 'Here are your hives.', toolCount: 0);
  }

  @override
  Future<AskBackendStatus> fetchStatus() async =>
      const AskBackendStatus(enabled: true, configured: true, model: 'test');
}

class _UnsupportedTts implements TextToSpeechService {
  @override
  bool get isSupported => false;

  @override
  bool speak(String text, {String? languageCode}) => false;

  @override
  void stop() {}
}

class _NoMicSpeech implements SpeechRecognitionService {
  @override
  bool get isSupported => false;

  @override
  String? get lastResult => null;

  @override
  Future<SpeechProbe> probe({String? localeId}) async => const SpeechProbe(
        permission: SpeechPermissionStatus.denied,
        available: false,
      );

  @override
  Stream<String> listen({String? localeId}) => Stream.empty();

  @override
  void cancel() {}
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() {
    HoneyChainStore.testMode = true;
  });

  testWidgets('empty state shows title, suggestions and placeholder',
      (tester) async {
    final controller = AskMyBeeController(_FakeApi(),
        offlineCheck: () => false);
    await tester.pumpWidget(_wrap(AskMyBeeScreen(
      controller: controller,
      speech: _NoMicSpeech(),
      tts: _UnsupportedTts(),
    )));
    await tester.pumpAndSettle();

    expect(find.text('Ask My Bee'), findsNWidgets(2)); // AppBar title + toggle
    expect(find.text('TRY ASKING'), findsOneWidget); // SectionLabel uppercases
    expect(find.text('Show my hives'), findsOneWidget);
    expect(find.text('How is my hive doing?'), findsOneWidget);
    // The empty state is a lazy ListView — scroll to the remaining suggestions.
    final listView = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Record an inspection'), 200,
        scrollable: listView);
    expect(find.text('Record an inspection'), findsOneWidget);
    expect(find.text('Show recent harvests'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Record treatment'), 200,
        scrollable: listView);
    expect(find.text('Record treatment'), findsOneWidget);
    expect(find.text('Check bee health'), findsOneWidget);
    expect(find.text('Ask about your hives…'), findsOneWidget);
  });

  testWidgets('sending a typed message shows the assistant reply with tool chip',
      (tester) async {
    final api = _FakeApi(
      replies: const [
        AskChatReply(reply: 'You have 2 hives.', toolCount: 2),
      ],
    );
    final controller = AskMyBeeController(api, offlineCheck: () => false);
    await tester.pumpWidget(_wrap(AskMyBeeScreen(
      controller: controller,
      speech: _NoMicSpeech(),
      tts: _UnsupportedTts(),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField), 'Show my hives');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Show my hives'), findsOneWidget); // user bubble
    expect(find.text('You have 2 hives.'), findsOneWidget); // assistant bubble
    expect(find.text('2 hive tool(s) used'), findsOneWidget);
    expect(api.sent, hasLength(1));
    expect(api.sent.first.first.content, 'Show my hives');
  });

  testWidgets('an error surfaces an inline error card', (tester) async {
    final api = _FakeApi()
      ..nextError = const ApiException(
          ApiExceptionKind.unknown, 'rate limited', statusCode: 429);
    final controller = AskMyBeeController(api, offlineCheck: () => false);
    await tester.pumpWidget(_wrap(AskMyBeeScreen(
      controller: controller,
      speech: _NoMicSpeech(),
      tts: _UnsupportedTts(),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(
      find.text('Too many messages — wait a minute and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('a pending write shows the confirmation card; Confirm sends yes',
      (tester) async {
    final api = _FakeApi(
      replies: const [
        AskChatReply(reply: 'Shall I confirm 1.0 kg to Hive A?', toolCount: 0),
        AskChatReply(reply: 'Recorded 1.0 kg to Hive A.', toolCount: 1),
      ],
    );
    final controller = AskMyBeeController(api, offlineCheck: () => false);
    await tester.pumpWidget(_wrap(AskMyBeeScreen(
      controller: controller,
      speech: _NoMicSpeech(),
      tts: _UnsupportedTts(),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'record 1 kg');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Confirm this record'), findsOneWidget);
    expect(find.text('Nothing is recorded until you confirm.'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(api.sent, hasLength(2));
    expect(api.sent.last.last.content, 'Yes, confirm.');
    expect(find.text('Recorded 1.0 kg to Hive A.'), findsOneWidget);
    expect(find.text('Confirm this record'), findsNothing);
  });

  testWidgets('tapping the mic without speech support shows a snackbar',
      (tester) async {
    final controller = AskMyBeeController(_FakeApi(),
        offlineCheck: () => false);
    await tester.pumpWidget(_wrap(AskMyBeeScreen(
      controller: controller,
      speech: _NoMicSpeech(),
      tts: _UnsupportedTts(),
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Voice input is not available on this device. Please type instead.'),
      findsOneWidget,
    );
    expect(find.text('Ask about your hives…'), findsOneWidget); // still on empty state
  });

  testWidgets('an error card offers Try again and resends without duplicating',
      (tester) async {
    final api = _FakeApi()
      ..nextError = const ApiException(
          ApiExceptionKind.network, 'offline', statusCode: null);
    final controller = AskMyBeeController(api, offlineCheck: () => false);
    await tester.pumpWidget(_wrap(AskMyBeeScreen(
      controller: controller,
      speech: _NoMicSpeech(),
      tts: _UnsupportedTts(),
    )));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Show my hives');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(
      find.text('Ask My Bee needs an internet connection.'),
      findsOneWidget,
    );
    expect(find.text('Show my hives'), findsOneWidget); // no duplicate bubble

    api.nextError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Here are your hives.'), findsOneWidget);
    expect(api.sent, hasLength(2));
    expect(api.sent.last.first.content, 'Show my hives');
    expect(find.text('Show my hives'), findsOneWidget); // still one bubble
  });

  testWidgets('an api-null controller shows the offline banner', (tester) async {
    final controller = AskMyBeeController(null, offlineCheck: () => false);
    await tester.pumpWidget(_wrap(AskMyBeeScreen(
      controller: controller,
      speech: _NoMicSpeech(),
      tts: _UnsupportedTts(),
    )));
    await tester.pumpAndSettle();

    expect(
      find.text('Ask My Bee needs an internet connection.'),
      findsOneWidget,
    );
  });
}