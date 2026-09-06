import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_header.dart';
import '../widgets/info_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/status_pill.dart';

class RegulatorScreen extends StatefulWidget {
  const RegulatorScreen({super.key});
  @override
  State<RegulatorScreen> createState() => _RegulatorScreenState();
}

class _RegulatorScreenState extends State<RegulatorScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final batches = store.batches;
        final selected = _selectedId == null ? (batches.isNotEmpty ? batches.first : null) : batches.where((b) => b.id == _selectedId).firstOrNull;
        return Scaffold(
          appBar: AppBar(title: Text(store.tr('regulator.title'))),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              BrandHeader(subtitle: store.tr('regulator.oversight')),
              const SizedBox(height: 8),
              Text(store.tr('regulator.subtitle'), style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 20),
              if (batches.isEmpty)
                Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(store.tr('regulator.no.batches'), style: const TextStyle(color: Colors.black54))))
              else ...[
                SectionHeader(title: store.tr('regulator.select.batch'), seeAllLabel: ''),
                const SizedBox(height: 8),
                SizedBox(
                  height: 54,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final batch in batches)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(batch.code),
                            selected: selected?.id == batch.id,
                            onSelected: (_) => setState(() => _selectedId = batch.id),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (selected != null) _AuditPanel(batch: selected),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AuditPanel extends StatelessWidget {
  const _AuditPanel({required this.batch});
  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final custody = store.custodyFor(batch);
    final verification = store.verificationsFor(batch).firstOrNull;
    final anchors = store.anchorsFor(batch);
    final events = store.eventsFor(batch);
    final compliant = verification != null && verification.status == VerificationStatus.pass;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(batch.code, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    StatusPill(label: compliant ? StatusPill.verified : StatusPill.pending),
                  ],
                ),
                const SizedBox(height: 12),
                InfoTile.row(store.tr('regulator.producer'), store.tr('regulator.fpo')),
                InfoTile.row(store.tr('regulator.origin'), batch.origin),
                InfoTile.row(store.tr('regulator.honey.type'), batch.honeyType),
                InfoTile.row(store.tr('regulator.quantity'), '${batch.quantityKg.toStringAsFixed(1)} kg'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader(title: store.tr('regulator.compliance'), seeAllLabel: ''),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _StatusRow(icon: Icons.inventory_2_outlined, label: store.tr('regulator.custody.title'), detail: custody.isNotEmpty ? store.tr('regulator.custody.recorded').replaceFirst('{count}', '${custody.length}') : store.tr('status.pending'), done: custody.isNotEmpty),
                const Divider(height: 20),
                _StatusRow(icon: Icons.science_outlined, label: store.tr('regulator.lab.title'), detail: verification != null ? (verification.status == VerificationStatus.pass ? store.tr('regulator.lab.pass') : store.tr('status.fail')) : store.tr('status.pending'), done: verification != null && verification.status == VerificationStatus.pass),
                const Divider(height: 20),
                _StatusRow(icon: Icons.link, label: store.tr('regulator.blockchain.title'), detail: anchors.isNotEmpty ? store.tr('regulator.anchored').replaceFirst('{count}', '${anchors.length}') : store.tr('status.pending'), done: anchors.isNotEmpty),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        SectionHeader(title: store.tr('regulator.audit.trail').replaceFirst('{count}', '${events.length}'), seeAllLabel: ''),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: events.isEmpty
                ? Text(store.tr('regulator.no.events'), style: const TextStyle(color: Colors.black54))
                : Column(
                    children: [
                      for (var i = 0; i < events.length; i++) ...[
                        _AuditStep(number: i + 1, event: events[i], isLast: i == events.length - 1),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.icon, required this.label, required this.detail, required this.done});
  final IconData icon;
  final String label;
  final String detail;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppTheme.green : AppTheme.orange;
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(detail, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: color, size: 20),
      ],
    );
  }
}

class _AuditStep extends StatelessWidget {
  const _AuditStep({required this.number, required this.event, required this.isLast});
  final int number;
  final AuditEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.honey.withValues(alpha: 0.25),
              child: Text('$number', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.honeyDark)),
            ),
            if (!isLast) Container(height: 30, width: 2, color: AppTheme.honey.withValues(alpha: 0.3)),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.description, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('${event.actor} · ${event.recordedAt.day} Aug ${event.recordedAt.year}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
