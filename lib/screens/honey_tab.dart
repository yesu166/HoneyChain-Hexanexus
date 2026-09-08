import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';
import '../widgets/batch_tile.dart';
import '../widgets/sync_status_badge.dart';
import 'honey_passport_screen.dart';

class HoneyTab extends StatelessWidget {
  const HoneyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final batches = store.batches.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              Text(
                store.tr('my.honey.title'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                store.tr('my.honey.subtitle'),
                style: const TextStyle(color: AppTheme.inkSoft, fontSize: 14),
              ),
              const SizedBox(height: 12),
              const SyncStatusBadge(),
              if (batches.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      store.tr('my.honey.empty'),
                      style: const TextStyle(
                        color: AppTheme.inkFaint,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              for (final batch in batches) ...[
                BatchTile(
                  batch: batch,
                  sourceHive: store.batchSourceHive(batch),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HoneyPassportScreen(batch: batch),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}