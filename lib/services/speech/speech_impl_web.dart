import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'speech_service.dart';

/// State shared with the JS callback handlers. These must be top-level so the
/// Dart functions can be exported to JS with `.toJS` (which only supports
/// top-level / static functions).
WebSpeechRecognitionService? gActiveSpeech;
JSObject? gActiveRec;

/// Grab the transcript from the final/only result and hand it to the active
/// service, closing the stream when the utterance is final.
void _onSpeechResult(JSObject event) {
  final svc = gActiveSpeech;
  if (svc == null) return;
  final results = event['results'];
  if (results == null) return;
  final resultsObj = results as JSObject;
  final n = resultsObj['length']?.dartify();
  final count = n is int ? n : 0;
  if (count <= 0) return;
  final last = resultsObj.getProperty((count - 1).toJS);
  if (last == null) return;
  final lastObj = last as JSObject;
  final first = lastObj.getProperty(0.toJS);
  if (first == null) return;
  final firstObj = first as JSObject;
  final transcript = firstObj['transcript']?.dartify() as String? ?? '';
  svc._emit(transcript);
  final isFinal = firstObj['isFinal']?.dartify() as bool? ?? false;
  if (isFinal) svc._close();
}

void _onSpeechError(JSObject _) => gActiveSpeech?._close();

void _onSpeechEnd(JSObject _) => gActiveSpeech?._close();

/// Web Speech API (SpeechRecognition) wrapper for browsers.
///
/// Feature-detects `webkitSpeechRecognition`/`SpeechRecognition`. When the
/// browser does not expose it, [isSupported] is false and the demo falls back
/// to manual input.
class WebSpeechRecognitionService implements SpeechRecognitionService {
  // Keep a reference to the (possibly prefixed) constructor to avoid name
  // collisions in the Dart API surface.
  static JSAny? _ctor;
  String? _last;
  StreamController<String>? _controller;

  static bool _detect() {
    if (_ctor != null) return true;
    // Read the (optionally webkit-prefixed) constructor off the global window
    // object via js_interop_unsafe. This never throws on unsupported browsers;
    // it simply resolves to a friendly null.
    final window = globalContext;
    final webkit = window['webkitSpeechRecognition'];
    final ctor =
        (webkit != null && webkit.isA<JSFunction>())
            ? webkit
            : window['SpeechRecognition'];
    if (ctor != null && ctor.isA<JSFunction>()) {
      _ctor = ctor;
      return true;
    }
    return false;
  }

  @override
  bool get isSupported => _detect();

  @override
  String? get lastResult => _last;

  @override
  Stream<String> listen() {
    _last = null;
    final controller = StreamController<String>();
    _controller = controller;
    gActiveSpeech = this;
    if (!_detect()) {
      scheduleMicrotask(() => controller.close());
      return controller.stream;
    }
    try {
      final ctor = _ctor! as JSFunction;
      final rec = ctor.callAsConstructor<JSObject>();
      gActiveRec = rec;
      rec['interimResults'] = true.toJS;
      rec['lang'] = 'en-IN'.toJS;
      rec['onresult'] = _onSpeechResult.toJS;
      rec['onerror'] = _onSpeechError.toJS;
      rec['onend'] = _onSpeechEnd.toJS;
      rec.callMethod('start'.toJS);
    } catch (_) {
      _close();
    }
    return controller.stream;
  }

  void _emit(String transcript) {
    _last = transcript;
    final c = _controller;
    if (c != null && !c.isClosed) c.add(transcript);
  }

  void _close() {
    gActiveSpeech = null;
    gActiveRec = null;
    final c = _controller;
    _controller = null;
    if (c != null && !c.isClosed) c.close();
  }

  @override
  void cancel() {
    gActiveSpeech = null;
    gActiveRec = null;
    final c = _controller;
    _controller = null;
    if (c != null && !c.isClosed) c.close();
  }
}

SpeechRecognitionService webSpeechRecognition() =>
    WebSpeechRecognitionService();