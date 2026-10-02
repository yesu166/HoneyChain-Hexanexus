import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';
import 'consumer_screen.dart';
import 'kvic_van_screen.dart';

/// First-launch role gate — the judge-facing demo chooser.
///
/// Exactly THREE primary entries are offered:
///
///   1. BEEKEEPER                      -> phone + OTP login -> beekeeper shell
///   2. KVIC HONEY MISSION / PORTABLE VAN -> real backend sign-in -> van workspace
///   3. CONSUMER                       -> QR scan -> Honey Passport
///
/// This is a demo-entry simplification only. Every other role (FPO, society,
/// laboratory, processor, buyer, distributor, retailer, admin, institution,
/// platform oversight) keeps its backend role, database model, API endpoints
/// and RBAC exactly as before — it is simply no longer a primary choice here.
class WhoAreYouScreen extends StatelessWidget {
  const WhoAreYouScreen({
    super.key,
    required this.onBeekeeper,
    required this.onKvicVan,
  });

  /// Raised when the Beekeeper role is tapped so the parent can swap the
  /// gate for the phone + OTP login without adding a route.
  final VoidCallback onBeekeeper;

  /// Raised when the KVIC Portable Van is tapped so the parent opens the van
  /// workspace (which signs in against the real backend).
  final VoidCallback onKvicVan;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.honeyGold, width: 2),
                  color: AppTheme.card,
                ),
                child: const Icon(
                  Icons.hive_outlined,
                  size: 38,
                  color: AppTheme.honeyDark,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              store.tr('app.title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              store.tr('app.subtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 34),
            Text(
              store.tr('who.are.you'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              store.tr('who.are.you.subtitle'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.inkSoft),
            ),
            const SizedBox(height: 24),
            _RoleOption(
              icon: Icons.person_outline,
              title: store.tr('role.beekeeper'),
              subtitle: store.tr('role.beekeeper.desc'),
              accent: AppTheme.honeyDark,
              onTap: onBeekeeper,
            ),
            const SizedBox(height: 14),
            _RoleOption(
              icon: Icons.local_shipping_outlined,
              title: 'KVIC HONEY MISSION\nPORTABLE VAN',
              subtitle:
                  'Portable van operations: batch intake, origin review, '
                  'quality hand-off and pass-forward.',
              accent: AppTheme.green,
              onTap: onKvicVan,
            ),
            const SizedBox(height: 14),
            _RoleOption(
              icon: Icons.qr_code_scanner_rounded,
              title: store.tr('role.consumer'),
              subtitle: store.tr('role.consumer.desc'),
              accent: AppTheme.teal,
              onTap: () => _openConsumer(context),
            ),
            const SizedBox(height: 22),
            Text(
              store.tr('role.note'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
            ),
          ],
        ),
      ),
    );
  }

  void _openConsumer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConsumerScreen()),
    );
  }
}

/// Opens the KVIC Portable Van workspace. Exposed so the parent gate can route
/// to it without importing the internals of this screen.
Route<void> kvicVanRoute() =>
    MaterialPageRoute<void>(builder: (_) => const KvicVanScreen());

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppTheme.radiusCard,
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: AppTheme.radiusCard,
            border: Border.all(color: AppTheme.border),
            boxShadow: const [AppTheme.shadowCard],
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.tint(accent),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 26, color: accent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.inkSoft,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}