import 'package:flutter/material.dart';

import '../data/demo_seed.dart';
import '../data/honeychain_store.dart';
import '../models/domain.dart';

class CreateBatchScreen extends StatefulWidget {
  const CreateBatchScreen({super.key});
  @override
  State<CreateBatchScreen> createState() => _CreateBatchScreenState();
}

class _CreateBatchScreenState extends State<CreateBatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _honey = TextEditingController(text: 'Multifloral Honey');
  final _quantity = TextEditingController(text: '12');
  final _location = TextEditingController(text: 'Kotagiri, Tamil Nadu');
  final Set<String> _selectedHives = {};
  final _beekeeper = TextEditingController(text: 'Ravi Kumar');
  DateTime _harvestDate = DemoSeed.now;

  @override
  void dispose() {
    _honey.dispose();
    _quantity.dispose();
    _location.dispose();
    _beekeeper.dispose();
    super.dispose();
  }

  void _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _harvestDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
    );
    if (date != null) setState(() => _harvestDate = date);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final quantity = double.tryParse(_quantity.text) ?? 0;
    final harvests = _selectedHives.map((hiveId) {
      final hive = HoneyChainStore.instance.hives.where((h) => h.id == hiveId).firstOrNull;
      return Harvest(
        id: 'harvest-${DateTime.now().microsecondsSinceEpoch}-$hiveId',
        hiveId: hiveId,
        beekeeperId: HoneyChainStore.instance.currentBeekeeper.id,
        harvestedAt: _harvestDate,
        honeyType: hive?.honeyType ?? _honey.text,
        quantityKg: quantity / (_selectedHives.isEmpty ? 1 : _selectedHives.length),
      );
    }).toList();

    final batch = HoneyChainStore.instance.createBatchDirect(
      honeyType: _honey.text.trim(),
      origin: _location.text.trim(),
      quantityKg: quantity,
      harvests: harvests,
    );
    Navigator.pop(context, true);
    // Surface for consumers/producers to reach batch directly
    _onCreated(context, batch);
  }

  void _onCreated(BuildContext context, Batch batch) {}

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(store.tr('create.batch.appbar'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(store.tr('create.batch.heading'),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(store.tr('create.batch.desc'),
                    style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 24),
                TextFormField(
                    controller: _beekeeper,
                    decoration: InputDecoration(
                        labelText: store.tr('create.batch.beekeeper'),
                        prefixIcon: const Icon(Icons.person_outline)),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? store.tr('create.batch.required') : null),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _honey,
                    decoration: InputDecoration(
                        labelText: store.tr('create.batch.honey.type'),
                        prefixIcon: const Icon(Icons.water_drop_outlined)),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? store.tr('create.batch.required') : null),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: store.tr('create.batch.quantity'),
                        prefixIcon: const Icon(Icons.scale_outlined)),
                    validator: (v) => (double.tryParse(v ?? '') ?? 0) > 0
                        ? null
                        : store.tr('create.batch.qty.error')),
                const SizedBox(height: 14),
                TextFormField(
                    controller: _location,
                    decoration: InputDecoration(
                        labelText: store.tr('create.batch.origin'),
                        prefixIcon: const Icon(Icons.location_on_outlined)),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? store.tr('create.batch.required') : null),
                const SizedBox(height: 14),
                _DateTile(text: '${_harvestDate.day} Aug ${_harvestDate.year}', onTap: _pickDate),
                const SizedBox(height: 20),
                Text(store.tr('create.batch.hives.label'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (store.hives.isEmpty)
                  Text(store.tr('create.batch.no.hives'),
                      style: const TextStyle(color: Colors.black54))
                else
                  for (final hive in store.hives)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _selectedHives.contains(hive.id),
                      onChanged: (v) => setState(() => v == true ? _selectedHives.add(hive.id) : _selectedHives.remove(hive.id)),
                      title: Text(hive.name),
                      subtitle: Text(hive.honeyType),
                    ),
                const SizedBox(height: 20),
                FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.check), label: Text(store.tr('create.batch.btn'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.calendar_today),
        title: Text(HoneyChainStore.instance.tr('create.batch.harvest.date')),
        subtitle: Text(text),
        trailing: const Icon(Icons.edit_calendar),
        onTap: onTap,
      ),
    );
  }
}
