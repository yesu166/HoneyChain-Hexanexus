import 'package:flutter/foundation.dart';

import '../../core/api/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../data/honeychain_store.dart';
import '../../services/connectivity_service.dart';
import 'ask_my_bee_api.dart';

/// Lifecycle of an Ask My Bee interaction.
enum AskMyBeeState {
  /// Nothing is happening — user can type, listen or send.
  idle,

  /// The microphone is recording.
  listening,

  /// A message was sent; the backend/Gemini is producing a reply.
  thinking,

  /// The backend ran validated HoneyChain tools (hives/harvest/health/...).
  toolExecuting,

  /// The backend replied and the reply is being surfaced (rendered / spoken).
  responding,

  /// The last attempt failed; [lastError] carries a user-safe message.
  error,
}

/// One bubble shown in the conversation.
class AskChatEntry {
  const AskChatEntry({
    required this.role,
    required this.content,
    this.toolCount = 0,
  });

  final String role; // 'user' | 'assistant'
  final String content;

  /// How many HoneyChain tools the backend executed for this assistant turn.
  final int toolCount;

  bool get isUser => role == 'user';
}

/// Lightweight controller for the Ask My Bee conversation.
///
/// - accepts typed OR recognized speech text and sends it to the backend
/// - exposes assistant replies + a user-safe error message
/// - prevents duplicate submissions while a request is in flight
/// - supports cancellation (stale responses are dropped)
/// - keeps the current screen/session conversation in [entries]
/// - never calls Supabase or Gemini directly — it only talks through
///   [AskMyBeeApi] which talks to the authenticated FastAPI backend
class AskMyBeeController extends ChangeNotifier {
  AskMyBeeController(
    this._api, {
    String Function(String key)? tr,
    bool Function()? offlineCheck,
  }) : _tr = tr ?? ((key) => HoneyChainStore.instance.tr(key)),
       _offlineCheck =
           offlineCheck ??
           _defaultOfflineCheck;

  final AskMyBeeApi? _api;
  final String Function(String key) _tr;
  final bool Function() _offlineCheck;

  final List<AskChatEntry> _entries = [];
  AskMyBeeState _state = AskMyBeeState.idle;
  String? _lastError;
  int _requestSeq = 0;
  AskBackendStatus? _status;

  /// Conversation bubbles for the current screen/session.
  List<AskChatEntry> get entries => List.unmodifiable(_entries);

  AskMyBeeState get state => _state;

  /// User-safe error text for the ERROR state (offline, rate limited, ...).
  String? get lastError => _lastError;

  /// True while a request is in flight (or being surfaced).
  bool get busy =>
      _state == AskMyBeeState.thinking ||
      _state == AskMyBeeState.toolExecuting ||
      _state == AskMyBeeState.responding;

  /// True when the assistant finished a reply but it is not visible yet.
  bool get showingReply => _state == AskMyBeeState.responding;

  /// Backend `GET /api/v1/ai/status` result, or null before first fetch.
  AskBackendStatus? get backendStatus => _status;

  /// True when the request should not be attempted (no backend compiled in,
  /// or the device currently reports no network). Ask My Bee requires
  /// connectivity — offline HoneyChain workflows are never affected.
  bool get offline {
    if (_api == null) return true;
    return _offlineCheck();
  }

  /// Backend configured but the server answered "Ask My Bee not enabled".
  bool get backendDisabled =>
      _status != null && !_status!.enabled && !_status!.configured;

  /// True when the most recent assistant message is asking the beekeeper to
  /// confirm a write (inspection / treatment / harvest / hive creation).
  ///
  /// The backend only records after the beekeeper confirms in plain language;
  /// this surfaces Confirm/Cancel in the UI so a confirmation is never sent
  /// automatically. The assistant bubble itself shows exactly what would be
  /// recorded (the backend always restates it before asking).
  bool get awaitingConfirmation {
    if (_entries.isEmpty) return false;
    final last = _entries.last;
    if (last.isUser) return false;
    final lower = last.content.toLowerCase();
    return lower.contains('confirm') ||
        lower.contains('shall i') ||
        lower.contains('should i record') ||
        lower.contains('should i log') ||
        lower.contains('shall we confirm');
  }

  // ------------------------------------------------------------------ send

  /// Sends [text] (typed or recognized speech) to the backend.
  ///
  /// Returns true when the message was accepted. Returns false when the
  /// controller is busy (no duplicate submissions) or [text] is empty.
  Future<bool> send(String text) => _send(text, recordUser: true);

  /// Re-sends the last failed user message (offline / rate limit / server
  /// error) without adding a duplicate bubble — the failed message is already
  /// part of the conversation and is simply retried.
  Future<bool> resendLast() {
    for (var i = _entries.length - 1; i >= 0; i--) {
      if (_entries[i].isUser) return _send(_entries[i].content, recordUser: false);
    }
    return Future.value(false);
  }

  Future<bool> _send(String text, {required bool recordUser}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || busy) return false;

    if (offline) {
      _enterError(_tr('ask.offline'));
      return false;
    }

    if (recordUser) {
      _entries.add(AskChatEntry(role: 'user', content: trimmed));
    }
    _setState(AskMyBeeState.thinking);

    final seq = ++_requestSeq;
    try {
      final reply = await _api!.sendChat(
        _entries.map((e) => AskChatMessage(role: e.role, content: e.content)).toList(),
        language: HoneyChainStore.instance.language,
      );
      if (seq != _requestSeq) return false; // cancelled while in flight

      if (reply.toolCount > 0) _setState(AskMyBeeState.toolExecuting);
      _entries.add(
        AskChatEntry(role: 'assistant', content: reply.reply, toolCount: reply.toolCount),
      );
      _setState(AskMyBeeState.responding);
      _setState(AskMyBeeState.idle);
      return true;
    } on ApiException catch (e) {
      if (seq != _requestSeq) return false;
      _enterError(_messageFor(e));
      return false;
    } catch (_) {
      if (seq != _requestSeq) return false;
      _enterError(_tr('ask.error'));
      return false;
    }
  }

  /// Sends the explicit "yes, confirm" for a pending write confirmation.
  Future<bool> confirmAction() => send(_tr('ask.confirm.yes.send'));

  /// Sends the explicit "no, cancel" for a pending write confirmation.
  Future<bool> declineAction() => send(_tr('ask.confirm.no.send'));

  /// Drops any in-flight request (its late response is ignored safely).
  void cancelPending() {
    _requestSeq++;
    if (busy || _state == AskMyBeeState.listening) {
      _setState(AskMyBeeState.idle);
    }
  }

  /// Marks the microphone as on (LISTENING) or off (return to IDLE).
  Future<void> setListening(bool listening) async {
    if (listening && !busy) {
      _setState(AskMyBeeState.listening);
    } else if (!listening) {
      if (_state == AskMyBeeState.listening) _setState(AskMyBeeState.idle);
    }
  }

  /// Clears the current session conversation (new chat on this screen).
  void reset() {
    _requestSeq++;
    _entries.clear();
    _lastError = null;
    _setState(AskMyBeeState.idle);
  }

  /// Fetches `GET /api/v1/ai/status` (best effort, never throws).
  Future<void> refreshStatus() async {
    final api = _api;
    if (api == null) return;
    try {
      _status = await api.fetchStatus();
      notifyListeners();
    } on ApiException {
      // Status is advisory; the chat call itself reports errors.
    }
  }

  // ------------------------------------------------------------------ misc

  static bool _defaultOfflineCheck() {
    if (!ApiConfig.isConfigured) return true;
    return HoneyChainStore.instance.connectivityStatus ==
        ConnectivityStatus.offline;
  }

  void _setState(AskMyBeeState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  void _enterError(String message) {
    _lastError = message;
    _setState(AskMyBeeState.error);
  }

  String _messageFor(ApiException e) {
    if (e.statusCode == 429) return _tr('ask.rate.limited');
    switch (e.kind) {
      case ApiExceptionKind.auth:
      case ApiExceptionKind.forbidden:
        return _tr('ask.unauthorized');
      case ApiExceptionKind.network:
        return _tr('ask.offline');
      case ApiExceptionKind.timeout:
        return _tr('ask.timeout');
      case ApiExceptionKind.validation:
        return e.message.isEmpty ? _tr('ask.error') : e.message;
      case ApiExceptionKind.conflict:
      case ApiExceptionKind.notFound:
      case ApiExceptionKind.server:
      case ApiExceptionKind.unknown:
        return e.message.isEmpty ? _tr('ask.error') : e.message;
    }
  }

  @override
  void dispose() {
    _requestSeq++;
    super.dispose();
  }
}