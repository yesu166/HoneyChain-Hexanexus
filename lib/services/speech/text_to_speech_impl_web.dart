import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'text_to_speech_service.dart';

/// Web SpeechSynthesis wrapper ("Listen").
///
/// Feature-detects `speechSynthesis` on the global window. When missing, the
/// demo reports "not supported" and the caller degrades to on-screen text
/// only — the app never fakes or stubs audio output.
class WebTextToSpeechService implements TextToSpeechService {
  static bool? _supported;

  static bool _detect() {
    if (_supported != null) return _supported!;
    try {
      final window = globalContext;
      final synth = window['speechSynthesis'];
      _supported =
          synth != null &&
          (synth.isA<JSObject>() || synth.isA<JSFunction>());
    } catch (_) {
      _supported = false;
    }
    return _supported!;
  }

  // Keep a strong reference to the active utterance so the browser does not
  // garbage-collect it while audio is still playing.
  JSObject? _pendingUtterance;

  @override
  bool get isSupported => _detect();

  @override
  bool speak(String text, {String? languageCode}) {
    if (!_detect() || text.isEmpty) return false;
    try {
      final window = globalContext;
      final synth = window['speechSynthesis'];
      final utteranceCtor = window['SpeechSynthesisUtterance'];
      if (synth == null ||
          !synth.isA<JSObject>() ||
          utteranceCtor == null ||
          !utteranceCtor.isA<JSFunction>()) {
        return false;
      }
      final synthObj = synth as JSObject;
      final ssu = utteranceCtor as JSFunction;
      // A previous utterance may still be queued — read the reference and
      // cancel it before queueing a new one.
      if (_pendingUtterance != null) {
        _pendingUtterance = null;
        synthObj.callMethod('cancel'.toJS);
      }
      final utterance = ssu.callAsConstructor<JSObject>();
      utterance['text'] = text.toJS;
      utterance['lang'] = (languageCode == null || languageCode.isEmpty
              ? 'en-IN'
              : ttsLanguageId(languageCode))
          .toJS;
      utterance['rate'] = 0.95.toJS;
      _pendingUtterance = utterance;
      synthObj.callMethod('speak'.toJS, utterance);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void stop() {
    _pendingUtterance = null;
    if (!_detect()) return;
    try {
      final synth = globalContext['speechSynthesis'];
      if (synth != null && synth.isA<JSObject>()) {
        (synth as JSObject).callMethod('cancel'.toJS);
      }
    } catch (_) {
      // Stopping is best-effort on unsupported browsers.
    }
  }
}

TextToSpeechService webTextToSpeech() => WebTextToSpeechService();

/// Platform factory name used by [textToSpeechFactory].
TextToSpeechService platformTextToSpeech() => WebTextToSpeechService();