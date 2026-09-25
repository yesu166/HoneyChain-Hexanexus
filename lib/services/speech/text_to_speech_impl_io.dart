import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'text_to_speech_service.dart';

/// Native (Android/iOS) text-to-speech backed by `flutter_tts`.
///
/// Uses the installed system TTS engine and requests the app's current
/// language (Tamil/English/etc.) where the engine provides it. If the language
/// is not installed the engine's default voice is used rather than silently
/// disabling speech. If the engine is missing entirely the caller falls back
/// to showing text — audio is never faked.
class NativeTextToSpeechService implements TextToSpeechService {
  FlutterTts? _tts;
  bool _engineUnavailable = false;

  @override
  bool get isSupported => !_engineUnavailable;

  /// Ordered candidate locales for a language: locale+region first, then the
  /// bare language code the engine may know as a fallback (e.g. "hi-IN" -> "hi").
  List<String> _candidatesFor(String languageCode) {
    final locale = ttsLanguageId(languageCode);
    final bare = locale.split('-').first;
    return bare == locale ? [locale] : [locale, bare];
  }

  @override
  bool speak(String text, {String? languageCode}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _engineUnavailable) return false;
    final tts = _tts ??= FlutterTts();
    // Best effort: keep the async work contained so a missing engine or a
    // missing plugin channel (tests/desktop) never breaks the caller.
    unawaited(
      _speak(tts, trimmed, languageCode),
    );
    return true;
  }

  Future<void> _speak(FlutterTts tts, String text, String? languageCode) async {
    try {
      await tts.stop();
      if (languageCode != null && languageCode.isNotEmpty) {
        final fallback = await _selectFirstAvailable(tts, languageCode);
        // When no voice for the chosen language exists, leave the engine's
        // default voice selected so the utterance still plays audibly.
        if (fallback != null) {
          await tts.setLanguage(fallback);
        }
      }
      final result = await tts.speak(text);
      if (result == 0 && !_engineUnavailable) {
        _engineUnavailable = true; // engine present but refused to speak
      }
    } catch (_) {
      // A thrown channel error means speech is unavailable on this device.
      _engineUnavailable = true; // graceful text-only fallback from now on
    }
  }

  /// Picks the first candidate locale the engine reports as available, or null
  /// when none match so the caller can keep the engine's default voice.
  Future<String?> _selectFirstAvailable(
    FlutterTts tts,
    String languageCode,
  ) async {
    for (final candidate in _candidatesFor(languageCode)) {
      try {
        final available = await tts.isLanguageAvailable(candidate);
        if (available == 1) return candidate;
      } catch (_) {
        // Engine without availability probing: optimistically use the full
        // locale id rather than giving up on the requested language.
        return _candidatesFor(languageCode).first;
      }
    }
    return null;
  }

  @override
  void stop() {
    unawaited(_tts?.stop() ?? Future.value());
  }
}

TextToSpeechService platformTextToSpeech() => NativeTextToSpeechService();