import 'speech_service.dart';

/// Non-web (native/desktop) fallback: speech recognition is not available,
/// so the demo falls back to the existing manual harvest input.
class UnsupportedSpeechRecognitionService implements SpeechRecognitionService {
  @override
  bool get isSupported => false;
  @override
  String? get lastResult => null;
  @override
  Future<SpeechProbe> probe({String? localeId}) async => const SpeechProbe(
        permission: SpeechPermissionStatus.denied,
        available: false,
        serviceUnavailableReason: 'speech recognition is not available off-device',
      );
  @override
  Stream<String> listen({String? localeId}) => const Stream.empty();
  @override
  void cancel() {}
}

/// Factory used on non-web platforms (no browser Speech API available).
SpeechRecognitionService webSpeechRecognition() =>
    UnsupportedSpeechRecognitionService();