import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import 'status_pill.dart';

/// Colored status pill for a hive based on its health risk.
StatusPill riskPill(BuildContext context, RiskLevel risk) {
  final store = HoneyChainStore.instance;
  final (label, color) = switch (risk) {
    RiskLevel.healthy => (store.tr('status.healthy'), AppTheme.green),
    RiskLevel.attentionRequired =>
      (store.tr('status.attention'), AppTheme.orange),
    RiskLevel.highRisk => (store.tr('status.action'), AppTheme.red),
  };
  return StatusPill(label: label, color: color);
}

/// Large rounded hive card for the My Hives screen.
class HiveCard extends StatelessWidget {
  const HiveCard({super.key, required this.hive, required this.risk, this.onTap});

  final Hive hive;
  final RiskLevel risk;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.honey.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.hive_outlined,
                        color: AppTheme.honeyDark,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hive.detail.isEmpty
                                ? hive.name
                                : '${hive.name} · ${hive.detail}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppTheme.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                    riskPill(context, risk),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 15,
                      color: AppTheme.inkFaint,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        hive.location,
                        style: const TextStyle(
                          color: AppTheme.inkSoft,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}