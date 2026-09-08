import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../models/domain.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/section_label.dart';
import '../honey_passport_screen.dart';

class BuyerAllocationScreen extends StatefulWidget {
  const BuyerAllocationScreen({super.key, required this.batch});

  final Batch batch;

  @override
  State<BuyerAllocationScreen> createState() => _BuyerAllocationScreenState();
}

class _BuyerAllocationScreenState extends State<BuyerAllocationScreen> {
  late double _allocateKg;
  int _selectedJarSizeGrams = 500;
  bool _creating = false;
  List<HoneyJar>? _createdJars;

  static const List<int> _supportedSizes = [100, 250, 500, 1000];

  @override
  void initState() {
    super.initState();
    final store = HoneyChainStore.instance;
    final listing = store.marketplaceListings
        .where((l) => l.batchId == widget.batch.id)
        .firstOrNull;
    final available = listing?.effectiveRemainingKg ?? widget.batch.quantityKg;
    // Default to min(2.0, available) or available if smaller
    _allocateKg = available >= 2.0 ? 2.0 : available;
    if (_allocateKg < 0.1 && available > 0) _allocateKg = available;
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final listing = store.marketplaceListings
        .where((l) => l.batchId == widget.batch.id)
        .firstOrNull;
    final availableKg =
        listing?.effectiveRemainingKg ?? widget.batch.quantityKg;
    final availableGrams = (availableKg * 1000).round();

    final allocatedGrams = (_allocateKg * 1000).round();
    final jarCount = _selectedJarSizeGrams > 0
        ? allocatedGrams ~/ _selectedJarSizeGrams
        : 0;
    final actualPackagingGrams = jarCount * _selectedJarSizeGrams;
    final remainingGrams = (availableGrams - actualPackagingGrams).clamp(0, availableGrams);
    final remainingKg = remainingGrams / 1000.0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        foregroundColor: AppTheme.ink,
        elevation: 0,
        title: Text(
          store.tr('buyer.allocation.title'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          _BatchSummaryCard(batch: widget.batch, availableKg: availableKg),
          const SizedBox(height: 20),

          if (_createdJars != null) ...[
            _CreatedJarsView(
              jars: _createdJars!,
              batch: widget.batch,
              onDone: () => Navigator.of(context).pop(),
            ),
          ] else ...[
            SectionLabel(store.tr('buyer.allocation.select.qty')),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: AppTheme.radiusCard,
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
'${formatKg(_allocateKg)} kg ($allocatedGrams g)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                      Text(
                        'Max: ${formatKg(availableKg)} kg',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.inkFaint,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _allocateKg.clamp(0.1, availableKg),
                    min: 0.1,
                    max: availableKg > 0.1 ? availableKg : 0.1,
                    divisions: (availableKg * 10).round().clamp(1, 1000),
                    activeColor: AppTheme.orange,
                    inactiveColor: AppTheme.orangeSoft,
                    onChanged: (v) {
                      setState(() {
                        // Snap to 100g intervals
                        _allocateKg = (v * 10).round() / 10.0;
                      });
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final w in [0.5, 1.0, 2.0, 2.5, 5.0])
                        if (w <= availableKg)
                          ActionChip(
                            label: Text('${formatKg(w)} kg'),
                            backgroundColor: (_allocateKg - w).abs() < 0.05
                                ? AppTheme.orange
                                : AppTheme.cardWarm,
                            labelStyle: TextStyle(
                              color: (_allocateKg - w).abs() < 0.05
                                  ? Colors.white
                                  : AppTheme.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            onPressed: () => setState(() => _allocateKg = w),
                          ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            SectionLabel(store.tr('buyer.allocation.select.size')),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final size in _supportedSizes) ...[
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () =>
                            setState(() => _selectedJarSizeGrams = size),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _selectedJarSizeGrams == size
                                ? AppTheme.orangeSoft
                                : AppTheme.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selectedJarSizeGrams == size
                                  ? AppTheme.orange
                                  : AppTheme.border,
                              width: _selectedJarSizeGrams == size ? 1.8 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.cookie_outlined,
                                size: 24,
                                color: _selectedJarSizeGrams == size
                                    ? AppTheme.orangeDark
                                    : AppTheme.inkSoft,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                size >= 1000 ? '1 kg' : '${size}g',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: _selectedJarSizeGrams == size
                                      ? AppTheme.orangeDark
                                      : AppTheme.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 22),

            SectionLabel(store.tr('buyer.allocation.preview')),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.cardCream,
                borderRadius: AppTheme.radiusCard,
                border: Border.all(color: AppTheme.honey.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  _PreviewRow(
                    label: store.tr('buyer.allocation.source'),
                    value: widget.batch.code,
                  ),
                  const Divider(height: 16),
                  _PreviewRow(
                    label: store.tr('buyer.allocation.allocated'),
                    value: '${formatKg(_allocateKg)} kg ($allocatedGrams g)',
                  ),
                  const Divider(height: 16),
                  _PreviewRow(
                    label: store.tr('buyer.allocation.jar.size'),
                    value: _selectedJarSizeGrams >= 1000
                        ? '1 kg (1000 g)'
                        : '$_selectedJarSizeGrams g',
                  ),
                  const Divider(height: 16),
                  _PreviewRow(
                    label: store.tr('buyer.allocation.jar.count'),
                    value: '$jarCount jars',
                    highlight: true,
                  ),
                  const Divider(height: 16),
                  _PreviewRow(
                    label: store.tr('buyer.allocation.remaining'),
                    value: '${formatKg(remainingKg)} kg ($remainingGrams g)',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: (jarCount > 0 && !_creating)
                    ? () => _confirmAndCreate(context, jarCount)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.orange,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: _creating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(
                  store.tr('buyer.allocation.confirm.button'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmAndCreate(BuildContext context, int jarCount) async {
    final store = HoneyChainStore.instance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          store.tr('buyer.allocation.confirm.title'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          store
              .tr('buyer.allocation.confirm.message')
              .replaceFirst('{qty}', formatKg(_allocateKg))
              .replaceFirst('{count}', '$jarCount')
              .replaceFirst(
                '{size}',
                _selectedJarSizeGrams >= 1000
                    ? '1 kg'
                    : '${_selectedJarSizeGrams}g',
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(store.tr('custody.cancel.button')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.orange),
            child: Text(store.tr('buyer.allocation.confirm.button')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _creating = true);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final created = store.allocateAndCreateJars(
      batch: widget.batch,
      allocatedKg: _allocateKg,
      jarSizeGrams: _selectedJarSizeGrams,
      buyerId: store.buyerId,
    );

    if (!context.mounted) return;
    setState(() {
      _creating = false;
      _createdJars = created;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          store
              .tr('buyer.allocation.created.toast')
              .replaceFirst('{count}', '${created.length}')
              .replaceFirst('{code}', widget.batch.code),
        ),
        backgroundColor: AppTheme.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _BatchSummaryCard extends StatelessWidget {
  const _BatchSummaryCard({required this.batch, required this.availableKg});

  final Batch batch;
  final double availableKg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                batch.code,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.greenSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'MARKET RELEASED',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.greenDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${batch.honeyType} · ${batch.origin}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.inkSoft,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Total Batch Qty: ${formatKg(batch.quantityKg)} kg · Available: ${formatKg(availableKg)} kg',
            style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: highlight ? 16 : 14,
            fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
            color: highlight ? AppTheme.orangeDark : AppTheme.ink,
          ),
        ),
      ],
    );
  }
}

class _CreatedJarsView extends StatelessWidget {
  const _CreatedJarsView({
    required this.jars,
    required this.batch,
    required this.onDone,
  });

  final List<HoneyJar> jars;
  final Batch batch;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.greenSoft,
            borderRadius: AppTheme.radiusCard,
            border: Border.all(color: AppTheme.green.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppTheme.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Created ${jars.length} Individual Jars',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Retaining complete upstream genealogy to ${batch.code}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Generated Jar Records',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final jar in jars) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.cookie_outlined, color: AppTheme.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        jar.jarId,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.ink,
                        ),
                      ),
                      Text(
                        '${jar.packageSize} · Batch: ${jar.sourceBatchId}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HoneyPassportScreen(jar: jar),
                    ),
                  ),
                  child: const Text('Passport'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: onDone,
            child: const Text('Return to Portal'),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
