import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';

/// The single canonical connectivity + sync badge shown across the app.
///
/// Renders every distinct state:
/// * checking — first probe in flight (or starting up);
/// * online + nothing pending — all good;
/// * online + pending — synced, but a few recent uploads… handled by [isSyncing]
///   during an active pass;
/// * syncing — active sync pass with a pending counter;
/// * offline — no network, changes are saved locally and will sync later;
/// * server unreachable — device online but HoneyChain's backend did not answer;
/// * sync failed — a pass ended with items still unsynced.
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final pending = store.pendingCount;
        final state = _badgeState(store);
        final (icon, color, label, subtitle) = state;
        final Widget leading = store.isSyncing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.green,
                ),
              )
            : Icon(icon, size: 16, color: color);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle != null ? '$label · $subtitle' : label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              if (pending > 0)
                Text(
                  '($pending)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _isOffline(ConnectivityStatus status) =>
      status == ConnectivityStatus.offline;

  (IconData, Color, String, String?) _badgeState(HoneyChainStore store) {
    final t = store.tr;
    if (store.isSyncing) {
      return (Icons.sync_rounded, AppTheme.green, t('status.syncing'),
          store.pendingCount > 0 ? '${store.pendingCount}' : null);
    }
    if (_isOffline(store.connectivityStatus)) {
      return (Icons.wifi_off_rounded, AppTheme.grey, t('status.offline'),
          t('home.offline.synclater'));
    }
    if (store.connectivityStatus == ConnectivityStatus.serviceError) {
      return (Icons.cloud_off_rounded, AppTheme.orangeDark,
          t('status.unavailable'), null);
    }
    if (store.connectivityStatus == ConnectivityStatus.checking) {
      return (Icons.sync_problem_rounded, AppTheme.inkSoft,
          t('status.checking'), null);
    }
    if (store.hasSyncError) {
      return (Icons.error_outline_rounded, AppTheme.red,
          t('status.sync.failed'), null);
    }
    if (store.pendingCount > 0) {
      return (Icons.schedule_rounded, AppTheme.orangeDark,
          t('status.sync.pending'), '${store.pendingCount}');
    }
    return (Icons.wifi_rounded, AppTheme.green, t('status.online'), null);
  }
}