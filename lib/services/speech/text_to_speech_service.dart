import 'text_to_speech_support.dart';

/// Text-to-speech ("Listen") for rural-first UX.
///
/// This is a thin abstraction over the platform speech synthesizer (browser
/// SpeechSynthesis on web, `flutter_tts` on Android/iOS). On platforms without
/// native speech it reports [isSupported] == false and the caller degrades
/// gracefully (the text is still shown on screen). The abstraction is kept
/// ready for a future server-side TTS provider. Audio output is never faked —
/// if the platform cannot synthesize speech, TTS is simply disabled.
abstract class TextToSpeechService {
  /// Whether speech synthesis is available on this platform.
  bool get isSupported;

  /// Speaks [text] in [languageCode] ("en", "ta", ...) when provided. Returns
  /// true when the utterance was queued; false when unavailable so callers can
  /// show text-only fallback.
  bool speak(String text, {String? languageCode});

  /// Stops any utterance currently being spoken.
  void stop();
}

/// Maps a HoneyChain language code to a TTS-friendly locale id.
String ttsLanguageId(String languageCode) => switch (languageCode) {
      'hi' => 'hi-IN',
      'ta' => 'ta-IN',
      'bn' => 'bn-IN',
      'pa' => 'pa-IN',
      'ml' => 'ml-IN',
      'mr' => 'mr-IN',
      _ => 'en-IN',
    };

/// Feature-detects and returns the right TTS implementation.
TextToSpeechService createTextToSpeechService() => textToSpeechFactory();