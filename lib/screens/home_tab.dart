import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../theme/beekeeper_tokens.dart';
import '../widgets/beekeeper_widgets.dart';
import 'bee_alert_detail_screen.dart';
import 'record_harvest_screen.dart';
import 'voice_harvest_screen.dart';

/// The beekeeper portal Home, matching the reference layout: header ->
/// online/offline -> greeting -> overall hive health -> current attention ->
/// two primary actions (My Hives / Record Harvest) -> today's weather ->
/// voice entry. All data flows from the existing HoneyChainStore (never faked
/// here), and every label is localized via the store.
class HomeTab extends StatelessWidget {
  const HomeTab({super.key, this.onGoToHives});

  /// Switches the parent shell to the Hives tab (used by the My Hives tile).
  final VoidCallback? onGoToHives;

  /// Opens the existing voice harvest flow from the persistent mic FAB.
  static void openVoice(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VoiceHarvestScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final needCare = store.needsCareCount;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: BeeTokens.spaceGutter,
              vertical: BeeTokens.spaceMd,
            ),
            children: [
              _Header(),
              const SizedBox(height: 12),
              const BeekeeperSyncStatus(),
              const SizedBox(height: 4),
              _Greeting(),
              const SizedBox(height: 14),
              _AlertsSection(needCare: needCare, hiveCount: store.hives.length),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BeekeeperPrimaryAction(
                      icon: Icons.hive_rounded,
                      iconColor: AppTheme.greenDark,
                      iconTint: AppTheme.greenSoft,
                      title: store.tr('home.my.hives'),
                      subtitle: store.tr('home.my.hives.action.sub'),
                      onTap: onGoToHives,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BeekeeperPrimaryAction(
                      icon: Icons.add_circle_outline_rounded,
                      iconColor: AppTheme.orangeDark,
                      iconTint: AppTheme.orangeSoft,
                      title: store.tr('home.record.harvest'),
                      subtitle: store.tr('home.record.harvest.sub'),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RecordHarvestScreen(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const BeekeeperAmbientStrip(),
              const SizedBox(height: 16),
              BeekeeperVoiceButton(
                title: store.tr('voice.ask'),
                subtitle: store.tr('home.voice.sub'),
                onTap: () => HomeTab.openVoice(context),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppTheme.honey.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.hive_rounded, color: AppTheme.honeyDark, size: 26),
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
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              Text(
                store.profile.organizationName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.inkSoft,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text(
            store.language.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppTheme.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}

/// ONE "Hive Alerts" section on Home: a heading plus a single row. When hives
/// need attention the row is the aggregate alert (title "N hives need
/// attention", subtitle = top hive's issue, tappable into alert detail). When
/// everything is fine the row is a calm all-clear. There is deliberately no
/// second health banner on Home.
class _AlertsSection extends StatelessWidget {
  const _AlertsSection({required this.needCare, required this.hiveCount});

  final int needCare;
  final int hiveCount;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            store.tr('home.alerts.title').toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppTheme.inkFaint,
            ),
          ),
        ),
        if (needCare > 0)
          _AttentionRow(store: store, needCare: needCare)
        else
          BeekeeperAlertRow(
            title: store
                .tr('home.all.healthy')
                .replaceFirst('{count}', '$hiveCount'),
            subtitle: store.tr('home.all.healthy.sub'),
            level: BeeStatusLevel.healthy,
          ),
      ],
    );
  }
}

/// Single aggregated "what needs attention?" row. Uses the attention count as
/// its title so Home shows exactly one alert line (never a list, never a
/// second banner). Tapping opens the reference-style alert detail screen.
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.store, required this.needCare});

  final HoneyChainStore store;
  final int needCare;

  @override
  Widget build(BuildContext context) {
    final hive = _mostRelevantHive(store);
    if (hive == null) return const SizedBox.shrink();
    final insight = store.insightFor(hive);
    final alert = _newestAlert(store, hive.id);

    final title = needCare == 1
        ? store.tr('home.hive.attention.one')
        : store.tr('home.hive.attention.many').replaceFirst('{count}', '$needCare');

    final String subtitle =
        switch (alert?.type) {
          AlertType.disease => store.tr('alert.disease.note'),
          AlertType.iot => store.tr('alert.iot.note'),
          AlertType.temperature => store.tr('alert.needs.cooling.note'),
          AlertType.humidity =>
            store.tr('alert.needs.care.note').replaceFirst('{hive}', hive.name),
          _ => insight.riskExplanation,
        };

    return BeekeeperAlertRow(
      title: title,
      subtitle: subtitle,
      time: alert != null ? relativeTime(alert.createdAt, store) : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BeeAlertDetailScreen(hive: hive, alert: alert),
        ),
      ),
    );
  }
}

/// Warm local greeting line shown under the sync banner.
class _Greeting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store.tr('home.greeting'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                store.tr('home.greeting.sub'),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.inkSoft,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.hive_outlined,
          size: 44,
          color: AppTheme.honey.withValues(alpha: 0.55),
        ),
      ],
    );
  }
}

Hive? _mostRelevantHive(HoneyChainStore store) {
  final needing = store.hives
      .where((h) => store.insightFor(h).riskLevel != RiskLevel.healthy)
      .toList();
  if (needing.isEmpty) return null;
  needing.sort((a, b) =>
      store.insightFor(b).riskLevel.index.compareTo(store.insightFor(a).riskLevel.index));
  return needing.first;
}

HiveAlert? _newestAlert(HoneyChainStore store, String hiveId) {
  HiveAlert? newest;
  const hiveTypes = {
    AlertType.temperature,
    AlertType.humidity,
    AlertType.disease,
    AlertType.iot,
  };
  for (final a in store.alerts) {
    if (a.hiveId != hiveId) continue;
    if (!hiveTypes.contains(a.type)) continue;
    if (newest == null || a.createdAt.isAfter(newest.createdAt)) newest = a;
  }
  return newest;
}
