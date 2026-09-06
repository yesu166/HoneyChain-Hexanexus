import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';

/// Demo/simulated acoustic (buzzing) activity for a hive. Clearly labeled as
/// simulation — the app does not claim a real audio sensor or diagnosis.
class AcousticActivityCard extends StatelessWidget {
  const AcousticActivityCard({super.key, required this.hive});

  final Hive hive;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final (label, level) = store.acousticFor(hive);
    const accents = [
      AppTheme.green,
      AppTheme.orange,
      AppTheme.red,
    ];
    final accent = accents[level.clamp(0, 2)];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.tr('acoustic.title'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              _Bar(level: level, active: level >= 1),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            store.tr('acoustic.disclaimer'),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.inkFaint,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.level, required this.active});

  final int level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 8,
              height: 6 + (i + 1) * 5.0,
              decoration: BoxDecoration(
                color: i <= level ? AppTheme.orange : AppTheme.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
      ],
    );
  }
}