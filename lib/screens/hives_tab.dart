import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../theme/beekeeper_tokens.dart';
import '../widgets/beekeeper_widgets.dart';
import '../widgets/sync_status_badge.dart';
import 'create_hive_screen.dart';
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
        final allRaw = store.backendModeActive
            ? store.serverHives.map(store.hiveFromServer).toList()
            : const <Hive>[];
        final all = allRaw.isNotEmpty ? allRaw : store.hives;
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      store.tr('my.hives.title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  _AddHiveAction(onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateHiveScreen(),
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                store.tr('my.hives.subtitle').replaceFirst('{count}', '${all.length}'),
                style: const TextStyle(color: AppTheme.inkSoft, fontSize: 14),
              ),
              const SizedBox(height: 12),
              if (store.backendModeActive)
                _BackendHivesBanner(
                  store: store,
                  showingServer: allRaw.isNotEmpty,
                  onRefresh: () => store.refreshServerCollections(),
                ),
              const SyncStatusBadge(),
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
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CreateHiveScreen(),
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: Text(
                            store.tr('hive.list.add'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
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

/// Compact "Add Hive" pill shown beside the My Hives title so it stays visible
/// without consuming vertical space ahead of the hive list.
class _AddHiveAction extends StatelessWidget {
  const _AddHiveAction({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Material(
      color: AppTheme.green.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: AppTheme.greenDark, size: 18),
              const SizedBox(width: 4),
              Text(
                store.tr('hive.list.add'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.greenDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Green banner shown when the beekeeper is signed into the live backend.
/// Reports which collections are live and offers a one-tap refresh.
class _BackendHivesBanner extends StatelessWidget {
  const _BackendHivesBanner({
    required this.store,
    required this.showingServer,
    required this.onRefresh,
  });

  final HoneyChainStore store;
  final bool showingServer;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final identity = store.backendIdentity;
    final serverCount = store.serverHives.length;
    final role = store.backendDisplayRole;
    final email = identity?.email ?? '';
    final status = store.blockchainHealth;
    final chain = status?.isConnected == true
        ? '${status?.channel ?? ''} · ${status?.chaincode ?? ''}'
        : 'Fabric offline';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(BeeTokens.radiusLg),
        border: Border.all(color: AppTheme.green.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined,
              color: AppTheme.greenDark, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Live backend · $role',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.greenDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email.isNotEmpty ? email : store.backendError ?? '',
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  showingServer
                      ? 'Showing $serverCount hives from backend'
                      : chain,
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.inkSoft),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            tooltip: 'Refresh backend collections',
            icon: store.serverCollectionsBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
