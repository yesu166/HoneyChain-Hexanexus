import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
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
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              Text(
                store.tr('alerts.title'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 12),
              const SyncStatusBadge(),
              if (alerts.isEmpty)
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
              for (final alert in alerts) _builderCard(context, store, alert),
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