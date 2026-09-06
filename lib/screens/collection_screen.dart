import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import 'lab_screen.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final batch = store.batch;
        final accepted = batch.custodyAccepted;

        return Scaffold(
          appBar: AppBar(title: Text(store.tr('collection.title'))),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                store.tr('collection.batch.custody'),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                store.tr('collection.subtitle'),
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 28),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            store.tr('collection.incoming'),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Chip(
                            label: Text(
                              accepted
                                  ? store.tr('collection.custody.accepted')
                                  : store.tr('collection.awaiting.custody'),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor:
                                (accepted ? Colors.green : Colors.amber)
                                    .withValues(alpha: 0.12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      _row(store.tr('collection.batch.id'), batch.id),
                      _row(store.tr('collection.producer'), batch.beekeeper),
                      _row(store.tr('collection.origin'), batch.origin),
                      _row(store.tr('collection.honey.type'), batch.honeyType),
                      _row(store.tr('collection.harvest.date'), batch.harvestDate),
                      _row(store.tr('collection.quantity.kg'), '${batch.quantity} kg'),

                      const SizedBox(height: 20),

                      if (accepted)
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  store.tr('collection.accepted.desc'),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, color: Colors.amber),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  store.tr('collection.pending.desc'),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () {
                            if (accepted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LabScreen(),
                                ),
                              );
                              return;
                            }
                            store.acceptCustody();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  store.tr('collection.custody.recorded.snackbar'),
                                ),
                              ),
                            );
                          },
                          icon: Icon(
                            accepted
                                ? Icons.science_outlined
                                : Icons.inventory_2,
                          ),
                          label: Text(
                            accepted
                                ? store.tr('collection.continue.lab')
                                : store.tr('collection.accept.custody'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.tr('fpo.chain.of.custody'),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ChainNode(
                        icon: '🐝',
                        label: store.tr('collection.chain.node.beekeeper'),
                        sub: store.tr('collection.chain.node.beekeeper.sub'),
                        state: ChainState.done,
                      ),
                      _ChainLink(),
                      _ChainNode(
                        icon: '📦',
                        label: store.tr('collection.chain.node.processor'),
                        sub: accepted ? store.tr('collection.chain.node.processor.accepted') : store.tr('collection.chain.node.processor.current'),
                        state: ChainState.current,
                      ),
                      _ChainLink(),
                      _ChainNode(
                        icon: '🧪',
                        label: store.tr('collection.chain.node.lab'),
                        sub: store.tr('collection.chain.node.pending'),
                        state: ChainState.pending,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          SizedBox(
            width: 100,
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

enum ChainState { done, current, pending }

class _ChainNode extends StatelessWidget {
  final String icon;
  final String label;
  final String sub;
  final ChainState state;

  const _ChainNode({
    required this.icon,
    required this.label,
    required this.sub,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      ChainState.done => Colors.green,
      ChainState.current => Colors.amber.shade800,
      ChainState.pending => Colors.black38,
    };
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: color.withValues(alpha: 0.12),
          child: Text(icon, style: const TextStyle(fontSize: 18)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: state == ChainState.pending ? Colors.black54 : null,
                ),
              ),
              Text(sub, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
        ),
        if (state != ChainState.pending)
          Icon(Icons.check_circle, color: Colors.green, size: 18)
        else
          const SizedBox.shrink(),
      ],
    );
  }
}

class _ChainLink extends StatelessWidget {
  const _ChainLink();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 20),
      height: 26,
      width: 2,
      color: Colors.amber.shade200,
    );
  }
}
