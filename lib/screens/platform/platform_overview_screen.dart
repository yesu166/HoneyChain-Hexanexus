import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../services/platform_api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_label.dart';

/// Platform Oversight -> Overview.
///
/// Platform-wide aggregates (`GET /api/v1/platform/stats`) with a live refresh
/// and a clear "platform" identity banner. Numbers are server-derived; the UI
/// never invents a metric.
class PlatformOverviewScreen extends StatefulWidget {
  const PlatformOverviewScreen({super.key});

  @override
  State<PlatformOverviewScreen> createState() => _PlatformOverviewScreenState();
}

class _PlatformOverviewScreenState extends State<PlatformOverviewScreen> {
  PlatformStats? _stats;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = HoneyChainStore.instance;
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stats = await store.platformApi.platformStats();
      if (!mounted) return;
      setState(() => _stats = stats);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Platform Overview',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _load,
                  icon: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 22),
                  tooltip: 'Refresh platform stats',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Live aggregate view for the platform oversight role.',
              style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              _ErrorCard(message: _error!, onRetry: _load)
            else if (_stats == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _StatsHeroRow(stats: _stats!),
              const SizedBox(height: 12),
              SectionLabel('Network scale'),
              _metricGrid(store, _stats!),
            ],
            const SizedBox(height: 12),
            const Divider(color: AppTheme.border, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.security_rounded, size: 18, color: AppTheme.honeyDark),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Role ${store.backendRole.isEmpty ? 'unknown' : store.backendRole}'
                    ' · scope restricted by backend RBAC',
                    style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _metricGrid(HoneyChainStore store, PlatformStats s) {
    final cells = <_MetricCell>[
      _MetricCell(
        icon: Icons.groups_outlined,
        color: AppTheme.honeyDark,
        value: '${s.registeredBeekeepers}',
        label: 'Beekeepers',
      ),
      _MetricCell(
        icon: Icons.account_balance_outlined,
        color: AppTheme.greenDark,
        value: '${s.organizations}',
        label: 'Organizations',
      ),
      _MetricCell(
        icon: Icons.hive_outlined,
        color: AppTheme.orangeDark,
        value: '${s.hives}',
        label: 'Hives',
      ),
      _MetricCell(
        icon: Icons.eco_outlined,
        color: AppTheme.green,
        value: _kg(s.honeyHarvestedKg),
        label: 'Honey (kg)',
      ),
      _MetricCell(
        icon: Icons.inventory_rounded,
        color: AppTheme.blue,
        value: '${s.harvests}',
        label: 'Harvests',
      ),
      _MetricCell(
        icon: Icons.inventory_2_outlined,
        color: AppTheme.teal,
        value: '${s.batches}',
        label: 'Batches',
      ),
      _MetricCell(
        icon: Icons.science_outlined,
        color: AppTheme.purple,
        value: '${s.labTests}',
        label: 'Lab tests',
      ),
      _MetricCell(
        icon: Icons.verified_outlined,
        color: AppTheme.greenDark,
        value: '${s.certificates}',
        label: 'Certificates',
      ),
      _MetricCell(
        icon: Icons.memory_rounded,
        color: AppTheme.orangeDark,
        value: '${s.iotDevices}',
        label: 'IoT devices',
      ),
      _MetricCell(
        icon: Icons.monitor_heart_outlined,
        color: AppTheme.blue,
        value: '${s.telemetryEvents}',
        label: 'Telemetry',
      ),
    ];
    return Column(
      children: [
        for (var i = 0; i < cells.length; i += 3) ...[
          Row(
            children: [
              for (var j = i; j < i + 3 && j < cells.length; j++) ...[
                Expanded(child: cells[j]),
                if (j != i + 2 && j != cells.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String _kg(double v) =>
      v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}t' : v.toStringAsFixed(0);
}

class _StatsHeroRow extends StatelessWidget {
  const _StatsHeroRow({required this.stats});

  final PlatformStats stats;

  @override
  Widget build(BuildContext context) {
    final orgs = stats.organizations;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppTheme.honey,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.admin_panel_settings_outlined,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$orgs organizations on the network',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stats.registeredBeekeepers} beekeepers · ${stats.hives} hives',
                  style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppTheme.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.redSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppTheme.red, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Could not load platform stats',
                  style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.inkSoft, height: 1.35),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}