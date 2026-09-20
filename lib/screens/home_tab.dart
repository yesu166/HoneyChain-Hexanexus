import 'package:flutter/material.dart';

import '../bee_health/screens/bee_health_home_screen.dart';
import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import 'bee_alert_detail_screen.dart';
import 'record_harvest_screen.dart';

/// Presentation-only beekeeper dashboard. Existing store/services remain the
/// source of truth; this screen does not introduce new API or domain logic.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key, this.onGoToHives});

  final VoidCallback? onGoToHives;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final healthy = store.hives
            .where((h) => store.insightFor(h).riskLevel == RiskLevel.healthy)
            .length;
        final latest = _latestReading(store);
        final attention = store.needsCareCount;

        return SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              _Header(store: store),
              const SizedBox(height: 14),
              _Hero(
                store: store,
                healthy: healthy,
                attention: attention,
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: store.tr('home.alerts.title')),
              const SizedBox(height: 9),
              _AlertSurface(store: store, attention: attention),
              const SizedBox(height: 18),
              _SectionTitle(title: store.tr('home.quick.actions')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ActionTile(
                      title: store.tr('home.my.hives'),
                      subtitle: store.tr('home.my.hives.action.sub'),
                      icon: Icons.hive_rounded,
                      colors: const [Color(0xFF2F8A58), Color(0xFF1F6843)],
                      onTap: onGoToHives,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionTile(
                      title: store.tr('home.record.harvest.sub'),
                      subtitle: store.tr('home.record.harvest'),
                      icon: Icons.water_drop_rounded,
                      colors: const [Color(0xFFF2B53D), Color(0xFFD98217)],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RecordHarvestScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _TelemetryCard(store: store, reading: latest),
              const SizedBox(height: 18),
              _HealthCard(
                store: store,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const BeeHealthHomeScreen(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.store});

  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    final name = store.profile.name.trim();
    final org = store.profile.organizationName.trim();
    final identity = name.isNotEmpty ? name : org;

    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFD86A), Color(0xFFE9A52D)],
            ),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: AppTheme.honeyGold.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: const Icon(Icons.hive_rounded, color: AppTheme.ink, size: 25),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'HoneyChain',
                style: TextStyle(
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              if (identity.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  identity,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: store.isOnline ? AppTheme.greenSoft : AppTheme.orangeSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: store.isOnline ? AppTheme.green : AppTheme.orange,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                store.isOnline ? store.tr('status.online') : store.tr('status.offline'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: store.isOnline
                      ? AppTheme.greenDark
                      : AppTheme.orangeDark,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.store,
    required this.healthy,
    required this.attention,
  });

  final HoneyChainStore store;
  final int healthy;
  final int attention;

  @override
  Widget build(BuildContext context) {
    final name = store.profile.name.trim().isEmpty
        ? 'Beekeeper'
        : store.profile.name.trim();
    final first = name.split(' ').first;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? store.tr('home.greeting.morning').replaceFirst('{name}', first)
        : hour < 17
            ? store.tr('home.greeting.afternoon').replaceFirst('{name}', first)
            : store.tr('home.greeting.evening').replaceFirst('{name}', first);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFCB50),
            Color(0xFFF0A72D),
            Color(0xFFE7891D),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE8A33D).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -44,
            child: Container(
              width: 155,
              height: 155,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 44,
            bottom: -70,
            child: Container(
              width: 135,
              height: 135,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.09),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: const TextStyle(
                    color: AppTheme.ink,
                    fontSize: 23,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  store.tr('home.greeting.sub'),
                  style: TextStyle(
                    color: AppTheme.ink.withValues(alpha: 0.68),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 330;
                    return Row(
                      children: [
                        Expanded(
                          child: _HeroMetric(
                            value: store.hives.length.toString(),
                            label: store.tr('home.hives.metric'),
                          ),
                        ),
                        if (!compact) _HeroDivider(),
                        Expanded(
                          child: _HeroMetric(
                            value: healthy.toString(),
                            label: store.tr('home.healthy.metric'),
                          ),
                        ),
                        if (!compact) _HeroDivider(),
                        Expanded(
                          child: _HeroMetric(
                            value: attention.toString(),
                            label: store.tr('home.attention.metric'),
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.22),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: AppTheme.ink,
                              size: 21,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: AppTheme.ink,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.ink.withValues(alpha: 0.60),
          ),
        ),
      ],
    );
  }
}

class _HeroDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 31,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: AppTheme.ink.withValues(alpha: 0.18),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: AppTheme.ink,
      ),
    );
  }
}

class _AlertSurface extends StatelessWidget {
  const _AlertSurface({
    required this.store,
    required this.attention,
  });

  final HoneyChainStore store;
  final int attention;

  @override
  Widget build(BuildContext context) {
    final hive = _mostRelevantHive(store);
    final alert = hive == null ? null : _newestAlert(store, hive.id);

    if (attention == 0 || hive == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: AppTheme.greenSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppTheme.green.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.verified_rounded,
              color: AppTheme.green,
              size: 25,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                store.tr('home.all.healthy')
                    .replaceFirst('{count}', store.hives.length.toString()),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.greenDark,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final detail = switch (alert?.type) {
      AlertType.disease => store.tr('alert.disease.note'),
      AlertType.iot => store.tr('alert.iot.note'),
      AlertType.temperature => store.tr('alert.needs.cooling.note'),
      AlertType.humidity =>
        store.tr('alert.needs.care.note').replaceFirst('{hive}', hive.name),
      _ => store.insightFor(hive).riskExplanation,
    };

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BeeAlertDetailScreen(hive: hive, alert: alert),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(15, 14, 12, 14),
          decoration: BoxDecoration(
            color: AppTheme.redSoft,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppTheme.red.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.red.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.priority_high_rounded,
                  color: AppTheme.red,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attention == 1
                          ? store.tr('home.hive.attention.one')
                          : store.tr('home.hive.attention.many')
                              .replaceFirst('{count}', attention.toString()),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 15,
                color: AppTheme.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          height: 126,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: colors.last.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xE6FFFFFF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  const _TelemetryCard({
    required this.store,
    required this.reading,
  });

  final HoneyChainStore store;
  final HiveReading? reading;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final hasData = r != null;
    final healthy = r != null && store.hives.any(
      (hive) => hive.id == r.hiveId &&
          store.insightFor(hive).riskLevel == RiskLevel.healthy,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(17, 17, 17, 15),
      decoration: BoxDecoration(
        color: const Color(0xFF24342C),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF24342C).withValues(alpha: 0.20),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.honeyGold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.sensors_rounded,
                  color: Color(0xFFFFC95A),
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hive Telemetry',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Live sensor snapshot',
                      style: TextStyle(
                        color: Color(0xB8FFFFFF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                hasData
                    ? Icons.wifi_tethering_rounded
                    : Icons.sync_disabled_rounded,
                color: hasData
                    ? const Color(0xFF7ED89A)
                    : const Color(0xB8FFFFFF),
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!hasData)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No live hive telemetry available yet.',
                style: TextStyle(
                  color: Color(0xE6FFFFFF),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 310;
                final columns = compact ? 2 : 3;
                final gap = 7.0;
                final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: width,
                      child: _TelemetryMetric(
                        icon: Icons.thermostat_rounded,
                        label: 'Temperature',
                        value: '${r.temperatureC.toStringAsFixed(1)}°C',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _TelemetryMetric(
                        icon: Icons.water_drop_rounded,
                        label: 'Humidity',
                        value: '${r.humidityPercent.toStringAsFixed(0)}%',
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _TelemetryMetric(
                        icon: Icons.monitor_weight_rounded,
                        label: 'Weight',
                        value: '${r.weightKg.toStringAsFixed(1)} kg',
                      ),
                    ),
                  ],
                );
              },
            ),
          if (hasData) ...[
            const SizedBox(height: 13),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 300;
                final status = Text(
                  healthy ? 'Within range' : 'Needs review',
                  style: TextStyle(
                    color: healthy
                        ? const Color(0xFF8BE0A3)
                        : const Color(0xFFFFC16B),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                );
                final updated = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      color: Color(0xB8FFFFFF),
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'Updated ${_relative(r.recordedAt)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xB8FFFFFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          updated,
                          const SizedBox(height: 5),
                          status,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: updated),
                          const SizedBox(width: 8),
                          status,
                        ],
                      );
              },
            ),
          ],
        ],
      ),
    );
  }

  String _relative(DateTime time) {
    final minutes = DateTime.now().difference(time).inMinutes;
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '${minutes}m ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return '${hours}h ago';
    return '${hours ~/ 24}d ago';
  }
}

class _TelemetryMetric extends StatelessWidget {
  const _TelemetryMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
        margin: const EdgeInsets.only(right: 7),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.075),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFFFFC95A), size: 18),
            const SizedBox(height: 7),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xB8FFFFFF),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.store,
    required this.onTap,
  });

  final HoneyChainStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFFFF4DD),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.honeyGold.withValues(alpha: 0.24),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: AppTheme.greenSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  color: AppTheme.green,
                  size: 24,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.tr('bh.title'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      store.tr('bh.subtitle'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkSoft,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppTheme.inkFaint,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

HiveReading? _latestReading(HoneyChainStore store) {
  HiveReading? latest;
  for (final hive in store.hives) {
    final readings = store.readingsForHive(hive.id);
    if (readings.isEmpty) continue;
    final candidate = readings.last;
    if (latest == null || candidate.recordedAt.isAfter(latest.recordedAt)) {
      latest = candidate;
    }
  }
  return latest;
}

Hive? _mostRelevantHive(HoneyChainStore store) {
  final needing = store.hives
      .where((h) => store.insightFor(h).riskLevel != RiskLevel.healthy)
      .toList();
  if (needing.isEmpty) return null;
  needing.sort(
    (a, b) => store
        .insightFor(b)
        .riskLevel
        .index
        .compareTo(store.insightFor(a).riskLevel.index),
  );
  return needing.first;
}

HiveAlert? _newestAlert(HoneyChainStore store, String hiveId) {
  HiveAlert? newest;
  const types = {
    AlertType.temperature,
    AlertType.humidity,
    AlertType.disease,
    AlertType.iot,
  };
  for (final alert in store.alerts) {
    if (alert.hiveId != hiveId) continue;
    if (!types.contains(alert.type)) continue;
    if (newest == null || alert.createdAt.isAfter(newest.createdAt)) {
      newest = alert;
    }
  }
  return newest;
}
