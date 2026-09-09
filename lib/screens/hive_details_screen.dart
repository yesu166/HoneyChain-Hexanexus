import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/disease.dart';
import '../models/domain.dart';
import '../models/iot.dart';
import '../theme/app_theme.dart';
import '../theme/beekeeper_tokens.dart';
import '../utils/format.dart';
import '../widgets/beekeeper_widgets.dart';
import '../widgets/listen_button.dart';
import '../widgets/section_label.dart';
import 'disease_screening_screen.dart';
import 'iot_simulator_screen.dart';
import 'record_harvest_screen.dart';

class HiveDetailsScreen extends StatefulWidget {
  const HiveDetailsScreen({super.key, required this.hive});

  final Hive hive;

  @override
  State<HiveDetailsScreen> createState() => _HiveDetailsScreenState();
}

class _HiveDetailsScreenState extends State<HiveDetailsScreen> {
  /// Session-scoped acknowledgement that the beekeeper checked this hive.
  /// Recorded on this phone only — it does not claim a screening result.
  bool _markedChecked = false;

  /// Target for the big "Get Advice" action — scrolls back to the guidance
  /// card when the beekeeper is down at the bottom action buttons.
  final GlobalKey _adviceKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = HoneyChainStore.instance;
      if (store.backendConfigured && !store.backendChecked) {
        store.refreshBackendIoT();
      }
    });
  }

  void _scrollToAdvice() {
    final ctx = _adviceKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _startDiseaseCheck(BuildContext context) async {
    final store = HoneyChainStore.instance;
    final source = await showDiseasePhotoSourceSheet(context);
    if (source == null) return;
    try {
      final picked = source
          ? await store.imageInput.pickFromCamera()
          : await store.imageInput.pickFromGallery();
      if (!context.mounted || picked == null) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DiseaseScreeningScreen(hive: widget.hive, image: picked),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.tr('screening.pick.failed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final hive = widget.hive;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        centerTitle: true,
        title: Text(
          hive.detail.isEmpty ? hive.name : '${hive.name} · ${hive.detail}',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final readings = store.readingsForHive(hive.id);
          final insight = store.insightFor(hive);
          final latest = readings.isNotEmpty ? readings.last : null;
          final checks = store.healthChecksFor(hive.id);
          final needsAttention = insight.riskLevel != RiskLevel.healthy;
          final showMarkChecked = needsAttention && !_markedChecked;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              _StatusHeader(
                store: store,
                hive: hive,
                insight: insight,
              ),
              if (latest != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    store
                        .tr('hive.detail.last.updated')
                        .replaceFirst('{time}', relativeTime(latest.recordedAt, store)),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.inkFaint,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _PhotoHero(hive: hive),
              if (showMarkChecked) ...[
                const SizedBox(height: 12),
                BeekeeperSecondaryButton(
                  icon: Icons.check_circle_outline_rounded,
                  label: store.tr('hive.detail.mark.checked'),
                  onPressed: () {
                    setState(() => _markedChecked = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(store.tr('hive.detail.check.recorded')),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 22),
              SectionLabel(store.tr('readings.title')),
              const SizedBox(height: 6),
              Text(
                store.tr('readings.prototype.note'),
                style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint, height: 1.35),
              ),
              const SizedBox(height: 12),
              BeekeeperMetricRow(
                icon: Icons.thermostat_rounded,
                label: store.tr('reading.temperature'),
                value: latest == null
                    ? '—'
                    : '${latest.temperatureC.round()}°C',
                status: _tempStatusLabel(store, insight.tempStatus),
                statusColor: insight.tempStatus == ReadingStatus.healthy
                    ? AppTheme.green
                    : AppTheme.orange,
              ),
              const SizedBox(height: 10),
              BeekeeperMetricRow(
                icon: Icons.water_drop_outlined,
                label: store.tr('reading.humidity'),
                value: latest == null
                    ? '—'
                    : '${latest.humidityPercent.round()}%',
                status: _tempStatusLabel(store, insight.humidityStatus),
                statusColor: insight.humidityStatus == ReadingStatus.healthy
                    ? AppTheme.green
                    : AppTheme.orange,
              ),
              const SizedBox(height: 10),
              BeekeeperMetricRow(
                icon: Icons.scale_outlined,
                label: store.tr('reading.weight'),
                value: latest == null ? '—' : '${latest.weightKg.round()} kg',
                status: _weightStatusLabel(store, insight.weightStatus),
                statusColor: switch (insight.weightStatus) {
                  WeightStatus.growing => AppTheme.green,
                  WeightStatus.dropping => AppTheme.red,
                  WeightStatus.steady => AppTheme.ink,
                },
                delta: _weightDelta(store, readings),
              ),
              const SizedBox(height: 14),
              _BackendIoTTelemetry(store: store, hive: hive),
              const SizedBox(height: 14),
              _DiseaseCheckCard(
                onTap: () => _startDiseaseCheck(context),
              ),
              const SizedBox(height: 22),
              Column(
                key: _adviceKey,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionLabel(store.tr('advice.title')),
                  _AdviceCard(insight: insight),
                  const SizedBox(height: 8),
                  Text(
                    store.tr('hive.detail.guidance.note'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.inkFaint,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
              if (checks.isNotEmpty) ...[
                const SizedBox(height: 22),
                SectionLabel(store.tr('health.history')),
                for (final check in checks) _HealthCheckRow(check: check),
              ],
              const SizedBox(height: 22),
              SizedBox(
                height: BeeTokens.touchPrimary,
                child: FilledButton.icon(
                  onPressed: _scrollToAdvice,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.orangeDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: const Icon(Icons.tips_and_updates_outlined, size: 22),
                  label: Text(
                    store.tr('hive.detail.get.advice'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => RecordHarvestScreen(initialHive: hive),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 22),
                  label: Text(
                    store.tr('record.harvest.from').replaceFirst('{hive}', hive.name),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// Overall status+detected summary shown first on a hive detail page.
/// Healthy vs attention uses the same qualitative wording as everywhere else.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.store,
    required this.hive,
    required this.insight,
  });

  final HoneyChainStore store;
  final Hive hive;
  final HiveInsight insight;

  @override
  Widget build(BuildContext context) {
    final healthy = insight.riskLevel == RiskLevel.healthy;
    final accent = healthy ? AppTheme.green : AppTheme.red;
    final String statusLabel = healthy
        ? store.tr('hive.status.healthy')
        : (insight.riskLevel == RiskLevel.highRisk
            ? store.tr('hive.status.action')
            : store.tr('hive.status.attention'));
    final String detected;
    if (healthy) {
      detected = store.tr('hive.detail.detected.fine');
    } else {
      final alert = _newestConditionAlert(store, hive.id);
      if (alert?.type == AlertType.disease) {
        detected = store.tr('alert.disease.note');
      } else if (alert?.type == AlertType.iot) {
        detected = store.tr('alert.iot.note');
      } else if (alert?.type == AlertType.temperature) {
        detected = store.tr('alert.needs.cooling.note');
      } else {
        detected = insight.riskExplanation;
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: healthy ? AppTheme.greenSoft : AppTheme.redSoft,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.4),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                healthy ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                color: accent,
                size: 26,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  store.tr('hive.detail.status.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkSoft),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            store.tr('hive.detail.detected'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.ink),
          ),
          const SizedBox(height: 4),
          Text(
            detected,
            style: const TextStyle(fontSize: 14, color: AppTheme.ink, height: 1.45),
          ),
        ],
      ),
    );
  }
}

HiveAlert? _newestConditionAlert(HoneyChainStore store, String hiveId) {
  HiveAlert? current;
  const hiveTypes = {
    AlertType.temperature,
    AlertType.humidity,
    AlertType.disease,
    AlertType.iot,
  };
  for (final alert in store.alerts) {
    if (alert.hiveId != hiveId) continue;
    if (!hiveTypes.contains(alert.type)) continue;
    if (current == null || alert.createdAt.isAfter(current.createdAt)) {
      current = alert;
    }
  }
  return current;
}

class _PhotoHero extends StatelessWidget {
  const _PhotoHero({required this.hive});

  final Hive hive;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: AppTheme.honey.withValues(alpha: 0.22),
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              Icons.hive_rounded,
              size: 64,
              color: AppTheme.honey.withValues(alpha: 0.65),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 13,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hive.location,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Optional weight change since the previous reading, localized by the store.
/// Hidden when there is no previous reading or the change is negligible.
String? _weightDelta(HoneyChainStore store, List<HiveReading> readings) {
  if (readings.length < 2) return null;
  final change =
      readings.last.weightKg - readings[readings.length - 2].weightKg;
  if (change.abs() < 0.05) return null;
  final sign = change > 0 ? '+' : '−';
  final delta = '$sign${change.abs().toStringAsFixed(1)} kg';
  return store.tr('hive.detail.weight.delta').replaceFirst('{delta}', delta);
}

String _tempStatusLabel(HoneyChainStore store, ReadingStatus status) =>
    switch (status) {
      ReadingStatus.high => store.tr('read.status.high'),
      ReadingStatus.low => store.tr('read.status.low'),
      ReadingStatus.healthy => store.tr('read.status.healthy'),
    };

String _weightStatusLabel(HoneyChainStore store, WeightStatus status) =>
    switch (status) {
      WeightStatus.growing => store.tr('read.status.growing'),
      WeightStatus.dropping => store.tr('read.status.dropping'),
      WeightStatus.steady => store.tr('read.status.steady'),
    };

/// Guidance card driven by the hive insight engine (never a diagnosis).
class _AdviceCard extends StatelessWidget {
  const _AdviceCard({required this.insight});

  final HiveInsight insight;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final (code, accent) = switch (insight.adviceCode) {
      'cool' => ('advice.cool', AppTheme.orange),
      'ventilation' => ('advice.ventilation', AppTheme.orange),
      _ => ('advice.inspect', AppTheme.green),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(
          color: accent.withValues(alpha: 0.45),
          width: 1.4,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              insight.adviceCode == 'cool'
                  ? Icons.ac_unit_rounded
                  : insight.adviceCode == 'ventilation'
                      ? Icons.air_rounded
                      : Icons.visibility_outlined,
              color: accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.tr(code),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  store.tr('$code.note'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                ListenButton(
                  compact: true,
                  text: '${store.tr(code)}. ${store.tr('$code.note')}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact "Check for Disease" action in the hive health/monitoring area.
/// Tapping it opens the camera/gallery selection sheet.
class _DiseaseCheckCard extends StatelessWidget {
  const _DiseaseCheckCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: AppTheme.orange.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.orangeSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  color: AppTheme.orangeDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.tr('hive.check.disease'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      store.tr('hive.check.disease.note'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ],
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
    );
  }
}

/// Backend-driven telemetry card for a hive which has a registered device.
///
/// Only shown when a device is actually assigned to this hive AND the backend
/// is online; local [HiveReading]s continue to drive the rest of the page.
/// Never fabricated — every value comes from the API response.
class _BackendIoTTelemetry extends StatelessWidget {
  const _BackendIoTTelemetry({required this.store, required this.hive});

  final HoneyChainStore store;
  final Hive hive;

  @override
  Widget build(BuildContext context) {
    if (!store.backendOnline || !store.backendConfigured) {
      return const SizedBox.shrink();
    }
    final device = _deviceFor(store, hive.id);
    if (device == null) return const SizedBox.shrink();

    final events = store.apiTelemetryFor(device.deviceId);
    final latest = events.isNotEmpty ? events.last : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('IoT telemetry (live)'),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: AppTheme.radiusCard,
            border: Border.all(color: AppTheme.teal.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.memory_rounded, size: 18, color: AppTheme.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      device.deviceName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'SIMULATED DEVICE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.teal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const IotSimulatorScreen(),
                      ),
                    ),
                    icon: const Icon(
                      Icons.tune_rounded,
                      size: 18,
                      color: AppTheme.inkFaint,
                    ),
                    tooltip: 'Open IoT simulator',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _metric('Temp', latest?.payload.temperatureC == null
                      ? '—'
                      : '${latest!.payload.temperatureC!.round()}°C'),
                  _metric('Humidity', latest?.payload.humidityPercent == null
                      ? '—'
                      : '${latest!.payload.humidityPercent!.round()}%'),
                  _metric('Weight', latest?.payload.hiveWeightKg == null
                      ? '—'
                      : '${latest!.payload.hiveWeightKg!.round()}kg'),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                latest == null
                    ? 'Device online — no events yet (run the simulator).'
                    : 'seq #${latest.sequence} · ${latest.timestamp} · '
                        'rssi ${_rssi(device)} · batt ${_batt(device)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: AppTheme.inkFaint)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
        ],
      ),
    );
  }

  String _rssi(IotDevice device) {
    final signal = device.signalStrength;
    return signal == null ? '—' : '${signal.round()} dBm';
  }

  String _batt(IotDevice device) {
    final battery = device.batteryPercent;
    return battery == null ? '—' : '${battery.round()}%';
  }
}

IotDevice? _deviceFor(HoneyChainStore store, String hiveId) {
  for (final device in store.apiDevices) {
    if (device.assignedHiveId == hiveId) return device;
  }
  return null;
}

/// One row of the hive's recent health screening history.
class _HealthCheckRow extends StatelessWidget {
  const _HealthCheckRow({required this.check});

  final HealthCheckEvent check;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final (label, accent) = switch (check.outcome) {
      DiseaseScreenOutcome.possibleDisease => (
          store.tr('health.possible'),
          AppTheme.orange,
        ),
      DiseaseScreenOutcome.unableToAssess => (
          store.tr('health.unable'),
          AppTheme.teal,
        ),
      DiseaseScreenOutcome.noObviousSigns => (
          store.tr('health.none'),
          AppTheme.green,
        ),
    };
    final condition = check.conditionId != null
        ? DiseaseClassCatalog.byId(check.conditionId).label
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.health_and_safety_outlined, color: accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                if (condition != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    condition,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.inkFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            formatDate(check.checkedAt),
            style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
          ),
        ],
      ),
    );
  }
}