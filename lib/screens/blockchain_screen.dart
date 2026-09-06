import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../widgets/status_badge.dart';
import 'passport_screen.dart';
import 'regulator_screen.dart';

class BlockchainScreen extends StatefulWidget {
  const BlockchainScreen({super.key});

  @override
  State<BlockchainScreen> createState() => _BlockchainScreenState();
}

class _BlockchainScreenState extends State<BlockchainScreen> {
  final store = HoneyChainStore.instance;
  Batch? _batch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = store.activeV2Batch ?? (store.batches.isNotEmpty ? store.batches.first : null);
      if (target != null && target.status == BatchStatus.labVerified && store.anchorsFor(target).isEmpty) {
        store.anchorV2Batch(target, 'LAB_VERIFICATION');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        _batch = store.activeV2Batch ?? (store.batches.isNotEmpty ? store.batches.first : null);
        final batch = _batch;
        if (batch == null) {
          return Scaffold(
            appBar: AppBar(title: Text(store.tr('blockchain.evidence.title'))),
            body: Center(child: Text(store.tr('blockchain.no.batch'))),
          );
        }
        final anchors = store.anchorsFor(batch);
        final anchored = anchors.isNotEmpty;
        final verifyTimestamp = store.verificationsFor(batch).isNotEmpty ? store.verificationsFor(batch).first.testedAt : null;

        return Scaffold(
          appBar: AppBar(title: Text(store.tr('blockchain.evidence.title'))),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurple.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.science_outlined,
                      color: Colors.deepPurple,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        store.tr('blockchain.mock.notice'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text(
                store.tr('blockchain.integrity.title'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                store.tr('blockchain.integrity.desc'),
                style: const TextStyle(color: Colors.black54, height: 1.5),
              ),
              const SizedBox(height: 20),

              if (!anchored)
                _PendingCard(batch: batch)
              else
                _EvidenceCard(
                  batch: batch,
                  verifier: store.tr('blockchain.regulatory.lab'),
                  verifyTimestamp: verifyTimestamp != null ? '${verifyTimestamp.day} Aug ${verifyTimestamp.year}' : store.tr('text.placeholder'),
                  anchors: anchors,
                ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PassportScreen(batch: batch),
                          ),
                        );
                      },
                      icon: const Icon(Icons.qr_code_scanner),
                      label: Text(store.tr('blockchain.consumer.passport')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegulatorScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.gavel_outlined),
                      label: Text(store.tr('blockchain.regulator.audit')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  final Batch batch;
  final String verifier;
  final String verifyTimestamp;
  final List<BlockchainAnchor> anchors;

  const _EvidenceCard({
    required this.batch,
    required this.verifier,
    required this.verifyTimestamp,
    required this.anchors,
  });

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final anchor = anchors.isNotEmpty ? anchors.first : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, color: Colors.deepPurple),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store.tr('blockchain.anchored.record'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                StatusBadge(label: store.tr('status.anchored'), color: Colors.deepPurple),
              ],
            ),
            const Divider(height: 26),
            _row(store.tr('passport.batch.id'), batch.code),
            _row(store.tr('blockchain.event'), store.tr('blockchain.event.desc')),
            _row(store.tr('blockchain.verifier'), verifier),
            _row(store.tr('blockchain.timestamp'), verifyTimestamp),
            _row(store.tr('blockchain.verification.result'), store.tr('blockchain.result.pass')),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                anchor?.anchorId ?? '—',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final Batch batch;

  const _PendingCard({required this.batch});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hourglass_empty, color: Colors.amber),
                const SizedBox(width: 10),
                Text(
                  store.tr('blockchain.awaiting'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              batch.status == BatchStatus.labVerified
                  ? store.tr('blockchain.will.anchor').replaceFirst('{batch}', batch.code)
                  : store.tr('blockchain.needs.lab').replaceFirst('{batch}', batch.code),
              style: const TextStyle(color: Colors.black54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
