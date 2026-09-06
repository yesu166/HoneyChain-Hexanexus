import 'package:flutter/material.dart';

import '../models/domain.dart';
import '../theme/app_theme.dart';

/// Color family per alert severity.
(Color, Color) alertColors(AlertSeverity severity) {
  return switch (severity) {
    AlertSeverity.urgent => (AppTheme.red, AppTheme.redSoft),
    AlertSeverity.care => (AppTheme.orange, AppTheme.orangeSoft),
    AlertSeverity.info => (AppTheme.green, AppTheme.greenSoft),
  };
}

/// Tinted alert card shown on the Alerts screen.
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.alert,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.onAction,
  });

  final HiveAlert alert;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (accent, tint) = alertColors(alert.severity);
    return Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                switch (alert.type) {
                  AlertType.temperature => Icons.thermostat_rounded,
                  AlertType.humidity => Icons.water_drop_outlined,
                  AlertType.harvest => Icons.inventory_2_outlined,
                  AlertType.codeCreate => Icons.qr_code_rounded,
                  AlertType.verification =>
                    Icons.verified_outlined,
                  AlertType.disease => Icons.warning_amber_rounded,
                  AlertType.iot => Icons.sensors_rounded,
                },
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppTheme.inkSoft,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (onAction != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent.withValues(alpha: 0.14),
                          foregroundColor: accent,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide(
                              color: accent.withValues(alpha: 0.45),
                              width: 1.4,
                            ),
                          ),
                        ),
                        icon: Icon(
                          switch (alert.type) {
                            AlertType.temperature ||
                            AlertType.humidity ||
                            AlertType.disease ||
                            AlertType.iot =>
                              Icons.hive_outlined,
                            AlertType.verification =>
                              Icons.verified_user_outlined,
                            _ => Icons.arrow_forward_rounded,
                          },
                          size: 18,
                        ),
                        label: Text(
                          actionLabel,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}