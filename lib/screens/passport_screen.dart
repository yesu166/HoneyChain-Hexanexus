import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../widgets/status_badge.dart';

class PassportScreen extends StatelessWidget {
  const PassportScreen({super.key, required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final anchors = store.anchorsFor(batch);
    final verifications = store.verificationsFor(batch);
    final verifier = verifications.isNotEmpty ? verifications.first.status.name : store.tr('consumer.lab.pending');

    return Scaffold(
      appBar: AppBar(title: Text(store.tr('passport.title'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Center(child: Container(width: double.infinity, padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.amber.shade200)),
          child: Column(children: [
            const Icon(Icons.verified, size: 56, color: Colors.green),
            const SizedBox(height: 8),
            Text(store.tr('passport.verified.honey'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(batch.code, style: const TextStyle(color: Colors.black54)),
          ]))),
        const SizedBox(height: 18),
        Text(store.tr('passport.batch.identity'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
          _row(store.tr('passport.batch.id'), batch.code),
          _row(store.tr('passport.honey.type'), batch.honeyType),
          _row(store.tr('passport.origin'), batch.origin),
          _row(store.tr('passport.producer.fpo'), store.activeFpoOrg.name),
          _row(store.tr('passport.quantity'), '${batch.quantityKg.toStringAsFixed(1)} kg'),
          _row(store.tr('passport.batch.status'), batch.status.name),
        ]))),
        const SizedBox(height: 18),
        Text(store.tr('passport.trace.journey'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _journeyStep(store.tr('passport.step.hive'), store.tr('passport.step.hive.sub'), true),
          _journeyStep(store.tr('passport.step.fpo'), store.tr('passport.step.fpo.sub'), true),
          _journeyStep(store.tr('role.lab'), verifier == store.tr('status.pass') ? store.tr('passport.step.lab.done') : store.tr('passport.step.lab.pending').replaceFirst('{status}', verifier.toUpperCase()), verifications.isNotEmpty),
          _journeyStep(store.tr('passport.step.blockchain'), anchors.isNotEmpty ? store.tr('passport.step.blockchain.anchored') : store.tr('passport.step.blockchain.not'), anchors.isNotEmpty),
          _journeyStep(store.tr('passport.step.marketplace'), batch.status == BatchStatus.listed || batch.status == BatchStatus.completed ? store.tr('passport.step.listed') : store.tr('passport.step.not.listed'), batch.status == BatchStatus.listed || batch.status == BatchStatus.completed),
          _journeyStep(store.tr('passport.step.consumer'), store.tr('passport.step.consumer.sub'), true),
        ]))),
        const SizedBox(height: 18),
        Text(store.tr('passport.blockchain.integrity'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
          if (anchors.isEmpty)
            Text(store.tr('passport.no.anchors'), style: const TextStyle(color: Colors.black54))
          else
            for (final anchor in anchors) ...[
              Row(children: [
                const Icon(Icons.link, color: Colors.deepPurple),
                const SizedBox(width: 10),
                Expanded(child: Text('${anchor.eventType} ${store.tr('blockchain.anchor.anchored')}', style: const TextStyle(fontWeight: FontWeight.bold))),
                StatusBadge(label: store.tr('status.anchored'), color: Colors.deepPurple),
              ]),
              const SizedBox(height: 4),
              Text(anchor.anchorId, style: const TextStyle(fontFamily: 'monospace')),
              const Divider(),
            ],
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [const Icon(Icons.info_outline, color: Colors.deepPurple, size: 18), const SizedBox(width: 10), Expanded(child: Text(store.tr('passport.anchor.infrastructure'), style: const TextStyle(fontSize: 12)))]),
          ),
        ]))),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back), label: Text(store.tr('action.back'))),
      ]),
    );
  }

  Widget _row(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
    SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.black54))),
    Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
  ]));

  Widget _journeyStep(String title, String subtitle, bool done) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? Colors.green : Colors.black26, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(subtitle, style: const TextStyle(color: Colors.black54)),
      ])),
    ]),
  );
}
