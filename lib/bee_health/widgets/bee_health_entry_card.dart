import 'package:flutter/material.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/theme/app_theme.dart';

import '../screens/bee_health_home_screen.dart';

class BeeHealthEntryCard extends StatelessWidget {
  const BeeHealthEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: AppTheme.radiusCard,
          border: Border.all(color: AppTheme.border),
          boxShadow: const [AppTheme.shadowCard],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppTheme.radiusCard,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BeeHealthHomeScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.greenSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.health_and_safety_rounded,
                      color: AppTheme.green,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.tr('bh.title'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          store.tr('bh.subtitle'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.inkFaint,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
