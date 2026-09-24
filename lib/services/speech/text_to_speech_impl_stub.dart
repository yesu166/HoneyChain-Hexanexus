import 'text_to_speech_service.dart';

/// Non-web fallback (desktop test hosts): text-to-speech reports unsupported
/// and callers show the text without narration.
class UnsupportedTextToSpeechService implements TextToSpeechService {
  @override
  bool get isSupported => false;

  @override
  bool speak(String text, {String? languageCode}) => false;

  @override
  void stop() {}
}

/// Factory used on non-web platforms without a TTS engine.
TextToSpeechService webTextToSpeech() => UnsupportedTextToSpeechService();

/// Platform factory name used by [textToSpeechFactory].
TextToSpeechService platformTextToSpeech() => UnsupportedTextToSpeechService();