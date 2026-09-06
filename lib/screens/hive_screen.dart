import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../widgets/metric_card.dart';
import '../widgets/status_badge.dart';

class HiveScreen extends StatelessWidget {
  const HiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(store.tr('my.hives.title'))),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(store.tr('hive.health.heading'), style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(store.tr('hive.health.disclaimer'), style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 18),
            for (final hive in store.hives) _HiveCard(hive: hive),
          ],
        ),
      ),
    );
  }
}

class _HiveCard extends StatelessWidget {
  const _HiveCard({required this.hive});
  final Hive hive;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final insight = store.insightFor(hive);
    final color = insight.riskLevel == RiskLevel.healthy ? Colors.green : Colors.orange;
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HiveDetailScreen(hive: hive))),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.hive_outlined, color: Colors.amber, size: 30),
              const SizedBox(width: 10),
              Expanded(child: Text(hive.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              StatusBadge(label: insight.riskLevel == RiskLevel.healthy ? store.tr('hive.health.status.healthy') : store.tr('hive.health.status.attention'), color: color),
            ]),
            const SizedBox(height: 10),
            Text(hive.location, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 10),
            Text('${insight.healthScore}/100 ${store.tr('hive.health.score')}  |  ${hive.honeyType}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class HiveDetailScreen extends StatelessWidget {
  const HiveDetailScreen({super.key, required this.hive});
  final Hive hive;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final readings = store.readingsForHive(hive.id);
    final insight = store.insightFor(hive);
    final color = insight.riskLevel == RiskLevel.healthy ? Colors.green : Colors.orange;
    final latestWeight = readings.isEmpty ? null : readings.last.weightKg;
    return Scaffold(
      appBar: AppBar(title: Text(hive.name)),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text(hive.location, style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: MetricCard(label: store.tr('hive.health.score'), value: '${insight.healthScore}/100', icon: Icons.favorite_outline, color: color)),
          const SizedBox(width: 10),
          Expanded(child: MetricCard(label: store.tr('hive.health.latest.weight'), value: latestWeight == null ? store.tr('hive.health.no.reading') : '${latestWeight.toStringAsFixed(1)} kg', icon: Icons.scale_outlined)),
        ]),
        const SizedBox(height: 18),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.insights_outlined), const SizedBox(width: 8), Text(store.tr('hive.health.risk.insight'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19))]),
          const SizedBox(height: 12),
          StatusBadge(label: insight.riskLevel == RiskLevel.healthy ? store.tr('hive.health.status.healthy') : store.tr('hive.health.status.attention'), color: color),
          Text(insight.riskExplanation),
          const SizedBox(height: 8),
          Text(insight.productivityInsight, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(insight.inspectionRecommendation, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ]))),
        const SizedBox(height: 18),
        Text(store.tr('hive.health.historical'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(child: Column(children: [for (final reading in readings) ListTile(
          leading: const Icon(Icons.sensors_outlined),
          title: Text('${reading.recordedAt.day} Aug 2026'),
          subtitle: Text('${reading.temperatureC.toStringAsFixed(1)} C  |  ${reading.humidityPercent.toStringAsFixed(0)}% humidity'),
          trailing: Text('${reading.weightKg.toStringAsFixed(1)} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
        )])),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordHarvestScreen(hive: hive))), icon: const Icon(Icons.add), label: Text(store.tr('hive.health.record.harvest'))),
      ]),
    );
  }
}

class RecordHarvestScreen extends StatefulWidget {
  const RecordHarvestScreen({super.key, required this.hive});
  final Hive hive;
  @override
  State<RecordHarvestScreen> createState() => _RecordHarvestScreenState();
}

class _RecordHarvestScreenState extends State<RecordHarvestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController(text: '8');
  @override
  void dispose() { _quantity.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
    appBar: AppBar(title: Text(store.tr('harvest.record.title'))),
    body: Padding(padding: const EdgeInsets.all(24), child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.hive.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(widget.hive.honeyType, style: const TextStyle(color: Colors.black54)),
      const SizedBox(height: 24),
      TextFormField(controller: _quantity, keyboardType: TextInputType.number, validator: (value) => (double.tryParse(value ?? '') ?? 0) > 0 ? null : store.tr('harvest.enter.qty'), decoration: InputDecoration(labelText: store.tr('record.harvest.quantity'), border: const OutlineInputBorder())),
      const SizedBox(height: 20),
      FilledButton(onPressed: () { if (!_formKey.currentState!.validate()) return; HoneyChainStore.instance.recordHarvest(hive: widget.hive, quantityKg: double.parse(_quantity.text)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(store.tr('harvest.recorded')))); Navigator.pop(context); }, child: Text(store.tr('record.harvest.save'))),
    ]))),
  );
  }
}
