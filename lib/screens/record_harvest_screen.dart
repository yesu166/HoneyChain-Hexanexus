import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/section_label.dart';

class RecordHarvestScreen extends StatefulWidget {
  const RecordHarvestScreen({super.key, this.initialHive});

  final Hive? initialHive;

  @override
  State<RecordHarvestScreen> createState() => _RecordHarvestScreenState();
}

class _RecordHarvestScreenState extends State<RecordHarvestScreen> {
  late Hive? _hive;
  late DateTime _date = DateTime.now();
  double _qty = 1.0;
  bool _photoTaken = false;
  bool _saving = false;
  late final TextEditingController _source;
  late final TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    final store = HoneyChainStore.instance;
    _hive = widget.initialHive ??
        (store.hives.isNotEmpty ? store.hives.first : null);
    _source = TextEditingController();
    _qtyController = TextEditingController(text: '1.0');
  }

  @override
  void dispose() {
    _source.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  /// Minimum sensible harvest: 100 g (0.1 kg). Save stays disabled below this.
  static const double minQuantityKg = 0.1;

  static const List<double> quickWeights = [0.1, 0.5, 1.0, 2.0, 3.0];

  void _incrementQty() {
    double next;
    if (_qty < 0.95) {
      next = (_qty + 0.1).clamp(0.1, 100.0);
    } else {
      next = (_qty + 0.5).clamp(0.1, 100.0);
    }
    next = (next * 10).round() / 10;
    setState(() {
      _qty = next;
      _qtyController.text = next.toStringAsFixed(1);
    });
  }

  void _decrementQty() {
    double next;
    if (_qty <= 0.15) {
      next = 0.1;
    } else if (_qty <= 1.05) {
      next = (_qty - 0.1).clamp(0.1, 100.0);
    } else {
      next = (_qty - 0.5).clamp(0.1, 100.0);
    }
    next = (next * 10).round() / 10;
    setState(() {
      _qty = next;
      _qtyController.text = next.toStringAsFixed(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final hives = store.hives;
    if (_hive == null && hives.isNotEmpty) {
      _hive = hives.first;
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('record.harvest.title'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          SectionLabel(store.tr('record.harvest.which')),
          DropdownButtonFormField<String>(
            initialValue: _hive?.id,
            isExpanded: true,
            items: [
              for (final h in hives)
                DropdownMenuItem(
                  value: h.id,
                  child: Text(
                    h.detail.isEmpty
                        ? h.name
                        : '${h.name} · ${h.detail}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.ink),
                  ),
                ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                for (final h in hives) {
                  if (h.id == v) {
                    _hive = h;
                    break;
                  }
                }
              });
            },
            decoration: _fieldDecoration(),
          ),
          const SizedBox(height: 22),
          SectionLabel(store.tr('record.harvest.date')),
          InkWell(
            onTap: _pickDate,
            borderRadius: AppTheme.radiusField,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: AppTheme.radiusField,
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: AppTheme.inkSoft,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      formatDate(_date),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          SectionLabel(store.tr('record.harvest.quantity')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in quickWeights)
                _QuickWeightChip(
                  label: _weightLabel(store, w),
                  selected: (_qty - w).abs() < 0.01,
                  onTap: () => setState(() {
                    _qty = w;
                    _qtyController.text = w.toStringAsFixed(1);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: AppTheme.radiusField,
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  onTap: _decrementQty,
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IntrinsicWidth(
                        child: TextField(
                          controller: _qtyController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 4),
                          ),
                          onChanged: (val) {
                            final parsed = double.tryParse(val.trim());
                            if (parsed != null) {
                              setState(() => _qty = parsed);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        store.tr('common.kg'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  onTap: _incrementQty,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            store.tr('record.harvest.min.hint'),
            style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
          ),
          const SizedBox(height: 22),
          SectionLabel(store.tr('record.harvest.source')),
          TextField(
            controller: _source,
            keyboardType: TextInputType.text,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: store.tr('record.harvest.source.hint'),
              hintText: store.tr('record.harvest.source.placeholder'),
              prefixIcon: const Icon(
                Icons.local_florist_outlined,
                color: AppTheme.honeyDark,
              ),
              filled: true,
              fillColor: AppTheme.cardWarm,
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
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final opt in ['Not specified', 'Mixed / Multiple', 'Unknown'])
                ActionChip(
                  label: Text(
                    opt == 'Not specified'
                        ? store.tr('harvest.source.not_specified')
                        : (opt == 'Mixed / Multiple'
                            ? store.tr('harvest.source.mixed')
                            : store.tr('harvest.source.unknown')),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _source.text == opt ? AppTheme.orangeDark : AppTheme.ink,
                    ),
                  ),
                  backgroundColor:
                      _source.text == opt ? AppTheme.orangeSoft : AppTheme.card,
                  side: BorderSide(
                    color: _source.text == opt ? AppTheme.orange : AppTheme.border,
                  ),
                  onPressed: () {
                    setState(() {
                      _source.text = opt;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 22),
          SectionLabel(store.tr('record.harvest.photo')),
          InkWell(
            onTap: () => setState(() => _photoTaken = !_photoTaken),
            borderRadius: AppTheme.radiusField,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: AppTheme.radiusField,
                border: Border.all(
                  color: _photoTaken ? AppTheme.green : AppTheme.border,
                  width: _photoTaken ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _photoTaken
                        ? Icons.check_circle_rounded
                        : Icons.camera_alt_outlined,
                    color: _photoTaken ? AppTheme.green : AppTheme.inkSoft,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      store.tr('record.harvest.photo'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color:
                            _photoTaken ? AppTheme.ink : AppTheme.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed:
                  _hive != null && _qty >= minQuantityKg && !_saving
                      ? _save
                      : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green,
                disabledBackgroundColor: AppTheme.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 20),
              label: Text(
                store.tr('record.harvest.save'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.fromSeed(seedColor: AppTheme.orange),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final store = HoneyChainStore.instance;
    final hive = _hive;
    if (hive == null) return;
    if (_qty < minQuantityKg) return;
    setState(() => _saving = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final harvest = store.recordHarvest(
      hive: hive,
      quantityKg: _qty,
      date: _date,
      floralSource: _source.text.trim(),
    );
    var anchored = false;
    if (store.backendModeActive) {
      final server = await store.pushHarvestToBackend(harvest);
      final bundle = await store.anchorHarvestEvidence(
        harvest: harvest,
        serverHarvestId: server?.id,
      );
      anchored = bundle?.isAnchored ?? false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          store.backendModeActive
              ? (anchored
                  ? 'Saved & anchored on the blockchain (Fabric)'
                  : 'Saved — blockchain anchor pending')
              : store.tr('record.harvest.saved'),
        ),
        backgroundColor: anchored ? AppTheme.green : AppTheme.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pop();
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

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          color: AppTheme.orangeSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppTheme.orangeDark, size: 24),
      ),
    );
  }
}

/// One-shot preset weight button (100 g / 500 g / 1 kg / 2 kg / 3 kg).
class _QuickWeightChip extends StatelessWidget {
  const _QuickWeightChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.orange : AppTheme.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.orange : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppTheme.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// Rounds a quantity to 1 decimal place and clamps it to [minQuantityKg, 100].
double round1(double v) {
  final clamped = v.clamp(_RecordHarvestScreenState.minQuantityKg, 100.0);
  return (clamped * 10).round() / 10;
}

String _weightLabel(HoneyChainStore store, double kg) {
  final grams = (kg * 1000).round();
  if (grams % 1000 == 0) {
    return '${grams ~/ 1000} ${store.tr('common.kg')}';
  }
  return '$grams ${store.tr('common.g')}';
}