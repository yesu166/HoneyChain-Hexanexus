import 'text_to_speech_service.dart';
import 'text_to_speech_impl_web.dart'
    if (dart.library.io) 'text_to_speech_impl_io.dart';

/// Returns the TTS implementation for the current platform.
/// Web builds use the browser SpeechSynthesis API; Android/iOS builds use the
/// native `flutter_tts` plugin.
TextToSpeechService textToSpeechFactory() => platformTextToSpeech();