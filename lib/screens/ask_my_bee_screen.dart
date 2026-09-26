import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../core/api/api_config.dart';
import '../data/honeychain_store.dart';
import '../l10n/app_strings.dart';
import '../services/api_token_store.dart';
import '../services/ask_my_bee/ask_my_bee_api.dart';
import '../services/ask_my_bee/ask_my_bee_controller.dart';
import '../services/speech/speech_service.dart';
import '../services/speech/speech_text.dart';
import '../services/speech/text_to_speech_service.dart';
import '../theme/app_theme.dart';
import '../widgets/markdown_text.dart';
import '../widgets/section_label.dart';

/// Ask My Bee — the single voice/text assistant for HoneyChain.
///
/// One unified screen: type, speak or tap a suggestion, and the assistant
/// answers through the HoneyChain backend (FastAPI → Gemini → owned hive
/// tools). The microphone is just one input control next to the text field —
/// there is no separate "Voice Harvest" mode and no giant microphone.
///
/// This screen never contains AI credentials: no Gemini key, no Supabase
/// service-role key, no backend secret. It only talks to the authenticated
/// FastAPI backend.
class AskMyBeeScreen extends StatefulWidget {
  const AskMyBeeScreen({
    super.key,
    this.controller,
    this.speech,
    this.tts,
  });

  /// Injectable Ask My Bee controller (widget tests / previews). When null the
  /// screen builds a real controller backed by the FastAPI backend (only when
  /// an API base URL was compiled in; otherwise Ask My Bee reports offline).
  final AskMyBeeController? controller;

  /// Injectable speech recognizer (tests). Defaults to the platform one.
  final SpeechRecognitionService? speech;

  /// Injectable TTS (tests). Defaults to the platform one.
  final TextToSpeechService? tts;

  @override
  State<AskMyBeeScreen> createState() => _AskMyBeeScreenState();
}

class _AskMyBeeScreenState extends State<AskMyBeeScreen> {
  late final AskMyBeeController _controller;
  late final SpeechRecognitionService _speech;
  late final TextToSpeechService _tts;

  final TextEditingController _askText = TextEditingController();
  final ScrollController _askScroll = ScrollController();
  StreamSubscription<String>? _askSub;
  String _speechPreview = '';
  String? _lastSpoken;
  SpeechProbe? _speechProbe;
  bool _micExplainerShown = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? AskMyBeeController(_defaultApiIfConfigured());
    _speech = widget.speech ?? createSpeechRecognitionService();
    _tts = widget.tts ?? createTextToSpeechService();
    _controller.addListener(_onAssistantChange);
    if (widget.controller == null) {
      unawaited(_controller.refreshStatus());
    }
  }

  /// Best-effort backend client. null when no API base URL compiled in — then
  /// Ask My Bee reports it needs internet (offline-first workflows still work).
  AskMyBeeApi? _defaultApiIfConfigured() {
    if (!ApiConfig.isConfigured) return null;
    return AskMyBeeHttpApi(
      ApiClient(
        tokenProvider: () => ApiTokenStore.instance.token,
        timeout: const Duration(seconds: 60),
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onAssistantChange);
    if (widget.controller == null) {
      _controller.dispose();
    }
    _speech.cancel();
    _askSub?.cancel();
    _askText.dispose();
    _askScroll.dispose();
    _tts.stop();
    super.dispose();
  }

  /// Speaks the reply (with Markdown markers stripped so asterisks and hashes
  /// are never read aloud) and keeps the chat scrolled to the bottom.
  void _onAssistantChange() {
    final entries = _controller.entries;
    if (entries.isNotEmpty) {
      final last = entries.last;
      if (!last.isUser && last.content != _lastSpoken && _tts.isSupported) {
        _lastSpoken = last.content;
        final spoken = sanitizeForSpeech(last.content).trim();
        _tts.speak(
          spoken.isEmpty ? last.content : spoken,
          languageCode: HoneyChainStore.instance.language,
        );
      }
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_askScroll.hasClients) return;
      _askScroll.jumpTo(_askScroll.position.maxScrollExtent);
    });
  }

  String? get _lastUserText {
    for (final entry in _controller.entries.reversed) {
      if (entry.isUser) return entry.content;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('ask.title'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
        actions: [
          _languageButton(store),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final entries = _controller.entries;
          final busy = _controller.busy;
          final conf = _controller.awaitingConfirmation;
          return Column(
            children: [
              if (_controller.offline) _offlineBanner(store),
              if (_controller.backendDisabled) _noticeBanner(store),
              Expanded(
                child: entries.isEmpty && !busy && !conf
                    ? _askEmptyState(store)
                    : _askMessageList(store, entries),
              ),
              if (conf) _confirmationCard(store),
              if (_controller.state == AskMyBeeState.listening)
                _speechPreviewRow(store),
              _inputBar(store, busy),
            ],
          );
        },
      ),
    );
  }

  Widget _languageButton(HoneyChainStore store) {
    return PopupMenuButton<String>(
      tooltip: store.tr('prompt.language'),
      icon: const Icon(Icons.translate_rounded, color: AppTheme.orangeDark),
      onSelected: (code) {
        store.setLanguage(code);
        // Re-render UI text and switch the chat/TTS target language now.
        if (mounted) setState(() {});
      },
      itemBuilder: (context) => [
        for (final lang in AppLanguages.all)
          PopupMenuItem(
            value: lang.code,
            child: Row(
              children: [
                Icon(
                  store.currentLang == lang
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: store.currentLang == lang
                      ? AppTheme.orangeDark
                      : AppTheme.inkFaint,
                ),
                const SizedBox(width: 10),
                Text(
                  lang.nativeName,
                  style: TextStyle(
                    fontWeight:
                        store.currentLang == lang ? FontWeight.w800 : FontWeight.w600,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _offlineBanner(HoneyChainStore store) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.redSoft,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppTheme.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.tr('ask.offline'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  store.tr('ask.offline.saved'),
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_controller.refreshStatus()),
            child: Text(
              store.tr('ask.retry'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noticeBanner(HoneyChainStore store) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.orangeSoft,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: AppTheme.orangeDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              store.tr('ask.not.configured'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _askEmptyState(HoneyChainStore store) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppTheme.orangeSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: AppTheme.orangeDark,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            store.tr('ask.title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            store.tr('ask.empty.body'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.inkSoft),
          ),
        ),
        const SizedBox(height: 24),
        SectionLabel(store.tr('ask.suggestions')),
        const SizedBox(height: 10),
        _suggestion(store.tr('ask.suggestion.hives'), Icons.home_work_outlined),
        _suggestion(store.tr('ask.suggestion.hive.status'), Icons.trending_up_rounded),
        _suggestion(store.tr('ask.suggestion.harvests'), Icons.inventory_2_outlined),
        _suggestion(store.tr('ask.suggestion.health'), Icons.health_and_safety_outlined),
        _suggestion(store.tr('ask.suggestion.inspection'), Icons.rule_rounded),
        _suggestion(store.tr('ask.suggestion.treatment'), Icons.medication_outlined),
      ],
    );
  }

  Widget _suggestion(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        child: InkWell(
          borderRadius: AppTheme.radiusCard,
          onTap: () => _sendText(label),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.orangeDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 18, color: AppTheme.inkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _askMessageList(HoneyChainStore store, List<AskChatEntry> entries) {
    return ListView(
      controller: _askScroll,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        for (final entry in entries) ...[
          if (entry.isUser)
            _userBubble(entry.content)
          else ...[
            _assistantBubble(store, entry),
            const SizedBox(height: 10),
          ],
        ],
        if (_controller.state == AskMyBeeState.error)
          _errorCard(store, _controller.lastError),
        if (entries.isNotEmpty && _controller.busy) _typingRow(store),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: Text(
                store.tr('ask.empty.body'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
              ),
            ),
          ),
      ],
    );
  }

  Widget _userBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.orange,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.35),
        ),
      ),
    );
  }

  Widget _assistantBubble(HoneyChainStore store, AskChatEntry entry) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              store.tr('ask.assistant.label'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppTheme.honeyDark,
              ),
            ),
            const SizedBox(height: 4),
            MarkdownText(
              entry.content,
              style:
                  const TextStyle(fontSize: 14, color: AppTheme.ink, height: 1.4),
            ),
            if (entry.toolCount > 0) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.build_rounded, size: 13, color: AppTheme.orangeDark),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      store.tr('ask.tools.used').replaceFirst('{n}', '${entry.toolCount}'),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _typingRow(HoneyChainStore store) {
    final label = switch (_controller.state) {
      AskMyBeeState.toolExecuting => store.tr('ask.tool.executing'),
      AskMyBeeState.responding => store.tr('ask.responding'),
      _ => store.tr('ask.thinking'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.orangeDark),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkSoft,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(HoneyChainStore store, String? message) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: AppTheme.redSoft,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message ?? store.tr('ask.error'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: _controller.busy ? null : _retryLast,
            child: Text(
              store.tr('ask.retry'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.red,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Re-sends the last failed user message (recovery from offline/rate limit/
  /// server errors) without re-typing it or duplicating the bubble.
  void _retryLast() {
    if (_lastUserText == null || _controller.busy) return;
    unawaited(_controller.resendLast());
  }

  Widget _confirmationCard(HoneyChainStore store) {
    final entries = _controller.entries;
    final action = entries.isNotEmpty ? entries.last.content : '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardWarm,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.honeyGold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_outlined, size: 20, color: AppTheme.honeyDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  store.tr('ask.confirm.title'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            action,
            style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.ink),
          ),
          const SizedBox(height: 6),
          Text(
            store.tr('ask.confirm.note'),
            style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _controller.busy
                      ? null
                      : () => unawaited(_controller.confirmAction()),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(store.tr('ask.confirm.yes')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _controller.busy
                      ? null
                      : () => unawaited(_controller.declineAction()),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(store.tr('ask.confirm.no')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _speechPreviewRow(HoneyChainStore store) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.greenSoft,
        borderRadius: AppTheme.radiusField,
        border: Border.all(color: AppTheme.green),
      ),
      child: Row(
        children: [
          const Icon(Icons.mic_rounded, color: AppTheme.greenDark, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _speechPreview.isEmpty
                  ? store.tr('ask.listening')
                  : '"$_speechPreview"',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.ink,
              ),
            ),
          ),
          IconButton(
            onPressed: () => unawaited(_toggleAskListen()),
            icon: const Icon(Icons.stop_rounded, color: AppTheme.red),
            visualDensity: VisualDensity.compact,
            tooltip: store.tr('ask.mic.cancel'),
          ),
        ],
      ),
    );
  }

  Widget _inputBar(HoneyChainStore store, bool busy) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: busy ? null : () => unawaited(_toggleAskListen()),
              onLongPress: busy
                  ? null
                  : () => unawaited(_speech
                          .probe(localeId: speechLocaleId(store.language))
                          .then((p) {
                        if (mounted) {
                          setState(() => _speechProbe = p);
                          _openVoiceDiagnostics(store);
                        }
                      })),
              style: IconButton.styleFrom(
                backgroundColor:
                    _controller.state == AskMyBeeState.listening
                        ? AppTheme.red
                        : AppTheme.orangeSoft,
                foregroundColor:
                    _controller.state == AskMyBeeState.listening
                        ? Colors.white
                        : AppTheme.orangeDark,
              ),
              icon: Icon(
                _controller.state == AskMyBeeState.listening
                    ? Icons.stop_rounded
                    : Icons.mic_rounded,
              ),
              tooltip: store.tr('ask.mic.cancel'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _askText,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: store.tr('ask.placeholder'),
                  filled: true,
                  fillColor: AppTheme.card,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: AppTheme.radiusField,
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppTheme.radiusField,
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppTheme.radiusField,
                    borderSide: const BorderSide(color: AppTheme.orange, width: 1.6),
                  ),
                ),
                onSubmitted: (_) => _sendText(_askText.text),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: busy ? null : () => _sendText(_askText.text),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.orange,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send_rounded),
              tooltip: store.tr('ask.send'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _askText.clear();
    _speech.cancel();
    await _controller.setListening(false);
    setState(() => _speechPreview = '');
    await _controller.send(trimmed);
  }

  Future<void> _toggleAskListen() async {
    final controller = _controller;
    if (controller.state == AskMyBeeState.listening) {
      _speech.cancel();
      await controller.setListening(false);
      if (mounted) setState(() => _speechPreview = '');
      return;
    }
    if (!_speech.isSupported) {
      _showSpeechMessage(HoneyChainStore.instance.tr('ask.mic.unavailable'));
      return;
    }
    // Fresh permission/locale reality check (never fires an OS prompt itself).
    final store = HoneyChainStore.instance;
    final probe = await _speech.probe(localeId: speechLocaleId(store.language));
    if (mounted) setState(() => _speechProbe = probe);

    switch (probe.permission) {
      case SpeechPermissionStatus.permanentlyDenied:
        _openPermanentDeniedDialog(store);
        return;
      case SpeechPermissionStatus.denied:
        _showSpeechMessage(
          store.tr('ask.mic.permission'),
          withRetry: true,
          retryAction: () => unawaited(_toggleAskListen()),
        );
        return;
      case SpeechPermissionStatus.unknown:
        // First use: explain, then start listening (the OS prompt fires from
        // the [listen] call itself, right after this explainer).
        if (!_micExplainerShown) {
          _micExplainerShown = true;
          final allowed = await _showMicExplainer(store);
          if (!(allowed ?? false)) {
            if (mounted) setState(() => _micExplainerShown = false);
            return;
          }
        }
        break;
      case SpeechPermissionStatus.granted:
        break;
    }

    if (mounted && !probe.available) {
      _showSpeechMessage(
        probe.serviceUnavailableReason.isEmpty
            ? store.tr('ask.mic.unavailable')
            : store.tr('ask.mic.unavailable'),
      );
      return;
    }
    if (mounted) {
      final fallback = probe.localeFallbackMessage;
      if (fallback.isNotEmpty && probe.effectiveLocale.isNotEmpty) {
        _showInfoMessage(
          store
              .tr('ask.mic.locale.using')
              .replaceFirst('{locale}', probe.effectiveLocale),
        );
      }
    }

    // Do not capture a reply that is still playing while the mic opens.
    _tts.stop();
    await controller.setListening(true);
    if (!mounted) return;
    setState(() => _speechPreview = '');
    _startAskSpeech();
  }

  Future<bool?> _showMicExplainer(HoneyChainStore store) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(store.tr('ask.mic.explain.title')),
        content: Text(store.tr('ask.mic.explain.body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(store.tr('ask.mic.explain.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(store.tr('ask.mic.explain.allow')),
          ),
        ],
      ),
    );
  }

  void _openPermanentDeniedDialog(HoneyChainStore store) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(store.tr('ask.mic.permanent.title')),
        content: Text(store.tr('ask.mic.permanent.body')),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(store.tr('ask.mic.permanent.ok')),
          ),
        ],
      ),
    );
  }

  /// Long-press on the microphone — device diagnostics for troubleshooting.
  void _openVoiceDiagnostics(HoneyChainStore store) {
    final probe = _speechProbe;
    final permissionLabel = switch (probe?.permission) {
      SpeechPermissionStatus.granted => store.tr('ask.mic.status.granted'),
      SpeechPermissionStatus.denied => store.tr('ask.mic.status.denied'),
      SpeechPermissionStatus.permanentlyDenied => store.tr('ask.mic.status.permanent'),
      _ => store.tr('ask.mic.status.unknown'),
    };
    final engine = probe?.available == true
        ? store.tr('ask.mic.status.available')
        : probe?.available == false
            ? store.tr('ask.mic.status.unavailable')
            : store.tr('ask.mic.status.unknown');
    final supported = (probe?.supportedLocales ?? const <String>[]);
    final supportedText = supported.isEmpty ? '—' : supported.join(', ');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(store.tr('ask.diag.title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(store
                  .tr('ask.diag.permission')
                  .replaceFirst('{status}', permissionLabel)),
              const SizedBox(height: 6),
              Text(store.tr('ask.diag.engine').replaceFirst('{status}', engine)),
              const SizedBox(height: 6),
              Text(store
                  .tr('ask.diag.requested')
                  .replaceFirst('{locale}', probe?.requestedLocale.isEmpty == true
                      ? '—'
                      : (probe?.requestedLocale ?? '—'))),
              const SizedBox(height: 6),
              Text(store
                  .tr('ask.diag.effective')
                  .replaceFirst('{locale}', probe?.effectiveLocale.isEmpty == true
                      ? '—'
                      : (probe?.effectiveLocale ?? '—'))),
              const SizedBox(height: 6),
              Text(store
                  .tr('ask.diag.supported')
                  .replaceFirst('{list}', supportedText)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(store.tr('ask.diag.ok')),
          ),
        ],
      ),
    );
  }

  void _startAskSpeech() {
    _askSub?.cancel();
    final store = HoneyChainStore.instance;
    final sub = _speech
        .listen(localeId: speechLocaleId(store.language))
        .listen(
          (text) {
            if (!mounted) return;
            setState(() => _speechPreview = text);
          },
          onError: (Object error) {
            if (!mounted) return;
            unawaited(_controller.setListening(false));
            if (error is SpeechFailure) {
              final store = HoneyChainStore.instance;
              switch (error.kind) {
                case SpeechFailureKind.permissionDenied:
                  _showSpeechMessage(
                    store.tr('ask.mic.permission'),
                    withRetry: true,
                    retryAction: () => unawaited(_toggleAskListen()),
                  );
                case SpeechFailureKind.permissionPermanentlyDenied:
                  _openPermanentDeniedDialog(store);
                case SpeechFailureKind.unavailable:
                  _showSpeechMessage(store.tr('ask.mic.unavailable'));
                case SpeechFailureKind.localeUnsupported:
                  _showSpeechMessage(store.tr('ask.mic.locale.unavailable'));
                case SpeechFailureKind.noMatch:
                  _showSpeechMessage(
                    store.tr('ask.mic.no.speech'),
                    withRetry: true,
                    retryAction: () => unawaited(_toggleAskListen()),
                  );
                case SpeechFailureKind.timeout:
                  _showSpeechMessage(
                    store.tr('ask.mic.timeout'),
                    withRetry: true,
                    retryAction: () => unawaited(_toggleAskListen()),
                  );
                case SpeechFailureKind.busy:
                  _showSpeechMessage(store.tr('ask.mic.busy'));
                case SpeechFailureKind.audioInputFailure:
                  _showSpeechMessage(store.tr('ask.mic.audio'));
                case SpeechFailureKind.network:
                  _showSpeechMessage(store.tr('ask.mic.network'));
                case SpeechFailureKind.serviceError:
                  _showSpeechMessage(
                    store.tr('ask.mic.service'),
                    withRetry: true,
                    retryAction: () => unawaited(_toggleAskListen()),
                  );
                case SpeechFailureKind.other:
                  _showSpeechMessage(store.tr('ask.mic.no.speech'));
              }
            } else {
              _showSpeechMessage(store.tr('ask.mic.no.speech'));
            }
          },
          onDone: () {
            if (!mounted) return;
            unawaited(_controller.setListening(false));
            final preview = _speechPreview.trim();
            if (preview.isNotEmpty) {
              unawaited(_sendText(preview));
            } else {
              _showSpeechMessage(
                HoneyChainStore.instance.tr('ask.mic.no.speech'),
                withRetry: true,
                retryAction: () => unawaited(_toggleAskListen()),
              );
            }
          },
          cancelOnError: true,
        );
    _askSub = sub;
  }

  void _showInfoMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.ink,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSpeechMessage(
    String message, {
    bool withRetry = false,
    VoidCallback? retryAction,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.orangeDark,
        behavior: SnackBarBehavior.floating,
        action: withRetry && retryAction != null
            ? SnackBarAction(
                label: HoneyChainStore.instance.tr('ask.mic.retry'),
                textColor: Colors.white,
                onPressed: retryAction,
              )
            : null,
      ),
    );
  }
}