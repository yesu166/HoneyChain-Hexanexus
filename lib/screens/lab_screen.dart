import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_header.dart';
import '../widgets/section_header.dart';
import '../widgets/status_pill.dart';
import 'batch_detail_screen.dart';
import 'blockchain_screen.dart';

class LabScreen extends StatelessWidget {
  const LabScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final batches = store.batches;
        final verified = batches.where((b) => store.verificationsFor(b).isNotEmpty && store.verificationsFor(b).first.status == VerificationStatus.pass).length;
        return Scaffold(
          appBar: AppBar(title: Text(store.tr('lab.title'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BrandHeader(subtitle: store.tr('lab.regional')),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockchainScreen())),
                  icon: const Icon(Icons.link),
                  label: Text(store.tr('lab.view.blockchain')),
                ),
              ),
              const SizedBox(height: 20),
              SectionHeader(title: store.tr('lab.verify.title').replaceFirst('{count}', '$verified'), seeAllLabel: ''),
              const SizedBox(height: 8),
              Text(store.tr('lab.evidence.note'), style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 12),
              if (batches.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(store.tr('lab.no.batches'), style: const TextStyle(color: Colors.black54))))
              else
                for (final batch in batches) ...[
                  _VerificationCard(batch: batch),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final verification = store.verificationsFor(batch).firstOrNull;
    final anchors = store.anchorsFor(batch);
    final decided = verification != null;

    String label;
    if (verification == null) {
      label = StatusPill.pending;
    } else if (verification.status == VerificationStatus.pass) {
      label = store.tr('status.pass');
    } else {
      label = store.tr('status.fail');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BatchDetailScreen(batch: batch))),
                    child: Text(batch.code, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ),
                StatusPill(label: label),
              ],
            ),
            const SizedBox(height: 6),
            Text('${batch.honeyType} · ${batch.origin}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 12),
            if (!decided)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        store.verifyV2Batch(batch, VerificationStatus.pass);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('lab.verified.pass'))));
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(store.tr('status.pass')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        store.verifyV2Batch(batch, VerificationStatus.fail);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('lab.marked.fail'))));
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: Text(store.tr('status.fail')),
                    ),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  const Icon(Icons.science_outlined, color: AppTheme.honeyDark, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      verification.status == VerificationStatus.pass
                          ? store.tr('lab.result.pass.desc')
                          : store.tr('lab.result.fail.desc'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (anchors.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(store.tr('lab.anchored.mock'), style: const TextStyle(color: Colors.black45, fontSize: 12)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
