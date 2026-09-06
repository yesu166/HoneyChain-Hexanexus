import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../models/domain.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import 'org_batch_detail_screen.dart';

/// Consolidates multiple collected harvests (from different hives) into ONE
/// genealogy batch. The org picks a honey type and selects member harvests.
class OrgCreateBatchScreen extends StatefulWidget {
  const OrgCreateBatchScreen({super.key, required this.harvests});

  final List<Harvest> harvests;

  @override
  State<OrgCreateBatchScreen> createState() => _OrgCreateBatchScreenState();
}

class _OrgCreateBatchScreenState extends State<OrgCreateBatchScreen> {
  final Set<String> _selected = {};
  String _honeyType = 'Floral Honey';

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final totalKg = widget.harvests.fold<double>(
      0,
      (sum, h) => _selected.contains(h.id) ? sum + h.quantityKg : sum,
    );
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('org.batch.multi.hive.title'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          _InfoCard(
            icon: Icons.hub_outlined,
            title: store.tr('org.batch.consolidate.info.title'),
            body: store.tr('org.batch.consolidate.info.body'),
          ),
          const SizedBox(height: 18),
          Text(
            store.tr('org.batch.honey.type.label').toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: AppTheme.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _honeyType,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'Floral Honey', child: Text('Floral Honey')),
              DropdownMenuItem(value: 'Multiflora Honey', child: Text('Multiflora Honey')),
              DropdownMenuItem(value: 'Wild Forest Honey', child: Text('Wild Forest Honey')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _honeyType = v);
            },
            decoration: _fieldDecoration(),
          ),
          const SizedBox(height: 20),
          Text(
            store.tr('org.batch.select.harvests.label').replaceFirst('{count}', '${_selected.length}'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: AppTheme.inkFaint,
            ),
          ),
          const SizedBox(height: 8),
          if (widget.harvests.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                store.tr('org.batch.no.harvests'),
                style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
              ),
            )
          else ...[
            Container(
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: AppTheme.radiusCard,
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < widget.harvests.length; i++) ...[
                    _selectableTile(store, widget.harvests[i]),
                    if (i != widget.harvests.length - 1)
                      const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: AppTheme.border,
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _selected.isEmpty
                  ? store.tr('org.batch.select.at.least')
                  : store
                      .tr('org.batch.total.label')
                      .replaceFirst('{kg}', formatKg(totalKg)),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _selected.isEmpty ? AppTheme.orangeDark : AppTheme.green,
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _selected.isEmpty ? null : () => _createBatch(),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.orange,
                disabledBackgroundColor: AppTheme.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.hexagon_outlined, size: 20),
              label: Text(
                store.tr('org.batch.create.btn'),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _selectableTile(HoneyChainStore store, Harvest h) {
    final selected = _selected.contains(h.id);
    final hive = store.hiveName(h.hiveId);
    return InkWell(
      onTap: () {
        setState(() {
          if (selected) {
            _selected.remove(h.id);
          } else {
            _selected.add(h.id);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_off,
              color: selected ? AppTheme.orange : AppTheme.inkFaint,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hive,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatKg(h.quantityKg)} kg · ${formatDate(h.harvestedAt)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createBatch() {
    final store = HoneyChainStore.instance;
    final chosen = widget.harvests
        .where((h) => _selected.contains(h.id))
        .toList();
    if (chosen.isEmpty) return;
    final batch = store.createConsolidatedBatch(chosen, honeyTypeOverride: _honeyType);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(store
            .tr('org.batch.created.toast')
            .replaceFirst('{code}', batch.code)),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => OrgBatchDetailScreen(batch: batch)),
    );
  }

  InputDecoration _fieldDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppTheme.card,
      hintStyle: const TextStyle(color: AppTheme.inkFaint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: AppTheme.radiusField,
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppTheme.radiusField,
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppTheme.radiusField,
        borderSide: const BorderSide(color: AppTheme.orange, width: 1.6),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardWarm,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.orangeDark, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}