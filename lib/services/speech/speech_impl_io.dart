import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart' as ste;

import 'speech_service.dart';

/// Native (Android/iOS) speech recognition backed by `speech_to_text`.
///
/// The recognizer reports unavailability / permission problems as [SpeechFailure]
/// errors on the [listen] stream (mapped from the plugin's platform errors), and
/// callers fall back to typing — audio is never simulated.
class NativeSpeechRecognitionService implements SpeechRecognitionService {
  final stt.SpeechToText _stt = stt.SpeechToText();

  /// Cached engine state; `true` once a successful initialize happened.
  bool? _initWorked;

  /// How many times the OS microphone permission was actually requested.
  int _initAttempts = 0;

  bool _activeSession = false;
  String? _last;
  StreamController<String>? _controller;
  List<String> _cachedLocaleIds = const [];

  @override
  bool get isSupported => true; // plugin linked; runtime failures surface on listen

  @override
  String? get lastResult => _last;

  // ------------------------------------------------------------------ engine

  Future<bool> _ensureInitialized() async {
    if (_initWorked == true) return true;
    _initAttempts++;
    try {
      _initWorked = await _stt.initialize(
        onError: _onError,
        onStatus: _onStatus,
        // Generous so slow starters still produce a final result instead of
        // the UI claiming "no speech" for an engine that was simply catching
        // up. Setting it <= 50ms disables the check entirely.
        finalTimeout: const Duration(milliseconds: 3500),
        debugLogging: false,
      );
    } catch (_) {
      _initWorked = false;
    }
    return _initWorked ?? false;
  }

  Future<bool> _hasPermissionOrFalse() async {
    try {
      return await _stt.hasPermission;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- locales

  Future<List<String>> _localeIds() async {
    if (_cachedLocaleIds.isNotEmpty) return _cachedLocaleIds;
    try {
      _cachedLocaleIds = [
        for (final l in await _stt.locales()) l.localeId,
      ];
    } catch (_) {
      _cachedLocaleIds = const [];
    }
    return _cachedLocaleIds;
  }

  String _normalized(String s) => s.toLowerCase().replaceAll('_', '-');

  /// Resolves the recognizer locale to use: exact match first, then a prefix
  /// match on the language (ta-IN requested -> ta-IN/ta installed), then the
  /// lang alone, then English, then the first supported locale.
  Future<({String effective, String fallbackMessage})> _resolveLocale(
    String? requested,
  ) async {
    final ids = await _localeIds();
    if (ids.isEmpty) return (effective: '', fallbackMessage: '');
    String system = '';
    try {
      system = _normalized((await _stt.systemLocale())?.localeId ?? '');
    } catch (_) {}

    final req = (requested ?? '').trim();
    if (req.isEmpty) {
      final fallback = (system.isNotEmpty
              ? ids.where((l) => _normalized(l) == system).firstOrNull
              : null) ??
          ids.first;
      return (effective: fallback, fallbackMessage: '');
    }
    final lang = req.split('-').first.toLowerCase();
    String? pick;
    for (final l in ids) {
      if (_normalized(l) == _normalized(req)) {
        pick = l;
        break;
      }
    }
    if (pick == null) {
      for (final l in ids) {
        if (_normalized(l).startsWith('$lang-')) {
          pick = l;
          break;
        }
      }
    }
    if (pick == null) {
      for (final l in ids) {
        if (_normalized(l).startsWith(lang)) {
          pick = l;
          break;
        }
      }
    }
    if (pick == null) {
      final english = ids.where((l) => _normalized(l).startsWith('en')).firstOrNull;
      pick = english ?? ids.first;
    }
    if (_normalized(pick) != _normalized(req)) {
      return (effective: pick, fallbackMessage: '$req → $pick');
    }
    return (effective: pick, fallbackMessage: '');
  }

  // ------------------------------------------------------------------ probe

  @override
  Future<SpeechProbe> probe({String? localeId}) async {
    final requested = (localeId ?? '').trim();
    final hasPermission = await _hasPermissionOrFalse();

    final SpeechPermissionStatus permission;
    if (hasPermission) {
      permission = SpeechPermissionStatus.granted;
    } else if (_initAttempts == 0) {
      // Never prompted yet — the microphone dialog only fires on [listen],
      // after the UI has shown its own explainer.
      permission = SpeechPermissionStatus.unknown;
    } else if (_initAttempts >= 2) {
      // Serial denied requests: the OS is done re-prompting. Only a visit to
      // system Settings can restore voice input now.
      permission = SpeechPermissionStatus.permanentlyDenied;
    } else {
      permission = SpeechPermissionStatus.denied;
    }

    bool available = false;
    String reason = '';
    if (hasPermission) {
      available = await _ensureInitialized();
      if (!available) {
        reason = 'speech recognition did not start on this device';
      }
    } else if (_initWorked == true) {
      available = true; // engine bridged earlier; only permission is missing
    } else {
      reason =
          'microphone permission not granted — HoneyChain will ask when you speak';
    }

    String effective = '';
    String fallbackMessage = '';
    List<String> supported = const [];
    if (available) {
      final resolved = await _resolveLocale(requested.isEmpty ? null : requested);
      effective = resolved.effective;
      fallbackMessage = resolved.fallbackMessage;
      supported = await _localeIds();
    }

    return SpeechProbe(
      permission: permission,
      available: available,
      serviceUnavailableReason: reason,
      requestedLocale: requested,
      effectiveLocale: effective,
      localeFallbackMessage: fallbackMessage,
      supportedLocales: supported,
    );
  }

  // ---------------------------------------------------------------- events

  void _onError(ste.SpeechRecognitionError error) {
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      controller.addError(SpeechFailure(_kindFor(error.errorMsg), error.errorMsg));
    }
    // Permanent errors (and every permission refusal) end the session so the
    // UI can react; a later tap starts a fresh one.
    if (error.permanent ||
        error.errorMsg.toLowerCase().contains('permission')) {
      _finishSession();
    }
  }

  void _onStatus(String status) {
    // 'done'/'notListening' means the utterance ended. Always finalize —
    // even when a partial result was already delivered — so the stream
    // actually closes and the UI stops showing a dead "Listening" state.
    if (status == stt.SpeechToText.doneStatus ||
        status == stt.SpeechToText.notListeningStatus) {
      _finishSession();
    }
  }

  static SpeechFailureKind _kindFor(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('permission')) return SpeechFailureKind.permissionDenied;
    if (m.contains('language_not_supported') ||
        m.contains('language_unavailable')) {
      return SpeechFailureKind.localeUnsupported;
    }
    if (m.contains('no_match') || m.contains('no speech') || m.contains('no_result')) {
      return SpeechFailureKind.noMatch;
    }
    if (m.contains('network')) return SpeechFailureKind.network;
    if (m.contains('too_many') || m.contains('busy')) return SpeechFailureKind.busy;
    if (m.contains('audio')) return SpeechFailureKind.audioInputFailure;
    if (m.contains('timeout')) return SpeechFailureKind.timeout;
    if (m.contains('server') || m.contains('client') || m.contains('retry')) {
      return SpeechFailureKind.serviceError;
    }
    if (m.contains('unavailable') ||
        m.contains('not_available') ||
        m.contains('service') ||
        m.contains('disabled')) {
      return SpeechFailureKind.unavailable;
    }
    return SpeechFailureKind.other;
  }

  // ---------------------------------------------------------------- listen

  @override
  Stream<String> listen({String? localeId}) {
    if (_activeSession) {
      final busy = StreamController<String>();
      busy.addError(const SpeechFailure(
        SpeechFailureKind.busy,
        'speech recognition is already active',
      ));
      unawaited(busy.close());
      return busy.stream;
    }

    _last = null;
    final requested = (localeId ?? '').trim();
    final controller = StreamController<String>();
    _controller = controller;
    _activeSession = true;

    unawaited(() async {
      final ok = await _ensureInitialized();
      if (!identical(_controller, controller)) return; // cancelled meanwhile
      if (!ok) {
        final hasPerm = await _hasPermissionOrFalse();
        _activeSession = false;
        if (!controller.isClosed) {
          controller.addError(SpeechFailure(
            hasPerm
                ? SpeechFailureKind.unavailable
                : SpeechFailureKind.permissionDenied,
            'engine not available',
          ));
          await controller.close();
        }
        return;
      }

      final resolved =
          await _resolveLocale(requested.isEmpty ? null : requested);
      final effective = resolved.effective.isEmpty ? null : resolved.effective;
      try {
        await _stt.listen(
          listenOptions: stt.SpeechListenOptions(
            localeId: effective,
            partialResults: true,
            listenMode: stt.ListenMode.dictation,
            cancelOnError: false,
            listenFor: const Duration(seconds: 45),
            pauseFor: const Duration(seconds: 6),
          ),
          onResult: (result) {
            if (!identical(_controller, controller)) return;
            final text = result.recognizedWords.trim();
            if (text.isNotEmpty) {
              _last = text;
              if (!controller.isClosed) controller.add(text);
            }
            if (result.finalResult) _finishSession();
          },
        );
      } on stt.ListenFailedException {
        _activeSession = false;
        if (!controller.isClosed) {
          controller.addError(const SpeechFailure(
            SpeechFailureKind.serviceError,
            'speech recognition service rejected the request',
          ));
          await controller.close();
        }
      } catch (e) {
        _activeSession = false;
        if (!controller.isClosed) {
          final lowered = e.toString().toLowerCase();
          controller.addError(SpeechFailure(
            lowered.contains('permission')
                ? SpeechFailureKind.permissionDenied
                : SpeechFailureKind.serviceError,
            'listen failed',
          ));
          await controller.close();
        }
      }
    }());

    return controller.stream;
  }

  /// Ends the current session, releases the microphone and closes the stream.
  void _finishSession() {
    final controller = _controller;
    final wasActive = _activeSession;
    _activeSession = false;
    _controller = null;
    if (wasActive) unawaited(_stt.cancel());
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }

  @override
  void cancel() => _finishSession();
}

SpeechRecognitionService platformSpeechRecognition() =>
    NativeSpeechRecognitionService();