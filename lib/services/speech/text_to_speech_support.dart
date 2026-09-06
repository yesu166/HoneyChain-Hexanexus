import 'text_to_speech_service.dart';
import 'text_to_speech_impl_web.dart'
    if (dart.library.io) 'text_to_speech_impl_stub.dart';

/// Returns the TTS implementation for the current platform.
/// Web builds use the browser SpeechSynthesis API; native/desktop builds
/// report unsupported so callers show the text without narration.
TextToSpeechService textToSpeechFactory() => webTextToSpeech();
