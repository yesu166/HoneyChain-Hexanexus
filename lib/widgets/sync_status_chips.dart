import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';

/// Small offline / pending-sync chips shown at the top of data screens.
class SyncStatusChips extends StatelessWidget {
  const SyncStatusChips({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final chips = <Widget>[];
        if (!store.isOnline) {
          chips.add(_chip(
            icon: Icons.wifi_off_rounded,
            label: store.tr('common.offline'),
            color: AppTheme.grey,
          ));
        }
        if (store.pendingCount > 0) {
          chips.add(_chip(
            icon: Icons.sync_rounded,
            label: '${store.tr('status.sync.pending')} (${store.pendingCount})',
            color: AppTheme.orangeDark,
          ));
        }
        if (chips.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(spacing: 8, children: chips),
        );
      },
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}