import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import 'status_pill.dart';

/// Hive health card showing temperature, humidity, weight and health score.
class HiveHealthCard extends StatelessWidget {
  const HiveHealthCard({super.key, required this.hive, required this.insight, required this.readings, this.onTap});

  final Hive hive;
  final HiveInsight insight;
  final List<HiveReading> readings;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final latest = readings.isNotEmpty ? readings.last : null;
    final healthy = insight.riskLevel == RiskLevel.healthy;
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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppTheme.honey.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.hive_outlined, color: AppTheme.honeyDark, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hive.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(hive.honeyType, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ],
                    ),
                  ),
                  StatusPill(label: healthy ? StatusPill.healthy : StatusPill.attention),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _Metric(label: store.tr('hive.health.temp'), value: latest != null ? '${latest.temperatureC.toStringAsFixed(1)}°' : '—'),
                  _Metric(label: store.tr('hive.health.humidity'), value: latest != null ? '${latest.humidityPercent.toStringAsFixed(0)}%' : '—'),
                  _Metric(label: store.tr('hive.health.weight'), value: latest != null ? '${latest.weightKg.toStringAsFixed(1)} kg' : '—'),
                  _Metric(label: store.tr('hive.health.health'), value: '${insight.healthScore}/100', highlight: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.highlight = false});
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black45, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: highlight ? AppTheme.honeyDark : null)),
        ],
      ),
    );
  }
}
