import 'speech_support.dart';

/// Why a speech recognition attempt failed, so the UI can explain it.
enum SpeechFailureKind {
  /// The OS-level microphone permission is denied (first denial).
  permissionDenied,

  /// The user has denied forever (or the OS will no longer re-prompt);
  /// only a visit to system Settings can restore voice input.
  permissionPermanentlyDenied,

  /// No recognizer engine exists on this device / platform.
  unavailable,

  /// The recognizer exists but has no usable locale for the requested language.
  localeUnsupported,

  /// The recognizer heard nothing (silence / no match).
  noMatch,

  /// The listener started but the utterance never produced text in time.
  timeout,

  /// Another session/app holds the recognizer or microphone.
  busy,

  /// The microphone itself failed (audio error / in use elsewhere).
  audioInputFailure,

  /// Recognition needs a network (server-side recognizer) and there is none.
  network,

  /// The recognizer service crashed or returned an unexpected error.
  serviceError,

  /// Anything else.
  other,
}

/// User-safe speech error delivered through the [SpeechRecognitionService]
/// listen stream's `onError` so callers can degrade instead of crashing.
class SpeechFailure {
  const SpeechFailure(this.kind, [this.message = '']);

  final SpeechFailureKind kind;
  final String message;
}

/// OS microphone permission state (best effort, no prompt fired yet).
enum SpeechPermissionStatus { unknown, granted, denied, permanentlyDenied }

/// Snapshot produced by [SpeechRecognitionService.probe]: what the device
/// actually supports right now. Telling the user the truth (`ta-IN` is not
/// installed, permission is off, no engine) beats pretending voice works.
class SpeechProbe {
  const SpeechProbe({
    this.permission = SpeechPermissionStatus.unknown,
    this.available = false,
    this.serviceUnavailableReason = '',
    this.requestedLocale = '',
    this.effectiveLocale = '',
    this.localeFallbackMessage = '',
    this.supportedLocales = const <String>[],
  });

  final SpeechPermissionStatus permission;

  /// True when the recognizer engine answered (not "configured").
  final bool available;

  /// Human detail when [available] is false.
  final String serviceUnavailableReason;

  /// The locale the app asked for (from the user's language).
  final String requestedLocale;

  /// The locale that will actually be used (resolved, or '' if unresolved).
  final String effectiveLocale;

  /// Non-empty when [effectiveLocale] differs from [requestedLocale] — e.g.
  /// "ta-IN not installed — using en-IN".
  final String localeFallbackMessage;

  /// Raw recognizer locales (ids) where that is reportable.
  final List<String> supportedLocales;
}

/// Access to device speech recognition.
///
/// This is a thin abstraction over the platform recognizer (Web Speech API on
/// web builds, `speech_to_text` on Android/iOS) so the Ask My Bee assistant
/// has one implementation for voice input everywhere. The service never
/// fakes audio: if the platform cannot recognize speech, failures surface as
/// [SpeechFailure] errors on the listen stream (or no result at all).
abstract class SpeechRecognitionService {
  /// Whether speech recognition is likely available on this platform/device.
  /// Runtime failures (permission denied, missing engine) still surface on
  /// the listen stream as [SpeechFailure].
  bool get isSupported;

  /// Concrete text produced by the most recent successful transcription.
  String? get lastResult;

  /// Non-blocking, non-prompting check of what the device supports.
  ///
  /// [probe] never shows an OS dialog: it only reads current permission state
  /// (`hasPermission`), initializes the engine when permission is already
  /// granted, and resolves [effectiveLocale]. The [listen] call (not the
  /// probe) is what triggers the OS microphone prompt on first use, after the
  /// UI has shown its own explainer.
  Future<SpeechProbe> probe({String? localeId});

  /// Starts a single utterance. Yields recognized text (typically incremental
  /// then final) and may emit [SpeechFailure] errors. Callers should listen,
  /// stop via [cancel] and dispose the subscription. When a session is already
  /// active, the returned stream emits a `busy` [SpeechFailure] and closes.
  Stream<String> listen({String? localeId});

  /// Stops an active recognition session.
  void cancel();
}

/// Maps a HoneyChain language code to a recognizer-friendly locale id.
String speechLocaleId(String languageCode) => switch (languageCode) {
      'hi' => 'hi-IN',
      'ta' => 'ta-IN',
      'bn' => 'bn-IN',
      'pa' => 'pa-IN',
      'ml' => 'ml-IN',
      'mr' => 'mr-IN',
      _ => 'en-IN',
    };

/// Feature-detects and returns the right implementation.
SpeechRecognitionService createSpeechRecognitionService() =>
    speechRecognitionFactory();