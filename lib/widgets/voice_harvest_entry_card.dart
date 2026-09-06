import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../screens/voice_harvest_screen.dart';
import '../theme/app_theme.dart';

/// Centered microphone card shown on the beekeeper home, between the bee
/// health check and the bee photo check. Taps to open voice harvest entry.
class VoiceHarvestEntryCard extends StatelessWidget {
  const VoiceHarvestEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const VoiceHarvestScreen()),
      ),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
        decoration: BoxDecoration(
          color: AppTheme.cardWarm,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [AppTheme.shadowCard],
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppTheme.orange,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              store.tr('voice.entry.title'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              store.tr('voice.entry.subtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 10),
            const Icon(
              Icons.graphic_eq_rounded,
              color: AppTheme.orangeDark,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}