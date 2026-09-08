import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../widgets/batch_card.dart';
import '../widgets/info_tile.dart';
import '../widgets/journey_timeline.dart';
import '../widgets/status_pill.dart';
import 'honey_passport_screen.dart';
import 'lab_screen.dart';
import 'marketplace_screen.dart';

class BatchDetailScreen extends StatelessWidget {
  const BatchDetailScreen({super.key, required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final verification = store.verificationsFor(batch).isNotEmpty ? store.verificationsFor(batch).first : null;
    final anchors = store.anchorsFor(batch);
    final listed = store.marketplaceListings.where((l) => l.batchId == batch.id).isNotEmpty;

    final steps = [
      TimelineStep(title: store.tr('passport.step.hive'), subtitle: store.tr('passport.step.hive.sub'), done: true),
      TimelineStep(title: store.tr('passport.step.fpo'), subtitle: store.tr('passport.step.fpo.sub'), done: batch.status.index >= BatchStatus.collected.index),
      TimelineStep(title: store.tr('passport.step.lab.done'), subtitle: verification != null ? store.tr('batch.detail.step.verified').replaceFirst('{status}', verification.status.name) : store.tr('status.pending'), done: verification != null && verification.status == VerificationStatus.pass),
      TimelineStep(title: store.tr('passport.step.blockchain'), subtitle: anchors.isNotEmpty ? store.tr('passport.step.blockchain.anchored') : store.tr('passport.step.blockchain.not'), done: anchors.isNotEmpty),
      TimelineStep(title: store.tr('passport.step.marketplace'), subtitle: listed ? store.tr('batch.detail.step.listed') : store.tr('batch.detail.step.not.listed'), done: listed),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(batch.code)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(child: Text(batch.code, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              StatusPill(label: batchStatusLabel(batch.status)),
            ],
          ),
          const SizedBox(height: 6),
          Text(batch.honeyType, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(label: store.tr('batch.detail.quantity'), value: '${batch.quantityKg.toStringAsFixed(1)} kg', icon: Icons.scale_outlined),
              const SizedBox(width: 12),
              _Stat(label: store.tr('batch.detail.origin'), value: batch.origin, icon: Icons.place_outlined),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.tr('batch.detail.details'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  InfoTile.row(store.tr('batch.detail.id'), batch.code),
                  InfoTile.row(store.tr('batch.detail.honey'), batch.honeyType),
                  InfoTile.row(store.tr('batch.detail.quantity'), '${batch.quantityKg.toStringAsFixed(1)} kg'),
                  InfoTile.row(store.tr('batch.detail.origin'), batch.origin),
                  InfoTile.row(store.tr('batch.detail.created'), '${batch.createdAt.day} Aug ${batch.createdAt.year}'),
                  InfoTile.row(store.tr('batch.detail.lab'), verification != null ? verification.status.name : store.tr('status.pending')),
                  InfoTile.row(store.tr('batch.detail.processing'), batch.status.name),
                  InfoTile.row(store.tr('batch.detail.marketplace'), listed ? store.tr('batch.detail.listed') : store.tr('batch.detail.not.listed')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(store.tr('batch.detail.traceability'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: JourneyTimeline(steps: steps))),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HoneyPassportScreen(batch: batch))),
              icon: const Icon(Icons.qr_code),
              label: Text(store.tr('batch.detail.view.qr')),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LabScreen())),
                  icon: const Icon(Icons.science_outlined),
                  label: Text(store.tr('batch.detail.lab')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketplaceScreen())),
                  icon: const Icon(Icons.storefront_outlined),
                  label: Text(store.tr('batch.detail.marketplace')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, color: AppTheme.honeyDark, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ])),
          ]),
        ),
      ),
    );
  }
}
