import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../services/productivity_service.dart';
import '../theme/app_theme.dart';

/// Productivity Prediction — the beekeeper-facing screen for the HoneyChain
/// honey-yield model.
///
/// The prediction is produced by the already-trained
/// `honey_productivity_model.joblib` (ExtraTreesRegressor) served by the
/// existing FastAPI model service (`productivity_api.py`,
/// `POST /predict-productivity`). This screen never computes, estimates or
/// rounds-in a yield itself: it sends the four recorded colony measurements
/// (`apiary`, `total_brood`, `varroa_2`, `hygiene_2`) and displays exactly what
/// the service returns.
///
/// Honesty rules enforced here:
/// * A missing measurement is never replaced by a default — the screen lists
///   precisely which model input is still required.
/// * An unreachable or failing service shows a retryable error, never a number.
/// * The telemetry outlook below is a separate on-device weight-trend summary
///   and is labelled as such.
class ProductivityScreen extends StatefulWidget {
  const ProductivityScreen({super.key, this.service});

  /// Injectable model-service client (tests pass a mocked client). Production
  /// builds leave this null and the screen talks to the real endpoint.
  final ProductivityService? service;

  @override
  State<ProductivityScreen> createState() => _ProductivityScreenState();
}

class _ProductivityScreenState extends State<ProductivityScreen> {
  String? _selectedHiveId;
  final TextEditingController _apiary = TextEditingController();
  final TextEditingController _brood = TextEditingController();
  final TextEditingController _varroa = TextEditingController();
  final TextEditingController _hygiene = TextEditingController();

  late final ProductivityService _service =
      widget.service ?? ProductivityService();

  bool _predicting = false;
  ProductivityResult? _result;
  List<String> _missing = const <String>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    final hives = HoneyChainStore.instance.hives;
    if (hives.isNotEmpty) {
      _selectedHiveId = hives.first.id;
      _restoreCached(hives.first.id);
    }
  }

  @override
  void dispose() {
    _apiary.dispose();
    _brood.dispose();
    _varroa.dispose();
    _hygiene.dispose();
    super.dispose();
  }

  /// Restores the measurements and the last prediction stored for [hiveId] so
  /// the screen reopens offline. A restored prediction is a value the model
  /// service previously returned; it is never recomputed locally.
  void _restoreCached(String hiveId) {
    final cached = ProductivityCache.load(hiveId);
    if (cached == null) {
      // Nothing has been recorded for this hive yet, so every model input is
      // still required. Reporting exactly which ones keeps the yield slot
      // honest instead of leaving it in an ambiguous state.
      _missing = _measurementsFromForm().missing;
      return;
    }
    final m = cached.measurements;
    _apiary.text = m.apiary ?? '';
    _brood.text = m.totalBrood?.toString() ?? '';
    _varroa.text = m.varroa2?.toString() ?? '';
    _hygiene.text = m.hygiene2?.toString() ?? '';
    _result = cached.result;
    _missing = m.missing;
  }

  /// The measurements currently typed into the form. Blank entries stay null so
  /// they are reported as still-required model inputs, never invented.
  ColonyMeasurements _measurementsFromForm() => ColonyMeasurements.fromText(
        apiary: _apiary.text,
        totalBrood: _brood.text,
        varroa2: _varroa.text,
        hygiene2: _hygiene.text,
      );

  /// Sends the recorded measurements to the existing productivity model service
  /// and shows exactly what it returns. When a measurement is missing nothing
  /// is sent — the screen reports which model input is still required.
  Future<void> _predict(Hive hive) async {
    final measurements = _measurementsFromForm();
    final inputs = measurements.toInputs();

    setState(() {
      _error = null;
      _missing = measurements.missing;
      _predicting = inputs != null;
      if (inputs == null) _result = null;
    });

    await ProductivityCache.save(
      CachedProductivity(
        hiveId: hive.id,
        measurements: measurements,
        cachedAt: DateTime.now(),
        result: inputs == null ? null : _result,
      ),
    );

    if (inputs == null) return;

    try {
      final result = await _service.predict(inputs);
      if (!mounted) return;
      setState(() {
        _result = result;
        _predicting = false;
      });
      await ProductivityCache.save(
        CachedProductivity(
          hiveId: hive.id,
          measurements: measurements,
          cachedAt: DateTime.now(),
          result: result,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _predicting = false;
        _error = e.friendly;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _predicting = false;
        _error = HoneyChainStore.instance.tr('prod.error');
      });
    }
  }

  void _selectHive(String? hiveId) {
    if (hiveId == null) return;
    setState(() {
      _selectedHiveId = hiveId;
      _result = null;
      _error = null;
      _missing = const <String>[];
      _apiary.clear();
      _brood.clear();
      _varroa.clear();
      _hygiene.clear();
      _restoreCached(hiveId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final hives = store.hives;
    final hive = hives.isEmpty
        ? null
        : hives.firstWhere(
            (h) => h.id == _selectedHiveId,
            orElse: () => hives.first,
          );

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(store.tr('prod.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardWarm,
                borderRadius: AppTheme.radiusCard,
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                store.tr('prod.subtitle'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.inkSoft,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              store.tr('prod.pick.hive'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 8),
            if (hives.isEmpty)
              _EmptyCard(text: store.tr('prod.no.data'))
            else ...[
              DropdownButtonFormField<String>(
                initialValue: hive?.id,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppTheme.card,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
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
                    borderSide: const BorderSide(
                      color: AppTheme.honeyGold,
                      width: 1.6,
                    ),
                  ),
                ),
                items: [
                  for (final h in hives)
                    DropdownMenuItem<String>(
                      value: h.id,
                      child: Text(
                        h.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.ink,
                        ),
                      ),
                    ),
                ],
                onChanged: _selectHive,
              ),
              const SizedBox(height: 16),
              if (hive == null)
                _EmptyCard(text: store.tr('prod.no.data'))
              else ...[
                _YieldCard(
                  store: store,
                  predicting: _predicting,
                  result: _result,
                  missing: _missing,
                  error: _error,
                ),
                const SizedBox(height: 16),
                _MeasurementsCard(
                  store: store,
                  apiary: _apiary,
                  brood: _brood,
                  varroa: _varroa,
                  hygiene: _hygiene,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _predicting ? null : () => _predict(hive),
                    icon: _predicting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                    label: Text(
                      store.tr('prod.refresh'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _PredictionCard(store: store, hive: hive),
                const SizedBox(height: 8),
                Text(
                  store.tr('prod.data.note'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.inkFaint,
                    height: 1.4,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Displays the yield returned by the trained HoneyChain productivity model.
///
/// Nothing on this card is estimated on-device. It renders exactly one of four
/// truthful states:
/// * loading — a request is in flight to the model service;
/// * error — the service failed, with a retry hint (never a number);
/// * insufficient — one or more model inputs are missing, listing exactly which;
/// * result — the kg figure the service returned, with the reported model name.
class _YieldCard extends StatelessWidget {
  const _YieldCard({
    required this.store,
    required this.predicting,
    required this.result,
    required this.missing,
    required this.error,
  });

  final HoneyChainStore store;
  final bool predicting;
  final ProductivityResult? result;
  final List<String> missing;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color accent;
    if (error != null) {
      accent = AppTheme.red;
      icon = Icons.cloud_off_rounded;
    } else if (predicting) {
      accent = AppTheme.honeyGold;
      icon = Icons.downloading_rounded;
    } else if (result != null) {
      accent = AppTheme.honeyDark;
      icon = Icons.hexagon_outlined;
    } else if (missing.isNotEmpty) {
      accent = AppTheme.orange;
      icon = Icons.rule_rounded;
    } else {
      accent = AppTheme.inkFaint;
      icon = Icons.hourglass_empty_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: accent, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.tr('prod.yield.title'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.inkFaint,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _headline(),
                      style: TextStyle(
                        fontSize: result == null ? 17 : 26,
                        fontWeight: FontWeight.w900,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (error != null) _Note(text: error!),
          if (error == null && missing.isNotEmpty)
            _Note(text: store.tr('prod.missing.prefix')),
          if (error == null && missing.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final field in missing)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _Chip(
                  icon: Icons.check_box_outline_blank_rounded,
                  label: store.tr('prod.field.$field'),
                ),
              ),
          ],
          if (result != null) ...[
            _Note(text: store.tr('prod.yield.source')),
            if (result!.model.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Row2(label: store.tr('prod.yield.model'), value: result!.model),
            ],
          ],
        ],
      ),
    );
  }

  /// The single line of truth for this card: a real kg value, a spinner state,
  /// or an explicit "not available" message. No placeholder number is shown.
  String _headline() {
    if (predicting) return store.tr('prod.yield.loading');
    if (result != null) {
      return '${result!.predictedHoneyYieldKg.toStringAsFixed(2)} '
          '${store.tr('prod.yield.unit')}';
    }
    if (error != null) return store.tr('prod.yield.unavailable');
    if (missing.isNotEmpty) return store.tr('prod.yield.insufficient');
    return store.tr('prod.yield.waiting');
  }
}

/// Small muted paragraph used across the productivity cards.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: AppTheme.inkSoft,
          height: 1.4,
        ),
      );
}

/// The four inputs the trained model expects, recorded by the beekeeper.
///
/// These are the exact model contract fields (`apiary`, `total_brood`,
/// `varroa_2`, `hygiene_2`). The HoneyChain data model stores none of them, so
/// the beekeeper enters them here and they are cached locally per hive.
class _MeasurementsCard extends StatelessWidget {
  const _MeasurementsCard({
    required this.store,
    required this.apiary,
    required this.brood,
    required this.varroa,
    required this.hygiene,
  });

  final HoneyChainStore store;
  final TextEditingController apiary;
  final TextEditingController brood;
  final TextEditingController varroa;
  final TextEditingController hygiene;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.tr('prod.inputs.title'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(height: 6),
          _Note(text: store.tr('prod.inputs.note')),
          const SizedBox(height: 14),
          _Field(
            controller: apiary,
            label: store.tr('prod.field.apiary'),
            icon: Icons.place_outlined,
          ),
          _Field(
            controller: brood,
            label: store.tr('prod.field.total_brood'),
            icon: Icons.grid_on_rounded,
            numeric: true,
          ),
          _Field(
            controller: varroa,
            label: store.tr('prod.field.varroa_2'),
            icon: Icons.bug_report_outlined,
            numeric: true,
          ),
          _Field(
            controller: hygiene,
            label: store.tr('prod.field.hygiene_2'),
            icon: Icons.cleaning_services_outlined,
            numeric: true,
          ),
        ],
      ),
    );
  }
}

/// A single labelled input in the measurements form.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.numeric = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppTheme.ink,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          prefixIcon: Icon(icon, size: 20, color: AppTheme.honeyDark),
          filled: true,
          fillColor: AppTheme.cardWarm,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
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
            borderSide: const BorderSide(color: AppTheme.honeyGold, width: 1.6),
          ),
        ),
      ),
    );
  }
}


class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.store, required this.hive});

  /// On-device weight-trend summary from recorded telemetry readings.
  ///
  /// This is deliberately separate from [_YieldCard]: it is arithmetic over
  /// this device's own readings (an outlook, not a model output), so it is
  /// labelled as telemetry and never presented as a predicted yield.
  final HoneyChainStore store;
  final Hive hive;

  @override
  Widget build(BuildContext context) {
    final insight = store.insightFor(hive);
    final readings = store.readingsForHive(hive.id);
    final weightChange = _weightChangePercent(readings);

    final (color, icon) = switch (insight.weightStatus) {
      WeightStatus.growing => (AppTheme.green, Icons.trending_up_rounded),
      WeightStatus.steady => (AppTheme.inkSoft, Icons.trending_flat_rounded),
      WeightStatus.dropping => (AppTheme.orange, Icons.trending_down_rounded),
    };
    final outlook = switch (insight.weightStatus) {
      WeightStatus.growing => store.tr('prod.outlook.growing'),
      WeightStatus.steady => store.tr('prod.outlook.steady'),
      WeightStatus.dropping => store.tr('prod.outlook.dropping'),
    };

    final latest = readings.isEmpty ? null : readings.last;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.tr('prod.telemetry'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.inkFaint,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      outlook,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Row2(
            label: store.tr('prod.weight.change'),
            value: weightChange == null ? '—' : _signed(weightChange),
          ),
          if (latest != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _Chip(
                  icon: Icons.thermostat_rounded,
                  label: '${latest.temperatureC.toStringAsFixed(1)}°C',
                ),
                const SizedBox(width: 8),
                _Chip(
                  icon: Icons.water_drop_rounded,
                  label: '${latest.humidityPercent.toStringAsFixed(0)}%',
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: _Chip(
                    icon: Icons.monitor_weight_rounded,
                    label: '${latest.weightKg.toStringAsFixed(1)} kg',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _Row2(
            label: store.tr('prod.health'),
            value: '${insight.healthScore}/100',
          ),
          const SizedBox(height: 8),
          _Row2(
            label: store.tr('prod.recommendation'),
            value: insight.inspectionRecommendation,
          ),
        ],
      ),
    );
  }

  static double? _weightChangePercent(List<HiveReading> readings) {
    if (readings.length < 2) return null;
    final first = readings.first.weightKg;
    final last = readings.last.weightKg;
    if (first == 0) return null;
    return (last - first) / first * 100;
  }

  static String _signed(double v) =>
      '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}%';
}

class _Row2 extends StatelessWidget {
  const _Row2({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.inkSoft,
              height: 1.35,
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.cardWarm,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.honeyDark),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.cardWarm,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: AppTheme.inkFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.inkSoft,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


