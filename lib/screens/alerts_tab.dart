import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../models/iot.dart';
import '../theme/app_theme.dart';
import '../widgets/alert_card.dart';
import '../widgets/sync_status_badge.dart';
import 'hive_details_screen.dart';
import 'honey_passport_screen.dart';

class AlertsTab extends StatelessWidget {
  const AlertsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final alerts = store.alerts.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        final backendNotes = store.apiNotifications;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      store.tr('alerts.title'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  if (store.backendConfigured)
                    IconButton(
                      onPressed: store.backendBusy
                          ? null
                          : () => store.refreshBackendIoT(),
                      icon: const Icon(Icons.refresh_rounded, size: 22),
                      tooltip: 'Refresh backend alerts',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const SyncStatusBadge(),
              if (store.backendConfigured && !store.backendOnline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Backend offline — local alerts only'
                    '${store.backendError == null ? '' : ' (${store.backendError})'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.orangeDark,
                    ),
                  ),
                ),
              if (backendNotes.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'Backend notifications',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 6),
                for (final note in backendNotes)
                  _BackendNotificationCard(
                    store: store,
                    notification: note,
                  ),
                const SizedBox(height: 16),
                const Divider(color: AppTheme.border, height: 1),
                const SizedBox(height: 12),
              ],
              if (alerts.isEmpty && backendNotes.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 44,
                        color: AppTheme.green,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        store.tr('alerts.no.alerts'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.inkFaint,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              if (alerts.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final alert in alerts)
                  _builderCard(context, store, alert),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _builderCard(BuildContext context, HoneyChainStore store, HiveAlert alert) {
    final hive = alert.hiveId != null ? store.hiveById(alert.hiveId!) : null;
    final hiveLabel = hive?.name ?? store.hiveName(alert.hiveId ?? '');
    Batch? relatedBatch;
    if (alert.batchId != null) {
      for (final b in store.batches) {
        if (b.id == alert.batchId) {
          relatedBatch = b;
          break;
        }
      }
    }

    VoidCallback? hiveAction;
    if (hive != null) {
      hiveAction = () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => HiveDetailsScreen(hive: hive)),
          );
    }
    VoidCallback? batchAction;
    final related = relatedBatch;
    if (related != null) {
      batchAction = () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => HoneyPassportScreen(batch: related),
            ),
          );
    }

    final (title, note, action, onAction) = switch (alert.type) {
      AlertType.temperature => (
          store.tr('alert.needs.cooling').replaceFirst('{hive}', hiveLabel),
          store.tr('alert.needs.cooling.note'),
          store.tr('alerts.view.hive'),
          hiveAction,
        ),
      AlertType.humidity => (
          store.tr('alert.needs.care').replaceFirst('{hive}', hiveLabel),
          store.tr('alert.needs.care.note').replaceFirst('{hive}', hiveLabel),
          store.tr('alerts.view.hive'),
          hiveAction,
        ),
      AlertType.disease => (
          store.tr('alert.disease').replaceFirst('{hive}', hiveLabel),
          store.tr('alert.disease.note'),
          store.tr('alerts.view.hive'),
          hiveAction,
        ),
      AlertType.iot => (
          store.tr('alert.iot').replaceFirst('{hive}', hiveLabel),
          store.tr('alert.iot.note'),
          store.tr('alerts.view.hive'),
          hiveAction,
        ),
      AlertType.verification => (
          store.tr('alert.batch.verified'),
          store.tr('alert.batch.verified.note')
              .replaceFirst('{batch}', alert.batchLabel ?? ''),
          store.tr('alerts.view.passport'),
          batchAction,
        ),
      _ => (
          store.tr('important.alert'),
          alert.id,
          '',
          null,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AlertCard(
        alert: alert,
        title: title,
        description: note,
        actionLabel: action,
        onAction: onAction,
      ),
    );
  }
}

/// A notification produced by the backend (`/api/v1/notifications`). Severity
/// and source come from the server; tapping marks it read (no local rewrite).
class _BackendNotificationCard extends StatelessWidget {
  const _BackendNotificationCard({
    required this.store,
    required this.notification,
  });

  final HoneyChainStore store;
  final BackendNotification notification;

  @override
  Widget build(BuildContext context) {
    final accent = switch (notification.severity) {
      'critical' || 'error' => AppTheme.red,
      'warning' => AppTheme.orange,
      _ => AppTheme.blue,
    };
    return InkWell(
      onTap: () => store.markBackendNotificationRead(notification.notificationId),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: notification.read ? AppTheme.card : accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: notification.read
                ? AppTheme.border
                : accent.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  notification.read
                      ? Icons.mark_email_read_outlined
                      : Icons.notifications_active_outlined,
                  size: 18,
                  color: notification.read ? AppTheme.inkFaint : accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    notification.title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: notification.read ? AppTheme.inkSoft : AppTheme.ink,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    notification.severity,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              notification.body.isEmpty ? notification.reason : notification.body,
              style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.35),
            ),
            if (notification.recommendedAction.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '→ ${notification.recommendedAction}',
                style: const TextStyle(fontSize: 12, color: AppTheme.orangeDark),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '${notification.source} · ${notification.category} · ${notification.createdAt}'
              '${notification.isSimulated ? ' · SIM' : ''}'
              '${notification.deviceId == null ? '' : ' · ${notification.deviceId}'}',
              style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}