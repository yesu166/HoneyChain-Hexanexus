import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/honey_batch.dart';
import 'collection_screen.dart';

class RegisterBatchScreen extends StatefulWidget {
  const RegisterBatchScreen({super.key});

  @override
  State<RegisterBatchScreen> createState() => _RegisterBatchScreenState();
}

class _RegisterBatchScreenState extends State<RegisterBatchScreen> {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController(text: 'Beekeeper');
  final originController = TextEditingController(text: 'Tamil Nadu');
  final honeyController = TextEditingController(text: 'Multifloral Honey');
  final quantityController = TextEditingController(text: '25');

  String harvestDate = '27 Aug 2026';

  @override
  void dispose() {
    nameController.dispose();
    originController.dispose();
    honeyController.dispose();
    quantityController.dispose();
    super.dispose();
  }

  void createBatch() {
    if (!formKey.currentState!.validate()) return;

    final quantity = double.tryParse(quantityController.text.trim()) ?? 0;

    final batch = HoneyChainStore.instance.registerBatch(
      beekeeper: nameController.text.trim(),
      origin: originController.text.trim(),
      honeyType: honeyController.text.trim(),
      harvestDate: harvestDate,
      quantity: quantity,
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) => _BatchCreatedDialog(
        batch: batch,
        onContinue: () {
          Navigator.of(dialogContext).pop();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const CollectionScreen()),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      appBar: AppBar(title: Text(store.tr('register.batch.title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  store.tr('register.batch.heading'),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  store.tr('register.batch.subtitle'),
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 28),

                _input(nameController, store.tr('register.batch.beekeeper'), Icons.person_outline, store: store),

                _input(
                  originController,
                  store.tr('register.batch.origin'),
                  Icons.location_on_outlined,
                  store: store,
                ),

                _input(
                  honeyController,
                  store.tr('register.batch.honey.type'),
                  Icons.water_drop_outlined,
                  store: store,
                ),

                _input(
                  quantityController,
                  store.tr('register.batch.quantity'),
                  Icons.scale_outlined,
                  number: true,
                  store: store,
                ),

                const SizedBox(height: 8),

                Card(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today),
                    title: Text(store.tr('register.batch.harvest.date')),
                    subtitle: Text(harvestDate),
                    trailing: const Icon(Icons.edit_calendar),
                    onTap: _pickHarvestDate,
                  ),
                ),

                const SizedBox(height: 30),

                SizedBox(
                  height: 55,
                  child: FilledButton.icon(
                    onPressed: createBatch,
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(store.tr('register.batch.create')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickHarvestDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date == null || !mounted) return;
    setState(() {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      harvestDate = '${date.day} ${months[date.month - 1]} ${date.year}';
    });
  }

  Widget _input(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool number = false,
    required HoneyChainStore store,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        keyboardType: number ? TextInputType.number : TextInputType.text,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return store.tr('text.required');
          }
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _BatchCreatedDialog extends StatelessWidget {
  final HoneyBatch batch;
  final VoidCallback onContinue;

  const _BatchCreatedDialog({required this.batch, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green),
          const SizedBox(width: 10),
          Text(store.tr('register.batch.created')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                batch.id,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _row(store.tr('register.batch.beekeeper'), batch.beekeeper),
            _row(store.tr('register.batch.origin'), batch.origin),
            _row(store.tr('register.batch.honey.type'), batch.honeyType),
            _row(store.tr('register.batch.harvest.date'), batch.harvestDate),
            _row(store.tr('register.batch.quantity'), '${batch.quantity} kg'),
            const SizedBox(height: 10),
            Text(
              store.tr('register.batch.next'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          onPressed: onContinue,
          icon: const Icon(Icons.arrow_forward),
          label: Text(store.tr('register.batch.continue')),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
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
