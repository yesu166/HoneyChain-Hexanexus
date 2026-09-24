import 'speech_service.dart';
import 'speech_impl_web.dart' if (dart.library.io) 'speech_impl_io.dart';

/// Returns the speech recognition implementation for the current platform.
/// Web builds use the browser Web Speech API; Android/iOS builds use the
/// native `speech_to_text` plugin.
SpeechRecognitionService speechRecognitionFactory() =>
    platformSpeechRecognition();