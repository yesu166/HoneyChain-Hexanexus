import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'status_pill.dart';

/// Colored status pill for a honey batch (beekeeper viewpoint).
StatusPill batchPill(BuildContext context, BatchDisplayStatus? status) {
  final store = HoneyChainStore.instance;
  final (label, color) = switch (status) {
    BatchDisplayStatus.verified => (store.tr('status.verified'), AppTheme.green),
    BatchDisplayStatus.inLab => (store.tr('status.in.lab'), AppTheme.orange),
    BatchDisplayStatus.failed => (store.tr('status.attention'), AppTheme.red),
    _ => (store.tr('status.pending'), AppTheme.grey),
  };
  return StatusPill(label: label, color: color);
}

/// Rounded card for one honey batch in My Honey.
class BatchTile extends StatelessWidget {
  const BatchTile({
    super.key,
    required this.batch,
    required this.sourceHive,
    this.onTap,
  });

  final Batch batch;
  final String sourceHive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppTheme.radiusCard,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.honey.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_drink_outlined,
                    color: AppTheme.honeyDark,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              batch.code,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppTheme.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (batch.syncStatus == SyncStatus.pending)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                store.tr('status.sync.pending'),
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.orangeDark,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '· ${formatDate(batch.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${store.tr('honey.source').replaceFirst('{hive}', sourceHive)}  '
                        '·  ${store.tr('honey.quantity').replaceFirst('{kg}', formatKg(batch.quantityKg))}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                batchPill(context, batch.displayStatus),
              ],
            ),
          ),
        ),
      ),
    );
  }
}