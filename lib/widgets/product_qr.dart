import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// A real QR code encoding a deterministic traceability handle for a product
/// batch (or an individual jar's payload).
///
/// The QR does not embed the full genealogy; it encodes a stable trace handle
/// (e.g. `honeychain://trace/<productCode>`) that a consumer scans or pastes
/// to open the Honey Passport. The payload is environment-independent so the
/// same QR is valid on web, mobile, and in the demo.
class ProductQrWidget extends StatelessWidget {
  const ProductQrWidget({
    super.key,
    required this.productCode,
    this.size = 140,
  });

  final String productCode;
  final double size;

  /// The deterministic trace handle the QR encodes.
  String traceUrl() {
    return 'honeychain://trace/${productCode.toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final url = traceUrl();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          QrImageView(
            data: url,
            version: QrVersions.auto,
            size: size,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF2E2417),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF2E2417),
            ),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 6),
          Text(
            productCode,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () async {
              if (store.isFpoRole || store.loggedIn) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HoneyPassportFromProductScreen(
                      productCode: productCode,
                    ),
                  ),
                );
              }
            },
            child: Text(
              store.tr('qr.tap.passport'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.orangeDark,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Consumer-facing Honey Passport shown when a product QR is scanned.
/// Looks up the product batch and its parent genealogy.
class HoneyPassportFromProductScreen extends StatelessWidget {
  const HoneyPassportFromProductScreen({super.key, required this.productCode});

  final String productCode;

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
          store.tr('qr.passport.title'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final product = store.productByCode(productCode);
          final batch = product != null ? store.batchById(product.parentBatchId) : null;
          final harvests = batch != null ? store.harvestsForBatch(batch) : <Harvest>[];
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              if (product == null || batch == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 60),
                    child: Text(
                      store
                          .tr('qr.product.not.found')
                          .replaceFirst('{code}', productCode),
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.inkSoft),
                    ),
                  ),
                )
              else ...[
                _PassportHeader(product: product, batch: batch),
                const SizedBox(height: 20),
                _SectionLabel(store.tr('qr.origin.potential')),
                _OriginCard(store: store, batch: batch, harvests: harvests),
                const SizedBox(height: 20),
                _SectionLabel(store.tr('qr.quality')),
                _QualityCard(batch: batch),
                const SizedBox(height: 26),
                Center(
                  child: Text(
                    store.tr('qr.scan.note'),
                    style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PassportHeader extends StatelessWidget {
  const _PassportHeader({required this.product, required this.batch});

  final ProductBatch product;
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final verified = batch.status == BatchStatus.labVerified;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(
          color: verified ? AppTheme.green : AppTheme.orange,
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: (verified ? AppTheme.green : AppTheme.orange)
                  .withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              verified ? Icons.verified_rounded : Icons.local_drink_outlined,
              color: verified ? AppTheme.green : AppTheme.orange,
              size: 30,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            verified
                ? store.tr('qr.authenticated')
                : store.tr('qr.pending.verification'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: verified ? AppTheme.green : AppTheme.orange,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${product.productCode} · ${product.size.label}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            store
                .tr('qr.parent.batch')
                .replaceFirst('{code}', batch.code),
            style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _OriginCard extends StatelessWidget {
  const _OriginCard({
    required this.store,
    required this.batch,
    required this.harvests,
  });

  final HoneyChainStore store;
  final Batch batch;
  final List<Harvest> harvests;

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
          _InfoRow(label: store.tr('qr.info.batch'), value: batch.code),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(label: store.tr('qr.info.honey.type'), value: batch.honeyType),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(label: store.tr('qr.info.origin'), value: batch.origin),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(
            label: store.tr('qr.info.source.hives'),
            value: harvests.isEmpty
                ? batch.origin
                : harvests.map((h) => store.hiveName(h.hiveId)).join(', '),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _InfoRow(
            label: store.tr('qr.info.total.batch'),
            value: '${formatKg(batch.quantityKg)} kg',
          ),
        ],
      ),
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final verified = batch.status == BatchStatus.labVerified;
    return Column(
      children: [
        _QualityRow(label: store.tr('qr.quality.moisture'), ok: verified),
        _QualityRow(label: store.tr('qr.quality.sugar'), ok: verified),
        _QualityRow(label: store.tr('qr.quality.lab.ref'), ok: verified),
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 20,
            color: ok ? AppTheme.green : AppTheme.grey,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.inkFaint,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: AppTheme.inkFaint,
        ),
      ),
    );
  }
}