import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../models/domain.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/brand_header.dart';
import '../../widgets/status_pill.dart';
import '../passport_screen.dart';
import 'buyer_allocation_screen.dart';

/// Buyer Portal: For bulk buyers and cooperatives to inspect released,
/// lab-verified, blockchain-anchored honey batches, and allocate quantity into
/// consumer packaging batches.
class BuyerPortalScreen extends StatelessWidget {
  const BuyerPortalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        foregroundColor: AppTheme.ink,
        elevation: 0,
        title: Text(
          store.tr('buyer.portal.title'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          // Section 14 & 15: Only MARKET_RELEASED (BatchStatus.listed) batches are visible to Buyer
          final releasedBatches = store.batches
              .where((b) => b.status == BatchStatus.listed)
              .toList();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              BrandHeader(subtitle: store.tr('buyer.portal.subtitle')),
              const SizedBox(height: 16),
              if (releasedBatches.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: AppTheme.radiusCard,
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.store_mall_directory_outlined,
                          size: 40,
                          color: AppTheme.inkFaint,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          store.tr('marketplace.empty'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final batch in releasedBatches) ...[
                  _BuyerBatchCard(batch: batch),
                  const SizedBox(height: 14),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _BuyerBatchCard extends StatelessWidget {
  const _BuyerBatchCard({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final listing = store.marketplaceListings
        .where((item) => item.batchId == batch.id)
        .firstOrNull;
    final remainingKg = listing?.effectiveRemainingKg ?? batch.quantityKg;
    final remainingGrams = (remainingKg * 1000).round();
    final anchors = store.anchorsFor(batch);
    final harvests = store.harvestsForBatch(batch);
    final hives = store.sourceHivesForBatch(batch);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppTheme.orangeSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_outlined,
                  size: 20,
                  color: AppTheme.orangeDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  batch.code,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              StatusPill(
                label: store.tr('org.detail.lab.verified'),
                color: AppTheme.green,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${batch.honeyType} · ${batch.origin}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.cardWarm,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.scale_outlined,
                  size: 16,
                  color: AppTheme.orangeDark,
                ),
                const SizedBox(width: 6),
                Text(
                  store
                      .tr('buyer.batch.available')
                      .replaceFirst('{qty}', formatKg(remainingKg))
                      .replaceFirst('{grams}', '$remainingGrams'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'FPO: ${batch.organizationId} · ${hives.length} Hives (${hives.join(", ")})',
            style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
          ),
          if (harvests.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Harvested: ${formatDate(harvests.first.harvestedAt)}',
              style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
            ),
          ],
          if (anchors.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.link_rounded,
                  size: 14,
                  color: AppTheme.greenDark,
                ),
                const SizedBox(width: 4),
                Text(
                  'Anchored: ${anchors.first.anchorId} (DEMO)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.greenDark,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PassportScreen(batch: batch),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code, size: 18),
                  label: Text(store.tr('marketplace.view.passport')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: remainingKg > 0.05
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  BuyerAllocationScreen(batch: batch),
                            ),
                          )
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.orange,
                  ),
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(store.tr('buyer.allocate.button')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
