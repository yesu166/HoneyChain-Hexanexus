import 'speech_support.dart';

/// Access to browser/device speech recognition.
///
/// This is a thin abstraction so the voice-harvest entry can use the Web
/// Speech API when available (browser) and transparently fall back to manual
/// typing everywhere else. The demo never fakes audio processing: if the
/// platform cannot recognize speech, [isSupported] is false and the caller
/// falls back to the existing manual harvest form.
abstract class SpeechRecognitionService {
  /// Whether speech recognition is available on this platform/device.
  bool get isSupported;

  /// Concrete text produced by the most recent successful transcription.
  String? get lastResult;

  /// Starts a single utterance. Returns a stream that yields recognized text
  /// (typically incremental then final). Callers should listen and stop.
  Stream<String> listen();

  /// Stops an active recognition session.
  void cancel();
}

/// Feature-detects and returns the right implementation.
SpeechRecognitionService createSpeechRecognitionService() =>
    speechRecognitionFactory();