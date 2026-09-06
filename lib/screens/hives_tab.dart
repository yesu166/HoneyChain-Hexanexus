import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../theme/beekeeper_tokens.dart';
import '../widgets/beekeeper_widgets.dart';
import 'hive_details_screen.dart';

class HivesTab extends StatefulWidget {
  const HivesTab({super.key});

  @override
  State<HivesTab> createState() => _HivesTabState();
}

class _HivesTabState extends State<HivesTab> {
  bool _needsCareOnly = false;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final all = store.hives;
        final needsCare =
            all.where((h) => store.insightFor(h).riskLevel != RiskLevel.healthy);
        final shown = _needsCareOnly ? needsCare.toList() : all;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: BeeTokens.spaceGutter,
              vertical: BeeTokens.spaceMd,
            ),
            children: [
              Text(
                store.tr('my.hives.title'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                store.tr('my.hives.subtitle').replaceFirst('{count}', '${all.length}'),
                style: const TextStyle(color: AppTheme.inkSoft, fontSize: 14),
              ),
              const SizedBox(height: 12),
              const BeekeeperSyncStatus(),
              if (needsCare.isNotEmpty) ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _FilterChip(
                      label: '${store.tr('filter.all')} (${all.length})',
                      selected: !_needsCareOnly,
                      onTap: () => setState(() => _needsCareOnly = false),
                    ),
                    _FilterChip(
                      label: '${store.tr('filter.needs.care')} '
                          '(${needsCare.length})',
                      selected: _needsCareOnly,
                      onTap: () => setState(() => _needsCareOnly = true),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(
                    children: [
                      const Icon(Icons.hive_outlined,
                          color: AppTheme.inkFaint, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        store.tr('hive.empty.title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        store.tr('hive.empty.sub'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.inkSoft,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final hive in shown) ...[
                _HiveRow(store: store, hive: hive),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _HiveRow extends StatelessWidget {
  const _HiveRow({required this.store, required this.hive});

  final HoneyChainStore store;
  final Hive hive;

  @override
  Widget build(BuildContext context) {
    final insight = store.insightFor(hive);
    final healthy = insight.riskLevel == RiskLevel.healthy;
    final level = healthy
        ? BeeStatusLevel.healthy
        : BeeStatusLevel.attention;
    final label = healthy
        ? store.tr('hive.status.healthy')
        : store.tr('hive.status.attention');

    final detailParts = [
      if (hive.detail.isNotEmpty) hive.detail,
      if (hive.location.isNotEmpty) hive.location,
    ];
    final subtitle = detailParts.join(' · ');

    return BeekeeperHiveStatusCard(
      title: hive.name.isEmpty ? hive.id : hive.name,
      code: hiveCode(hive),
      level: level,
      statusLabel: label,
      subtitle: subtitle.isEmpty ? null : subtitle,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => HiveDetailsScreen(hive: hive)),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppTheme.orange : AppTheme.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppTheme.orange : AppTheme.border),
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
