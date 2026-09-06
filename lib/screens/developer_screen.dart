import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';

/// Beekeeper-facing Developer & diagnostics screen. Kept intentionally tucked
/// away in More — never surfaced on Home / My Hives / Hive Detail / Alerts /
/// Bee Health / Record Harvest. Hosts the demo simulation tooling for
/// reproduceable test scenarios.
class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('dev.title'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.greenSoft,
                borderRadius: AppTheme.radiusCard,
                border: Border.all(color: AppTheme.green.withValues(alpha: 0.4)),
              ),
              child: Text(
                store.tr('dev.note'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.inkSoft,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              store.tr('dev.iot.title'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              store.tr('dev.iot.subtitle'),
              style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(
                  label: store.tr('demo.healthy'),
                  color: AppTheme.green,
                  onTap: () => store.demoSimulateHealthy(),
                ),
                _Pill(
                  label: store.tr('demo.iot'),
                  color: AppTheme.blue,
                  onTap: () => store.demoSimulateIoTAbnormal(),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              store.tr('dev.disease.title'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              store.tr('demo.simulation.note'),
              style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(
                  label: store.tr('demo.disease'),
                  color: AppTheme.orange,
                  onTap: () => store.demoSimulatePossibleDisease(),
                ),
                _Pill(
                  label: store.tr('demo.unable'),
                  color: AppTheme.teal,
                  onTap: () => store.demoSimulateUnableToAssess(),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}
