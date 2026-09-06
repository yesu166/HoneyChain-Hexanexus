import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Reusable status pill used across screens.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  static const healthy = 'Healthy';
  static const attention = 'Attention';
  static const verified = 'Verified';
  static const processing = 'Processing';
  static const pending = 'Pending';
  static const failed = 'Failed';
  static const listed = 'Listed';

  static Color pillColor(String label) {
    switch (label) {
      case healthy:
      case verified:
      case listed:
        return AppTheme.green;
      case attention:
      case processing:
        return AppTheme.orange;
      case failed:
        return AppTheme.red;
      case pending:
      default:
        return AppTheme.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? pillColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: c,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
