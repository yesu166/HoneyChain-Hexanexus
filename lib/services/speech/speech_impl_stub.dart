import 'speech_service.dart';

/// Non-web (native/desktop) fallback: speech recognition is not available,
/// so the demo falls back to the existing manual harvest input.
class UnsupportedSpeechRecognitionService implements SpeechRecognitionService {
  @override
  bool get isSupported => false;
  @override
  String? get lastResult => null;
  @override
  Stream<String> listen() => const Stream.empty();
  @override
  void cancel() {}
}

/// Factory used on non-web platforms (no browser Speech API available).
SpeechRecognitionService webSpeechRecognition() =>
    UnsupportedSpeechRecognitionService();