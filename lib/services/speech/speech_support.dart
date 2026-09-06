import 'speech_service.dart';
import 'speech_impl_web.dart' if (dart.library.io) 'speech_impl_stub.dart';

/// Returns the speech recognition implementation for the current platform.
/// Web builds use a Web Speech API wrapper; native/desktop builds report
/// unsupported so the manual harvest fallback is used.
SpeechRecognitionService speechRecognitionFactory() => webSpeechRecognition();