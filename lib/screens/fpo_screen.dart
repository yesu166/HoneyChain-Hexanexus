import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../widgets/batch_card.dart';
import '../widgets/brand_header.dart';
import '../widgets/section_header.dart';
import '../widgets/status_pill.dart';
import 'batch_detail_screen.dart';
import 'create_batch_screen.dart';

class FpoScreen extends StatelessWidget {
  const FpoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final batches = store.batches;
        final pendingCustody = batches.where((b) => b.status == BatchStatus.created).length;
        final pendingLab = batches.where((b) => b.status == BatchStatus.collected || b.status == BatchStatus.labPending).length;
        return Scaffold(
          appBar: AppBar(title: Text(store.tr('fpo.title'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BrandHeader(subtitle: store.tr('fpo.fpo.name')),
              const SizedBox(height: 20),
              Row(
                children: [
                  _Stat(label: store.tr('fpo.pending.custody'), value: '$pendingCustody', icon: Icons.inventory_2_outlined),
                  const SizedBox(width: 12),
                  _Stat(label: store.tr('fpo.pending.lab'), value: '$pendingLab', icon: Icons.science_outlined),
                  const SizedBox(width: 12),
                  _Stat(label: store.tr('fpo.total.batches'), value: '${batches.length}', icon: Icons.hexagon_outlined),
                ],
              ),
              const SizedBox(height: 20),
              SectionHeader(
                title: store.tr('my.batches.title'),
                onSeeAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateBatchScreen())),
                seeAllLabel: store.tr('fpo.create.batch'),
              ),
              const SizedBox(height: 12),
              if (batches.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(store.tr('fpo.no.batches'), style: const TextStyle(color: Colors.black54))))
              else
                for (final batch in batches) ...[
                  BatchCard(
                    batch: batch,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BatchDetailScreen(batch: batch))),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 20),
              SectionHeader(title: store.tr('fpo.chain.of.custody'), seeAllLabel: ''),
              const SizedBox(height: 12),
              if (batches.isEmpty)
                const SizedBox.shrink()
              else
                for (final batch in batches) _CustodyCard(batch: batch),
            ],
          ),
        );
      },
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
          child: Column(
            children: [
              Icon(icon, color: const Color(0xFFB97B1B)),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustodyCard extends StatelessWidget {
  const _CustodyCard({required this.batch});
  final Batch batch;
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final custody = store.custodyFor(batch);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(batch.code, style: const TextStyle(fontWeight: FontWeight.w800))),
                StatusPill(label: custody.isEmpty ? StatusPill.pending : StatusPill.verified),
              ],
            ),
            const SizedBox(height: 8),
            if (custody.isEmpty)
              Text(store.tr('fpo.no.custody'), style: const TextStyle(color: Colors.black54, fontSize: 13))
            else
              for (final event in custody)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(event.note),
                  subtitle: Text('${event.recordedAt.day} Aug ${event.recordedAt.year}'),
                ),
            if (custody.isEmpty && (batch.status == BatchStatus.created || batch.status == BatchStatus.collected)) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    store.acceptV2Custody(batch);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('fpo.custody.accepted.snackbar'))));
                  },
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(store.tr('fpo.accept.custody')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
