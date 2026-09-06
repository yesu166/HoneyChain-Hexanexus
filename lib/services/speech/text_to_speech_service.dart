import 'text_to_speech_support.dart';

/// Text-to-speech ("Listen") for rural-first UX.
///
/// This is a thin abstraction over the browser's SpeechSynthesis web API so
/// the demo can read out hive guidance, status and alerts aloud on web builds.
/// On platforms without native speech it reports [isSupported] == false and
/// the caller degrades gracefully (the translated text is still shown on
/// screen). The demo never fakes or stubs audio output — if the platform
/// cannot synthesize speech, TTS is simply disabled.
abstract class TextToSpeechService {
  /// Whether speech synthesis is available on this platform.
  bool get isSupported;

  /// Speaks [text]. Returns true when the utterance was queued.
  bool speak(String text);

  /// Stops any utterance currently being spoken.
  void stop();
}

/// Feature-detects and returns the right TTS implementation.
TextToSpeechService createTextToSpeechService() => textToSpeechFactory();
