import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'text_to_speech_service.dart';

/// Native (Android/iOS) text-to-speech backed by `flutter_tts`.
///
/// Uses the installed system TTS engine and requests the app's current
/// language (Tamil/English/etc.) where the engine provides it. If the language
/// or the engine is unavailable the caller falls back to showing text —
/// audio is never faked.
class NativeTextToSpeechService implements TextToSpeechService {
  FlutterTts? _tts;
  bool _failed = false;

  @override
  bool get isSupported => !_failed;

  @override
  bool speak(String text, {String? languageCode}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _failed) return false;
    final tts = _tts ??= FlutterTts();
    // Best effort: keep the async work contained so a missing engine or a
    // missing plugin channel (tests/desktop) never breaks the caller.
    unawaited(
      () async {
        try {
          // Stop any utterance still streaming so a new reply never overlaps
          // (voice output must stay audible and non-garbled).
          await tts.stop();
          if (languageCode != null && languageCode.isNotEmpty) {
            await tts.setLanguage(ttsLanguageId(languageCode));
          }
          await tts.speak(trimmed);
        } catch (_) {
          _failed = true; // graceful text-only fallback from now on
        }
      }(),
    );
    return true;
  }

  @override
  void stop() {
    unawaited(_tts?.stop() ?? Future.value());
  }
}

TextToSpeechService platformTextToSpeech() => NativeTextToSpeechService();