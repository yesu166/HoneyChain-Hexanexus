import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../services/speech/text_to_speech_service.dart';
import '../theme/app_theme.dart';

/// Rural-first "LISTEN" action: reads a status/guidance summary aloud using
/// the platform TTS when available. Always renders the text on screen too, so
/// the feature degrades gracefully on devices without speech synthesis.
class ListenButton extends StatelessWidget {
  const ListenButton({
    super.key,
    required this.text,
    this.compact = false,
  });

  /// The text to read aloud (already localized by the caller).
  final String text;

  /// Compact layout for card headers (icon + short label).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final tts = createTextToSpeechService();
    return compact
        ? TextButton.icon(
            onPressed: () => _speak(context, tts),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.orangeDark,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: const Icon(Icons.volume_up_rounded, size: 18),
            label: Text(
              store.tr('listen.label'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : OutlinedButton.icon(
            onPressed: () => _speak(context, tts),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.orangeDark,
              side: const BorderSide(color: AppTheme.orange),
            ),
            icon: const Icon(Icons.volume_up_rounded, size: 20),
            label: Text(
              store.tr('listen.label'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          );
  }

  void _speak(BuildContext context, TextToSpeechService tts) {
    final store = HoneyChainStore.instance;
    if (!tts.speak(text)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(store.tr('listen.unsupported'))),
        );
    }
  }
}