import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import 'collection_screen.dart';

import '../data/mock_data.dart';

class BeekeeperScreen extends StatelessWidget {
  const BeekeeperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final batch = MockData.batch;

    return Scaffold(
      appBar: AppBar(title: Text(store.tr('beekeeper.title'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CollectionScreen()),
          );
        },
        icon: const Icon(Icons.add),
        label: Text(store.tr('beekeeper.register.batch')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Welcome, Ravi ??',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            store.tr('beekeeper.subtitle'),
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 28),
          Text(
            store.tr('beekeeper.section.batches'),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.hexagon_outlined,
                        color: Colors.amber,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          batch.id,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Chip(label: Text(batch.status)),
                    ],
                  ),
                  const Divider(height: 28),
                  _InfoRow(store.tr('batch.info.honey'), batch.honeyType),
                  _InfoRow(store.tr('batch.info.origin'), batch.origin),
                  _InfoRow(store.tr('batch.info.harvest'), batch.harvestDate),
                  _InfoRow(store.tr('batch.info.quantity'), '${batch.quantity} kg'),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(Icons.verified, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        store.tr('status.lab.verified'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      const Icon(Icons.link, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(
                        store.tr('status.blockchain.recorded'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 90,
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
