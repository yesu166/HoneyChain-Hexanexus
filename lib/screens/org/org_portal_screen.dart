import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../models/domain.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/status_pill.dart';
import 'org_batch_detail_screen.dart';
import 'org_collection_screen.dart';
import 'org_products_screen.dart';

/// Organization / FPO portal.
///
/// A distinct, HoneyChain-themed workbench for the collection side of the
/// demo: switch among cooperating organizations, collect incoming harvests,
/// consolidate multi-hive harvests into batches, run lab / processing /
/// packaging, and issue consumer product QR codes. It replaces the old basic
/// "Collection / Processor" screen and does not touch the beekeeper nav.
class OrgPortalScreen extends StatefulWidget {
  const OrgPortalScreen({super.key});

  @override
  State<OrgPortalScreen> createState() => _OrgPortalScreenState();
}

class _OrgPortalScreenState extends State<OrgPortalScreen> {
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('org.portal.appbar'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final org = store.activeFpoOrg;
          final batches = store.batches.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              _OrgHeader(
                orgName: org.name,
                orgId: org.id,
                onSwitchOrg: () => _pickOrg(context),
              ),
              const SizedBox(height: 16),
              const _LiveMetricsCard(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      value: '${store.incomingCount}',
                      label: store.tr('org.portal.incoming'),
                      icon: Icons.inbox_outlined,
                      color: AppTheme.orange,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      value: '${store.collectedCount}',
                      label: store.tr('org.portal.collected'),
                      icon: Icons.inventory_2_outlined,
                      color: AppTheme.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatTile(
                      value: '${store.packagedCount}',
                      label: store.tr('org.portal.packaged'),
                      icon: Icons.local_shipping_outlined,
                      color: AppTheme.orangeDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _QuickActions(
                onCollection: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OrgCollectionScreen(),
                  ),
                ),
                onProducts: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const OrgProductsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _SectionTitle(
                title: store.tr('org.portal.batches.title'),
                trailing: '${batches.length}',
              ),
              const SizedBox(height: 12),
              if (batches.isEmpty)
                _EmptyCard(text: store.tr('org.portal.batches.empty'))
              else
                for (final batch in batches) ...[
                  _BatchRow(
                    batch: batch,
                    sourceHives: store.sourceHivesForBatch(batch),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => OrgBatchDetailScreen(batch: batch),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 20),
              Text(
                store.tr('org.portal.demo.note'),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.inkFaint,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickOrg(BuildContext context) async {
    final store = HoneyChainStore.instance;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bg,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                store.tr('org.portal.coops.title'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final org in store.organizations)
              ListTile(
                leading: Icon(
                  store.activeFpoOrgId == org.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: store.activeFpoOrgId == org.id
                      ? AppTheme.orange
                      : AppTheme.inkFaint,
                ),
                title: Text(
                  org.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                subtitle: Text(
                  org.id,
                  style: const TextStyle(
                    color: AppTheme.inkFaint,
                    fontSize: 12,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop(org.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) store.setActiveFpoOrg(selected);
  }
}

class _OrgHeader extends StatelessWidget {
  const _OrgHeader({
    required this.orgName,
    required this.orgId,
    required this.onSwitchOrg,
  });

  final String orgName;
  final String orgId;
  final VoidCallback onSwitchOrg;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.orangeSoft, AppTheme.cardWarm],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: AppTheme.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hub_outlined,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      orgId,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.orangeDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      orgName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onSwitchOrg,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.orangeDark,
              side: const BorderSide(color: AppTheme.orangeDark),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(
              store.tr('org.portal.switch.org'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}
class _LiveMetricsCard extends StatelessWidget {
  const _LiveMetricsCard();

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final dashboard = store.orgDashboard;
    final live = dashboard != null && dashboard.isBackendSourced;

    if (!live) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.cardWarm,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.stacked_line_chart_rounded,
                color: AppTheme.honeyDark, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                store.orgDashboardError ?? store.tr('org.dashboard.live.empty'),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.inkSoft,
                ),
              ),
            ),
            if (store.backendModeActive)
              IconButton(
                onPressed: store.orgDashboardBusy
                    ? null
                    : () => store.refreshOrgDashboard(),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh live metrics',
              ),
          ],
        ),
      );
    }

    final d = dashboard;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stacked_line_chart_rounded,
                  color: AppTheme.honeyDark, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  store.tr('org.dashboard.live'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              StatusPill(
                label: store.tr('org.dashboard.live.badge'),
                color: AppTheme.honey,
              ),
              const SizedBox(width: 4),
              if (store.orgDashboardBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  onPressed: () => store.refreshOrgDashboard(),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  tooltip: 'Refresh live metrics',
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            store.tr('org.dashboard.live.sub'),
            style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
          ),
          const SizedBox(height: 12),
          _metricRow(context, store, [
            _Metric(
              value: '${d.activeBeekeepers}',
              label: store.tr('org.dashboard.metric.beekeepers'),
              icon: Icons.groups_outlined,
              color: AppTheme.orange,
            ),
            _Metric(
              value: '${d.hives}',
              label: store.tr('org.dashboard.metric.hives'),
              icon: Icons.hive_outlined,
              color: AppTheme.honeyDark,
            ),
            _Metric(
              value: '${d.clusters}',
              label: store.tr('org.dashboard.metric.clusters'),
              icon: Icons.timeline_rounded,
              color: AppTheme.teal,
            ),
            _Metric(
              value: '${d.collections}',
              label: store.tr('org.dashboard.metric.collections'),
              icon: Icons.inventory_2_outlined,
              color: AppTheme.blue,
            ),
          ]),
          const SizedBox(height: 8),
          _metricRow(context, store, [
            _Metric(
              value: formatKg(d.honeyHarvestedKg),
              label: store.tr('org.dashboard.metric.harvest'),
              icon: Icons.eco_outlined,
              color: AppTheme.green,
            ),
            _Metric(
              value: '${d.batches}',
              label: store.tr('org.dashboard.metric.batches'),
              icon: Icons.inventory_rounded,
              color: AppTheme.orangeDark,
            ),
            _Metric(
              value: '${d.verifiedBatches}',
              label: store.tr('org.dashboard.metric.verified'),
              icon: Icons.verified_outlined,
              color: AppTheme.greenDark,
            ),
            _Metric(
              value: '${d.pendingActions}',
              label: store.tr('org.dashboard.metric.pending'),
              icon: Icons.pending_actions_rounded,
              color: AppTheme.red,
            ),
          ]),
          const SizedBox(height: 14),
          Text(
            store.tr('org.dashboard.recent'),
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppTheme.inkSoft,
            ),
          ),
          const SizedBox(height: 8),
          if (d.recentActivity.isEmpty)
            Text(
              store.tr('org.dashboard.recent.empty'),
              style: const TextStyle(fontSize: 12.5, color: AppTheme.inkFaint),
            )
          else
            for (final item in d.recentActivity.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Icon(
                      item.type == 'harvest'
                          ? Icons.eco_outlined
                          : item.type == 'custody'
                              ? Icons.local_shipping_outlined
                              : Icons.inventory_rounded,
                      size: 15,
                      color: AppTheme.inkFaint,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    if (item.timestamp.isNotEmpty)
                      Text(
                        _shortTs(item.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.inkFaint,
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _metricRow(BuildContext context, HoneyChainStore store,
      List<_Metric> metrics) {
    return Row(
      children: [
        for (final m in metrics) ...[
          Expanded(child: _MetricCell(metric: m)),
          if (m != metrics.last) const SizedBox(width: 8),
        ],
      ],
    );
  }

  String _shortTs(String ts) {
    final parsed = DateTime.tryParse(ts);
    if (parsed == null) return ts.length > 12 ? ts : ts;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)} ${two(parsed.hour)}:${two(parsed.minute)}';
  }
}

class _Metric {
  const _Metric({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardWarm,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Icon(metric.icon, color: metric.color, size: 18),
          const SizedBox(height: 4),
          Text(
            metric.value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            metric.label,
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

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onCollection,
    required this.onProducts,
  });

  final VoidCallback onCollection;
  final VoidCallback onProducts;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final incoming = store.incomingCount;
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            icon: Icons.inventory_2_outlined,
            title: store.tr('org.portal.action.collect'),
            subtitle: incoming > 0
                ? store.tr('org.portal.action.collect.sub').replaceFirst('{incoming}', '$incoming')
                : store.tr('org.portal.action.collect.sub.empty'),
            onTap: onCollection,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionCard(
            icon: Icons.qr_code_rounded,
            title: store.tr('org.portal.action.qr'),
            subtitle: store
                .tr('org.portal.action.qr.sub')
                .replaceFirst('{count}', '${store.packagedCount}'),
            onTap: onProducts,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.orangeSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.orangeDark, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: AppTheme.inkFaint,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.orangeDark,
            ),
          ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
      ),
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({
    required this.batch,
    required this.sourceHives,
    required this.onTap,
  });

  final Batch batch;
  final List<String> sourceHives;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      batch.code,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  _statusPill(batch.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${batch.honeyType} · ${formatKg(batch.quantityKg)} kg',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(
                    Icons.hive_outlined,
                    size: 15,
                    color: AppTheme.inkFaint,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      sourceHives.isEmpty
                          ? batch.origin
                          : '${sourceHives.length} source hives · ${sourceHives.join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.inkFaint,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(BatchStatus status) {
    final store = HoneyChainStore.instance;
    final (label, color) = switch (status) {
      BatchStatus.created => (store.tr('org.portal.batch.status.created'), AppTheme.orange),
      BatchStatus.collected => (store.tr('org.portal.batch.status.collected'), AppTheme.orangeDark),
      BatchStatus.labPending => (store.tr('org.portal.batch.status.inlab'), AppTheme.orange),
      BatchStatus.labVerified => (store.tr('org.portal.batch.status.labverified'), AppTheme.green),
      BatchStatus.labFailed => (store.tr('org.portal.batch.status.labfailed'), AppTheme.red),
      BatchStatus.processing => (store.tr('org.portal.batch.status.processing'), AppTheme.orange),
      BatchStatus.listed => (store.tr('org.portal.batch.status.listed'), AppTheme.orange),
      BatchStatus.completed => (store.tr('org.portal.batch.status.completed'), AppTheme.green),
    };
    return StatusPill(label: label, color: color);
  }
}