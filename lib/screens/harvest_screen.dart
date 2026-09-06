import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';

class CreateBatchScreen extends StatefulWidget {
  const CreateBatchScreen({super.key});
  @override
  State<CreateBatchScreen> createState() => _CreateBatchScreenState();
}

class _CreateBatchScreenState extends State<CreateBatchScreen> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(store.tr('batch.create.title'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text(store.tr('batch.select.harvests'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(store.tr('batch.select.subtitle'), style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 14),
        if (store.harvests.isEmpty)
          Text(store.tr('batch.no.harvests'), style: const TextStyle(color: Colors.black54))
        else ...[
          for (final harvest in store.harvests)
            CheckboxListTile(
              value: _selected.contains(harvest.id),
              onChanged: (value) => setState(() => value == true ? _selected.add(harvest.id) : _selected.remove(harvest.id)),
              title: Text('${harvest.honeyType} — ${harvest.quantityKg.toStringAsFixed(0)} kg'),
              subtitle: Text('${harvest.harvestedAt.day} Aug 2026  |  ${_harvestHive(store, harvest.hiveId)}'),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _selected.isEmpty
                ? null
                : () {
                    final selected = store.harvests.where((harvest) => _selected.contains(harvest.id)).toList();
                    final batch = store.createBatchFromHarvests(selected);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('batch.created').replaceFirst('{batch}', batch.code))));
                    Navigator.pop(context);
                  },
            icon: const Icon(Icons.hexagon_outlined),
            label: Text(store.tr('batch.create.title')),
          ),
        ],
      ]),
    );
  }

  String _harvestHive(HoneyChainStore store, String hiveId) {
    for (final hive in store.hives) {
      if (hive.id == hiveId) return hive.name;
    }
    return store.tr('text.unknown.hive');
  }
}
