import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../models/domain.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/status_pill.dart';
import 'org_create_batch_screen.dart';

/// Organization/FPO collection view: incoming harvests awaiting collection,
/// and collected harvests available for consolidation into multi-hive batches.
class OrgCollectionScreen extends StatefulWidget {
  const OrgCollectionScreen({super.key});

  @override
  State<OrgCollectionScreen> createState() => _OrgCollectionScreenState();
}

class _OrgCollectionScreenState extends State<OrgCollectionScreen> {
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
          store.tr('org.collection.appbar'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final incoming = store.incomingHarvests;
          final collected = store.collectedHarvests;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              _HeaderBanner(
                orgName: store.activeFpoOrg.name,
                incoming: store.incomingCount,
                collected: store.collectedCount,
              ),
              const SizedBox(height: 22),
              _SectionTitle(
                title: store.tr('org.collection.incoming.title'),
                count: incoming.length,
              ),
              const SizedBox(height: 8),
              if (incoming.isEmpty)
                _EmptyBox(text: store.tr('org.collection.no.incoming'))
              else
                for (final h in incoming) ...[
                  _HarvestTile(
                    harvest: h,
                    hiveName: store.hiveName(h.hiveId),
                    collected: false,
                    onAction: () => store.collectHarvest(h),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 22),
              _SectionTitle(
                title: store.tr('org.collection.collected.title'),
                count: collected.length,
              ),
              const SizedBox(height: 8),
              if (collected.isEmpty)
                _EmptyBox(text: store.tr('org.collection.no.collected'))
              else
                for (final h in collected) ...[
                  _HarvestTile(
                    harvest: h,
                    hiveName: store.hiveName(h.hiveId),
                    collected: true,
                    onAction: () {},
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 20),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed:
                      collected.isEmpty ? null : _openBatchCreation,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.orange,
                    disabledBackgroundColor: AppTheme.grey,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: const Icon(Icons.hexagon_outlined, size: 20),
                  label: Text(
                    store.tr('org.collection.consolidate'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  /// Starts the multi-hive batch consolidation flow with collected harvests.
  void _openBatchCreation() {
    final store = HoneyChainStore.instance;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            OrgCreateBatchScreen(harvests: List.of(store.collectedHarvests)),
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({
    required this.orgName,
    required this.incoming,
    required this.collected,
  });

  final String orgName;
  final int incoming;
  final int collected;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppTheme.orangeSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: AppTheme.orangeDark,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  orgName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  store
                      .tr('org.collection.banner.sub')
                      .replaceFirst('{incoming}', '$incoming')
                      .replaceFirst('{collected}', '$collected'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HarvestTile extends StatelessWidget {
  const _HarvestTile({
    required this.harvest,
    required this.hiveName,
    required this.collected,
    required this.onAction,
  });

  final Harvest harvest;
  final String hiveName;
  final bool collected;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: collected ? AppTheme.green : AppTheme.border,
          width: collected ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            collected ? Icons.check_circle_rounded : Icons.hive_outlined,
            color: collected ? AppTheme.green : AppTheme.orange,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hiveName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatKg(harvest.quantityKg)} kg · ${harvest.honeyType} · ${formatDate(harvest.harvestedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.inkFaint,
                  ),
                ),
              ],
            ),
          ),
          if (!collected)
            SizedBox(
              height: 34,
              child: FilledButton.icon(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.inventory_2_rounded, size: 16),
                label: Text(
                  store.tr('org.collection.collect.btn'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else
            StatusPill(label: store.tr('org.collection.collected.pill'), color: AppTheme.green),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.count});

  final String title;
  final int count;

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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.orangeSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.orangeDark,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
      ),
    );
  }
}