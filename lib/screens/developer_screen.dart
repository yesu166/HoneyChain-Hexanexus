import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../services/demo_auth_service.dart';
import '../theme/app_theme.dart';

/// Beekeeper-facing Developer & diagnostics screen. Kept intentionally tucked
/// away in More — never surfaced on Home / My Hives / Hive Detail / Alerts /
/// Bee Health / Record Harvest.
///
/// Every control on this screen is functional: it mutates the real local
/// store so a developer / tester can reproduce scenarios end-to-end.
class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('dev.title'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final target =
                store.seededDemoBatch() ??
                (store.batches.isNotEmpty ? store.batches.first : null);
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.greenSoft,
                    borderRadius: AppTheme.radiusCard,
                    border: Border.all(
                      color: AppTheme.green.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    store.tr('dev.note'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkSoft,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  store.tr('dev.data.title'),
                  style: _sectionTitle,
                ),
                const SizedBox(height: 6),
                _ActionButton(
                  label: store.tr('dev.data.reset'),
                  icon: Icons.restart_alt_rounded,
                  color: AppTheme.orangeDark,
                  onPressed: () {
                    store.resetToDemo();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(store.tr('dev.data.reset.done'))),
                    );
                  },
                ),
                const SizedBox(height: 22),
                Text(
                  store.tr('dev.trust.title'),
                  style: _sectionTitle,
                ),
                const SizedBox(height: 6),
                Text(
                  store.tr('dev.trust.subtitle'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                _TrustTargetPanel(store: store, batch: target),
                const SizedBox(height: 10),
                if (target == null)
                  Text(
                    store.tr('dev.trust.no.batch'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.inkFaint,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(
                        label: store.tr('dev.trust.org.verified'),
                        color: AppTheme.green,
                        onTap: () {
                          if (store.custodyFor(target).isEmpty) {
                            store.acceptV2Custody(target);
                          }
                        },
                      ),
                      _Pill(
                        label: store.tr('dev.trust.lab.verified'),
                        color: AppTheme.blue,
                        onTap: () =>
                            store.verifyV2Batch(target, VerificationStatus.pass),
                      ),
                      _Pill(
                        label: store.tr('dev.trust.anchor'),
                        color: AppTheme.purple,
                        onTap: () =>
                            store.anchorV2Batch(target, 'BATCH_VERIFIED'),
                      ),
                    ],
                  ),
                const SizedBox(height: 22),
                Text(
                  store.tr('dev.iot.title'),
                  style: _sectionTitle,
                ),
                const SizedBox(height: 6),
                Text(
                  store.tr('dev.iot.subtitle'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(
                      label: store.tr('demo.healthy'),
                      color: AppTheme.green,
                      onTap: () => store.demoSimulateHealthy(),
                    ),
                    _Pill(
                      label: store.tr('demo.iot'),
                      color: AppTheme.blue,
                      onTap: () => store.demoSimulateIoTAbnormal(),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  store.tr('dev.disease.title'),
                  style: _sectionTitle,
                ),
                const SizedBox(height: 6),
                Text(
                  store.tr('demo.simulation.note'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkSoft,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(
                      label: store.tr('demo.disease'),
                      color: AppTheme.orange,
                      onTap: () => store.demoSimulatePossibleDisease(),
                    ),
                    _Pill(
                      label: store.tr('demo.unable'),
                      color: AppTheme.teal,
                      onTap: () => store.demoSimulateUnableToAssess(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(store.tr('dev.sync.title'), style: _sectionTitle),
                const SizedBox(height: 6),
                _SyncPanel(store: store),
                const SizedBox(height: 24),
                Text(store.tr('dev.debug.title'), style: _sectionTitle),
                const SizedBox(height: 6),
                _DebugPanel(store: store),
                const SizedBox(height: 30),
              ],
            );
          },
        ),
      ),
    );
  }

  static const TextStyle _sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w800,
    color: AppTheme.ink,
  );
}

class _TrustTargetPanel extends StatelessWidget {
  const _TrustTargetPanel({required this.store, required this.batch});

  final HoneyChainStore store;
  final Batch? batch;

  @override
  Widget build(BuildContext context) {
    final batch = this.batch;
    if (batch == null) return const SizedBox.shrink();
    final trust = store.trustFor(batch);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: AppTheme.orangeDark, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${batch.code} · ${trust.tier.label}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'custody ${trust.custodyCount} · lab ${trust.passCount} · '
                  'anchors ${trust.anchorCount}'
                  '${trust.isPrototypeAnchor ? ' (mock)' : ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.inkSoft,
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

class _DebugPanel extends StatelessWidget {
  const _DebugPanel({required this.store});

  final HoneyChainStore store;

  @override
  Widget build(BuildContext context) {
    final rows = <String, String>{
      store.tr('dev.debug.lang'): store.language.toUpperCase(),
      store.tr('dev.debug.online'): store.isOnline ? 'true' : 'false',
      'Connectivity': store.connectivityStatus.name,
      'Batches': '${store.batches.length}',
      'Jars': '${store.jars.length}',
      'Products': '${store.productBatches.length}',
      'Pending sync': '${store.pendingCount}',
      'Sync attempts': '${store.syncFailureCount}',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          for (final entry in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkFaint,
                      ),
                    ),
                  ),
                  Text(
                    entry.value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
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

class _SyncPanel extends StatelessWidget {
  const _SyncPanel({required this.store});

  final HoneyChainStore store;

  Future<void> _sync(BuildContext context) async {
    await store.syncPendingNow();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync pass done · pending ${store.pendingCount}')),
      );
    }
  }

  Future<void> _signIn(BuildContext context, Future<bool> Function() signIn) async {
    final ok = await signIn();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Signed in to Supabase' : 'Sign-in failed (is --dart-define set?)',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = DemoAuthService.signedInEmail();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.tr('dev.sync.status').replaceFirst(
                  '{status}',
                  store.connectivityStatus.name,
                ),
            style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
          ),
          const SizedBox(height: 4),
          Text(
            email != null
                ? store.tr('dev.sync.signed.in').replaceFirst('{email}', email)
                : store.tr('dev.sync.not.configured'),
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.inkFaint,
            ),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            label: store.tr('dev.sync.now'),
            icon: Icons.sync_rounded,
            color: AppTheme.green,
            onPressed: () => _sync(context),
          ),
          const SizedBox(height: 8),
          _ActionButton(
            label: store.tr('dev.sync.clear'),
            icon: Icons.cleaning_services_rounded,
            color: AppTheme.grey,
            onPressed: store.clearSyncErrors,
          ),
          const SizedBox(height: 8),
          _ActionButton(
            label: store.tr('dev.sync.signin.beekeeper'),
            icon: Icons.person_rounded,
            color: AppTheme.blue,
            onPressed: () => _signIn(context, DemoAuthService.signInBeekeeper),
          ),
          const SizedBox(height: 8),
          _ActionButton(
            label: store.tr('dev.sync.signin.org'),
            icon: Icons.apartment_rounded,
            color: AppTheme.purple,
            onPressed: () =>
                _signIn(context, DemoAuthService.signInOrganization),
          ),
          const SizedBox(height: 8),
          _ActionButton(
            label: store.tr('dev.sync.signout'),
            icon: Icons.logout_rounded,
            color: AppTheme.orangeDark,
            onPressed: DemoAuthService.signOut,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: color),
        label: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}