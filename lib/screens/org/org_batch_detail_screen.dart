import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../models/domain.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/product_qr.dart';
import '../../widgets/status_pill.dart';
import '../../widgets/section_label.dart';
import '../honey_passport_screen.dart';
import 'org_products_screen.dart';

/// Organization-side detail for a consolidated batch: genealogy of source
/// hives/harvests, lab, processing, packaging and the consumer product QR.
class OrgBatchDetailScreen extends StatelessWidget {
  const OrgBatchDetailScreen({super.key, required this.batch});

  final Batch batch;

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
          batch.code,
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          // Resolve the live batch so post-action rebuilds show new state.
          final liveBatch = store.batchById(batch.id) ?? batch;
          final harvests = store.harvestsForBatch(liveBatch);
          final products = store.productsFor(liveBatch);
          final processing = store.processingFor(liveBatch);
          final verifications = store.verificationsFor(liveBatch);
          final custody = store.custodyFor(liveBatch);
          final batchAnchors = store
              .anchorsFor(liveBatch)
              .where((a) => a.packagingBatchId == null)
              .toList();
          final listing = store.marketplaceListings
              .where((l) => l.batchId == liveBatch.id)
              .firstOrNull;
          final packagingBatches = store.packagingBatchesFor(liveBatch);
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              _BatchHero(batch: liveBatch),
              const SizedBox(height: 18),
              SectionLabel(store.tr('org.detail.genealogy')),
              _GenealogyCard(harvests: harvests, store: store),
              const SizedBox(height: 22),
              SectionLabel(store.tr('org.detail.custody')),
              _CustodyCard(batch: liveBatch, custody: custody, store: store),
              const SizedBox(height: 22),
              SectionLabel(store.tr('org.detail.lab')),
              _LabCard(
                batch: liveBatch,
                verification:
                    verifications.isNotEmpty ? verifications.first : null,
              ),
              const SizedBox(height: 22),
              SectionLabel(store.tr('org.detail.processing.packaging')),
              _ProcessingCard(
                batch: liveBatch,
                processing: processing,
                onProcess: () => _recordProcessing(context),
                onPackage: (size) => _package(context, liveBatch, size),
                products: products,
              ),
              const SizedBox(height: 22),
              SectionLabel(store.tr('org.detail.integrity')),
              _IntegrityCard(
                batch: liveBatch,
                anchors: batchAnchors,
                listing: listing,
                store: store,
              ),
              const SizedBox(height: 22),
              SectionLabel(store.tr('org.detail.jars')),
              _PackagingJarsCard(
                packagingBatches: packagingBatches,
                store: store,
              ),
              const SizedBox(height: 22),
              if (products.isNotEmpty) ...[
                SectionLabel(store.tr('org.detail.product.qr')),
                const SizedBox(height: 10),
                _ProductQrCards(products: products),
                const SizedBox(height: 26),
              ],
            ],
          );
        },
      ),
    );
  }

  void _recordProcessing(BuildContext context) {
    final store = HoneyChainStore.instance;
    final unit = store.activeFpoOrg.name;
    store.recordProcessing(batch, unit);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store
            .tr('org.detail.processing.recorded.toast')
            .replaceFirst('{unit}', unit)),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _package(BuildContext context, Batch batch, ProductSize size) {
    final store = HoneyChainStore.instance;
    final product = store.createProductBatch(batch, size);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store
            .tr('org.detail.packaged.toast')
            .replaceFirst('{code}', product.productCode)
            .replaceFirst('{size}', size.label)),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrgProductsScreen()),
    );
  }
}

class _BatchHero extends StatelessWidget {
  const _BatchHero({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final (label, accent) = switch (batch.status) {
      BatchStatus.labVerified =>
        (store.tr('org.detail.lab.verified'), AppTheme.green),
      BatchStatus.labFailed =>
        (store.tr('org.detail.lab.failed'), AppTheme.red),
      BatchStatus.labPending ||
      BatchStatus.collected ||
      BatchStatus.created =>
        (store.tr('org.detail.in.progress'), AppTheme.orange),
      _ => (store.tr('org.detail.in.progress'), AppTheme.orange),
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.4),
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
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              StatusPill(label: label, color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${batch.honeyType} · ${formatKg(batch.quantityKg)} kg',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            store
                .tr('org.detail.org.origin')
                .replaceFirst('{org}', store.activeFpoOrg.name)
                .replaceFirst('{origin}', batch.origin),
            style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
          ),
          const SizedBox(height: 4),
          Text(
            store
                .tr('org.detail.created.date')
                .replaceFirst('{date}', formatDate(batch.createdAt)),
            style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _GenealogyCard extends StatelessWidget {
  const _GenealogyCard({required this.harvests, required this.store});

  final List<Harvest> harvests;
  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < harvests.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: AppTheme.orangeSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.hive_outlined,
                      size: 18,
                      color: AppTheme.orangeDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.hiveName(harvests[i].hiveId),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatKg(harvests[i].quantityKg)} kg · ${formatDate(harvests[i].harvestedAt)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (i != harvests.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16, color: AppTheme.border),
          ],
          if (harvests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                HoneyChainStore.instance.tr('org.detail.no.harvests'),
                style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
              ),
            ),
        ],
      ),
    );
  }
}

class _LabCard extends StatelessWidget {
  const _LabCard({required this.batch, required this.verification});

  final Batch batch;
  final LabVerification? verification;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    if (verification != null && verification!.status == VerificationStatus.pass) {
      return Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.greenSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.green.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_rounded, color: AppTheme.green),
                    const SizedBox(width: 8),
                    Text(
                      store.tr('org.detail.lab.verified'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  verification!.summary,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  store
                      .tr('org.detail.lab.ref')
                      .replaceFirst('{id}', verification!.labOrganizationId)
                      .replaceFirst('{date}', formatDate(verification!.testedAt)),
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              store.tr('org.detail.lab.illustrative'),
              style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint),
            ),
          ),
        ],
      );
    }

    final verified = batch.status == BatchStatus.labVerified;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            verified
                ? store.tr('org.detail.awaiting.packaging')
                : store.tr('org.detail.send.to.lab'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            store.tr('org.detail.trigger.demo'),
            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: () {
                store.verifyV2Batch(batch, VerificationStatus.pass);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(store.tr('org.detail.demo.passed')),
                    backgroundColor: AppTheme.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.orangeDark,
                side: const BorderSide(color: AppTheme.orangeDark),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.science_outlined, size: 18),
              label: Text(
                store.tr('org.detail.verify.btn'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProcessingCard extends StatelessWidget {
  const _ProcessingCard({
    required this.batch,
    required this.processing,
    required this.onProcess,
    required this.onPackage,
    required this.products,
  });

  final Batch batch;
  final List<ProcessingEvent> processing;
  final VoidCallback onProcess;
  final ValueChanged<ProductSize> onPackage;
  final List<ProductBatch> products;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final canPackage = batch.status == BatchStatus.labVerified ||
        batch.status == BatchStatus.processing ||
        batch.status == BatchStatus.completed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.tr('org.detail.processing.label'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          if (processing.isEmpty)
            Text(
              store.tr('org.detail.no.processing'),
              style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            )
          else
            for (final e in processing)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.orangeSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.factory_outlined,
                      size: 18,
                      color: AppTheme.orangeDark,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.unit,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                    Text(
                      formatDate(e.date),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: onProcess,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.orangeDark,
                side: const BorderSide(color: AppTheme.orangeDark),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.factory_outlined, size: 18),
              label: Text(
                store.tr('org.detail.record.processing'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 16),
          Text(
            store.tr('org.detail.packaging.label'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            store
                .tr('org.detail.qr.issued')
                .replaceFirst('{count}', '${products.length}'),
            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              _PackButton(
                size: ProductSize.size500ml,
                enabled: canPackage,
                onTap: () => onPackage(ProductSize.size500ml),
              ),
              _PackButton(
                size: ProductSize.size1kg,
                enabled: canPackage,
                onTap: () => onPackage(ProductSize.size1kg),
              ),
            ],
          ),
          if (!canPackage) ...[
            const SizedBox(height: 8),
            Text(
              store.tr('org.detail.package.after.lab'),
              style: const TextStyle(fontSize: 12, color: AppTheme.orangeDark),
            ),
          ],
        ],
      ),
    );
  }
}

class _PackButton extends StatelessWidget {
  const _PackButton({
    required this.size,
    required this.enabled,
    required this.onTap,
  });

  final ProductSize size;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return SizedBox(
      height: 44,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled ? AppTheme.green : AppTheme.grey,
          side: BorderSide(
            color: enabled ? AppTheme.green : AppTheme.grey,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.qr_code_rounded, size: 18),
        label: Text(
          store
              .tr('org.detail.pack.btn')
              .replaceFirst('{size}', size.label),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _CustodyCard extends StatelessWidget {
  const _CustodyCard({
    required this.batch,
    required this.custody,
    required this.store,
  });

  final Batch batch;
  final List<CustodyEvent> custody;
  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    final accepted = custody.isNotEmpty;
    final event = accepted ? custody.first : null;
    final canAccept =
        !accepted &&
        (batch.status == BatchStatus.created ||
            batch.status == BatchStatus.collected);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event != null) ...[
            Row(
              children: [
                const Icon(Icons.verified_rounded, color: AppTheme.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store.tr('org.detail.custody.accepted'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${event.note} · ${formatDate(event.recordedAt)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.inkSoft,
                height: 1.4,
              ),
            ),
          ] else ...[
            Text(
              store.tr('org.detail.custody.not.accepted'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: canAccept ? () => _acceptCustody(context) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.orangeDark,
                  side: const BorderSide(color: AppTheme.orangeDark),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.handshake_outlined, size: 18),
                label: Text(
                  store.tr('org.detail.custody.accept.btn'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              store.tr('org.detail.custody.hint'),
              style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
            ),
          ],
        ],
      ),
    );
  }

  void _acceptCustody(BuildContext context) {
    store.acceptV2Custody(batch);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store.tr('org.detail.custody.accept.toast')),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _IntegrityCard extends StatelessWidget {
  const _IntegrityCard({
    required this.batch,
    required this.anchors,
    required this.listing,
    required this.store,
  });

  final Batch batch;
  final List<BlockchainAnchor> anchors;
  final MarketplaceListing? listing;
  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    final anchored = anchors.isNotEmpty;
    final anchor = anchored ? anchors.first : null;
    final canAnchor = !anchored && batch.status == BatchStatus.labVerified;
    final canRelease =
        (listing == null || !listing!.isActive) &&
        batch.status == BatchStatus.labVerified;
    final listed = listing != null && listing!.isActive;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_rounded, color: AppTheme.orangeDark, size: 18),
              const SizedBox(width: 8),
              Text(
                store.tr('org.detail.anchor.label'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (anchor != null) ...[
            Row(
              children: [
                const Icon(Icons.verified_rounded, color: AppTheme.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store
                        .tr('org.detail.anchor.done')
                        .replaceFirst('{ref}', anchor.anchorId),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${anchor.eventType} · ${formatDate(anchor.anchoredAt)}',
              style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
            ),
          ] else ...[
            Text(
              store.tr('org.detail.no.anchor.yet'),
              style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: canAnchor ? () => _confirmAnchor(context) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.orangeDark,
                  side: const BorderSide(color: AppTheme.orangeDark),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.hub_outlined, size: 18),
                label: Text(
                  store.tr('org.detail.anchor.btn'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (!canAnchor) ...[
              const SizedBox(height: 8),
              Text(
                store.tr('org.detail.anchor.after.lab'),
                style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
              ),
            ],
          ],
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.storefront_outlined, color: AppTheme.orangeDark, size: 18),
              const SizedBox(width: 8),
              Text(
                store.tr('org.detail.market.label'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (listed) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: AppTheme.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store.tr('org.detail.listed.note'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${listing!.id} · ₹${listing!.pricePerKg}/kg · '
              '${formatKg(listing!.effectiveRemainingKg)} kg remaining',
              style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: canRelease ? () => _release(context) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.green,
                  side: const BorderSide(color: AppTheme.green),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.public_rounded, size: 18),
                label: Text(
                  store.tr('org.detail.release.btn'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (!canRelease) ...[
              const SizedBox(height: 8),
              Text(
                store.tr('org.detail.release.after.lab'),
                style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
              ),
            ] else if (!anchored) ...[
              const SizedBox(height: 8),
              Text(
                store.tr('org.detail.anchor.guard'),
                style: const TextStyle(fontSize: 12, color: AppTheme.orangeDark),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _confirmAnchor(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          store.tr('org.detail.anchor.confirm.title'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(store.tr('org.detail.anchor.confirm.message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(store.tr('action.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.orange),
            child: Text(store.tr('org.detail.anchor.confirm.button')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    store.anchorV2Batch(batch, 'BATCH_VERIFIED');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store.tr('org.detail.anchor.toast')),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _release(BuildContext context) {
    store.releaseV2BatchToMarket(batch);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store.tr('org.detail.release.toast')),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _PackagingJarsCard extends StatelessWidget {
  const _PackagingJarsCard({
    required this.packagingBatches,
    required this.store,
  });

  final List<PackagingBatch> packagingBatches;
  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    if (packagingBatches.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: AppTheme.radiusCard,
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          store.tr('org.detail.jars.none'),
          style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
        ),
      );
    }
    return Column(
      children: [
        for (final pb in packagingBatches) ...[
          _PackagingBatchTile(
            packagingBatch: pb,
            jars: store.jarsForPackagingBatch(pb.packagingBatchId),
            store: store,
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PackagingBatchTile extends StatelessWidget {
  const _PackagingBatchTile({
    required this.packagingBatch,
    required this.jars,
    required this.store,
  });

  final PackagingBatch packagingBatch;
  final List<HoneyJar> jars;
  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    final anchored = packagingBatch.status == 'ANCHORED';
    final pb = packagingBatch;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(
          color: anchored ? AppTheme.green : AppTheme.border,
          width: anchored ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pb.packagingBatchId,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              StatusPill(
                label: anchored
                    ? store.tr('org.detail.jars.anchored')
                    : store.tr('org.portal.batch.status.created'),
                color: anchored ? AppTheme.green : AppTheme.orange,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${store.tr('passport.packaging.batch')}: ${pb.sourceBatchId} · '
            '${formatDate(pb.packagingDate)}',
            style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
          ),
          const SizedBox(height: 4),
          Text(
            store
                .tr('org.detail.jars.count')
                .replaceFirst('{count}', '${pb.jarCount}')
                .replaceFirst('{size}', '${pb.jarSizeGrams}g'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.inkSoft,
            ),
          ),
          if (jars.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final jar in jars) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: AppTheme.cardCream,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cookie_outlined, color: AppTheme.orange, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            jar.jarId,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.ink,
                            ),
                          ),
                          Text(
                            '${jar.packageSize} · ${jar.buyerId}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HoneyPassportScreen(jar: jar),
                        ),
                      ),
                      child: Text(store.tr('marketplace.view.passport')),
                    ),
                  ],
                ),
              ),
            ],
          ],
          if (!anchored) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => _anchorPackaging(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.orangeDark,
                  side: const BorderSide(color: AppTheme.orangeDark),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.hub_outlined, size: 16),
                label: Text(
                  store.tr('org.detail.jars.anchor.btn'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _anchorPackaging(BuildContext context) {
    store.anchorPackagingBatch(packagingBatch);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store.tr('org.detail.jars.anchor.toast')),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ProductQrCards extends StatelessWidget {
  const _ProductQrCards({required this.products});

  final List<ProductBatch> products;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Column(
      children: [
        for (final product in products) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: AppTheme.radiusCard,
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                ProductQrWidget(productCode: product.productCode, size: 96),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productCode,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${product.size.label} · ${formatDate(product.createdAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.inkFaint,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        store
                            .tr('org.detail.parent.batch')
                            .replaceFirst(
                                '{code}',
                                store.batchById(product.parentBatchId)?.code ??
                                    product.parentBatchId),
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
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}