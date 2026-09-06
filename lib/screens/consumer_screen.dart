import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_header.dart';
import '../widgets/journey_timeline.dart';
import '../widgets/product_qr.dart';
import '../widgets/section_header.dart';
import '../widgets/status_pill.dart';
import 'honey_passport_screen.dart';
import 'passport_screen.dart';

class ConsumerScreen extends StatefulWidget {
  const ConsumerScreen({super.key});

  @override
  State<ConsumerScreen> createState() => _ConsumerScreenState();
}

class _ConsumerScreenState extends State<ConsumerScreen> {
  final controller = TextEditingController();
  final store = HoneyChainStore.instance;
  String? lastVerifiedId;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _verifyById() {
    final entered = controller.text.trim();
    if (entered.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('consumer.enter.batch.id'))));
      return;
    }
    // A jar payload (e.g. honeychain://jar/JAR-HC-000001) resolves to the
    // individual jar passport, keeping the full batch genealogy.
    final jar = store.resolveJar(entered);
    if (jar != null) {
      setState(() => lastVerifiedId = jar.jarId);
      final jarBatch = store.batchById(jar.sourceBatchId);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HoneyPassportScreen(batch: jarBatch, jar: jar),
        ),
      );
      return;
    }
    // A product code (e.g. HC-TN-00128-A) maps to a product-level Honey Passport.
    final product = store.productByCode(entered.toUpperCase());
    if (product != null) {
      setState(() => lastVerifiedId = product.productCode);
      Navigator.push(context, MaterialPageRoute(builder: (_) => HoneyPassportFromProductScreen(productCode: product.productCode)));
      return;
    }
    final batch = store.batchForPassport(entered.toLowerCase()) ??
        store.batches.where((b) => b.code.toLowerCase() == entered.toLowerCase()).firstOrNull;
    if (batch != null) {
      setState(() => lastVerifiedId = batch.code);
      Navigator.push(context, MaterialPageRoute(builder: (_) => PassportScreen(batch: batch)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('consumer.not.found'))));
    }
  }

  void _simulateScan() {
    final batch = store.seededDemoBatch();
    if (batch != null) {
      setState(() => lastVerifiedId = batch.code);
      Navigator.push(context, MaterialPageRoute(builder: (_) => PassportScreen(batch: batch)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('consumer.no.batch'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final batch = store.seededDemoBatch();
        return Scaffold(
          appBar: AppBar(title: Text(store.tr('consumer.appbar'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BrandHeader(subtitle: store.tr('consumer.verify.honey')),
              const SizedBox(height: 20),
              Card(
                color: AppTheme.cardCream,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(store.tr('consumer.title2'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(hintText: store.tr('consumer.hint'), isDense: true),
                              onSubmitted: (_) => _verifyById(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(onPressed: _verifyById, child: Text(store.tr('consumer.verify.button'))),
                        ],
                      ),
                      if (batch != null) ...[
                        const SizedBox(height: 8),
                        Text(store.tr('consumer.demo.batch').replaceFirst('{code}', batch.code), style: const TextStyle(color: Colors.black45, fontSize: 12)),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _simulateScan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(store.tr('consumer.scan.verify')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (batch != null) ...[
                SectionHeader(title: store.tr('passport.title'), seeAllLabel: ''),
                const SizedBox(height: 12),
                _PassportSummary(batch: batch, justVerified: lastVerifiedId == batch.code),
                const SizedBox(height: 22),
                SectionHeader(title: store.tr('batch.journey.title'), seeAllLabel: ''),
                const SizedBox(height: 12),
                _JourneyPanel(batch: batch),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PassportSummary extends StatelessWidget {
  const _PassportSummary({required this.batch, required this.justVerified});
  final Batch batch;
  final bool justVerified;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final verification = store.verificationsFor(batch).isNotEmpty ? store.verificationsFor(batch).first : null;
    final verified = verification != null && verification.status == VerificationStatus.pass;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.cardCream,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.honey.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Icon(verified ? Icons.verified : Icons.pending_outlined, size: 56, color: verified ? AppTheme.green : AppTheme.orange),
                  const SizedBox(height: 8),
                  Text(verified ? store.tr('status.verified.honey') : store.tr('status.verification.progress'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: verified ? null : AppTheme.orange)),
                  const SizedBox(height: 6),
                  Text(batch.code, style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            StatusPill(label: verified ? StatusPill.verified : StatusPill.pending),
            const SizedBox(height: 14),
            _row(store.tr('passport.batch.id'), batch.code),
            _row(store.tr('passport.honey.type'), batch.honeyType),
            _row(store.tr('passport.origin'), batch.origin),
            _row(store.tr('passport.quantity'), '${batch.quantityKg.toStringAsFixed(1)} kg'),
            _row(store.tr('role.lab'), verification != null ? verification.status.name : store.tr('consumer.lab.pending')),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PassportScreen(batch: batch))),
                icon: const Icon(Icons.qr_code),
                label: Text(store.tr('consumer.view.full.passport')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(width: 92, child: Text(label, style: const TextStyle(color: Colors.black54))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _JourneyPanel extends StatelessWidget {
  const _JourneyPanel({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final verification = store.verificationsFor(batch).firstOrNull;
    final anchors = store.anchorsFor(batch);
    final listed = store.marketplaceListings.where((l) => l.batchId == batch.id).isNotEmpty;
    final steps = [
      TimelineStep(title: store.tr('passport.step.hive'), subtitle: store.tr('passport.step.hive.sub'), done: true),
      TimelineStep(title: store.tr('passport.step.fpo'), subtitle: store.tr('batch.journey.entry.qc'), done: batch.status.index >= BatchStatus.collected.index),
      TimelineStep(title: store.tr('role.lab'), subtitle: verification != null ? 'Verified — ${verification.status.name}' : store.tr('status.pending'), done: verification != null && verification.status == VerificationStatus.pass),
      TimelineStep(title: store.tr('passport.step.blockchain'), subtitle: anchors.isNotEmpty ? store.tr('passport.step.blockchain.anchored') : store.tr('passport.step.blockchain.not'), done: anchors.isNotEmpty),
      TimelineStep(title: store.tr('passport.step.marketplace'), subtitle: listed ? store.tr('passport.step.listed') : store.tr('passport.step.not.listed'), done: listed),
    ];
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: JourneyTimeline(steps: steps)));
  }
}
