import 'package:flutter/material.dart';

import '../models/domain.dart';
import '../theme/app_theme.dart';
import 'status_pill.dart';

String batchStatusLabel(BatchStatus status) {
  switch (status) {
    case BatchStatus.created:
      return StatusPill.pending;
    case BatchStatus.collected:
      return StatusPill.processing;
    case BatchStatus.labPending:
      return StatusPill.pending;
    case BatchStatus.labVerified:
      return StatusPill.verified;
    case BatchStatus.labFailed:
      return StatusPill.failed;
    case BatchStatus.processing:
      return StatusPill.processing;
    case BatchStatus.listed:
      return StatusPill.listed;
    case BatchStatus.completed:
      return StatusPill.verified;
  }
}

/// Batch card showing ID, honey type, quantity, origin, harvest date and status.
class BatchCard extends StatelessWidget {
  const BatchCard({super.key, required this.batch, this.extra, this.onTap});

  final Batch batch;
  final String? extra;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = batchStatusLabel(batch.status);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.hexagon_outlined, color: AppTheme.honeyDark, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      batch.code,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  StatusPill(label: status),
                ],
              ),
              const SizedBox(height: 10),
              Text(batch.honeyType, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${batch.origin}  ·  ${batch.quantityKg.toStringAsFixed(1)} kg', style: const TextStyle(color: Colors.black54, fontSize: 13)),
              if (extra != null) ...[
                const SizedBox(height: 4),
                Text(extra!, style: const TextStyle(color: Colors.black38, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
