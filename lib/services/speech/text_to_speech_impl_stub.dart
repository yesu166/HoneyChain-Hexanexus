import 'text_to_speech_service.dart';

/// Non-web (native/desktop) fallback: browser SpeechSynthesis is unavailable,
/// so TTS reports unsupported and callers show the text without narration.
class UnsupportedTextToSpeechService implements TextToSpeechService {
  @override
  bool get isSupported => false;

  @override
  bool speak(String text) => false;

  @override
  void stop() {}
}

/// Factory used on non-web platforms.
TextToSpeechService webTextToSpeech() => UnsupportedTextToSpeechService();