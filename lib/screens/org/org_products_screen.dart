import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../models/domain.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/product_qr.dart';

/// All packaged product batches for the active organization, with their
/// consumer QR codes (which open the Honey Passport when tapped).
class OrgProductsScreen extends StatelessWidget {
  const OrgProductsScreen({super.key});

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
          store.tr('org.products.appbar'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final products = store.productBatches;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              _InfoBanner(count: products.length),
              const SizedBox(height: 18),
              if (products.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: AppTheme.radiusCard,
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    store.tr('org.products.no.products'),
                    style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
                  ),
                )
              else
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final product in products)
                      _ProductCard(product: product, store: store),
                  ],
                ),
              const SizedBox(height: 24),
              Text(
                store.tr('org.products.qr.note'),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.inkFaint,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              color: AppTheme.orangeSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.qr_code_rounded,
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
                  store.tr('org.products.consumer.ready'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  store
                      .tr('org.products.packaged.count')
                      .replaceFirst('{count}', '$count')
                      .replaceFirst('{org}', store.activeFpoOrg.name),
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

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.store});

  final ProductBatch product;
  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    final parent = store.batchById(product.parentBatchId);
    return Container(
      width: (MediaQuery.of(context).size.width - 20 * 2 - 12) / 2,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          ProductQrWidget(productCode: product.productCode, size: 108),
          const SizedBox(height: 10),
          Text(
            product.productCode,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${product.size.label} · ${formatDate(product.createdAt)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint),
          ),
          const SizedBox(height: 2),
          Text(
            parent?.code ?? '',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.orangeDark,
            ),
          ),
        ],
      ),
    );
  }
}