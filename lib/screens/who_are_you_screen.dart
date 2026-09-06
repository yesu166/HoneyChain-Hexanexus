import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';
import 'buyer/buyer_portal_screen.dart';
import 'consumer_screen.dart';
import 'org/org_login_screen.dart';

/// First-launch role gate: decide who is entering this session.
///
/// Beekeeper -> the existing phone + OTP [LoginScreen] (protects the existing
/// portal). Organization/FPO -> a lightweight org login that opens the
/// organization portal. No complex auth is required for the demo.
class WhoAreYouScreen extends StatelessWidget {
  const WhoAreYouScreen({super.key, required this.onBeekeeper});

  /// Raised when the Beekeeper role is tapped so the parent can swap the
  /// gate for the phone + OTP login without adding a route.
  final VoidCallback onBeekeeper;

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
                  border: Border.all(color: AppTheme.orange, width: 2),
                  color: AppTheme.card,
                ),
                child: const Icon(
                  Icons.hive_outlined,
                  size: 38,
                  color: AppTheme.orangeDark,
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
              emoji: '🐝',
              title: store.tr('role.beekeeper'),
              subtitle: store.tr('role.beekeeper.desc'),
              accent: AppTheme.orange,
              onTap: onBeekeeper,
            ),
            const SizedBox(height: 14),
            _RoleOption(
              icon: Icons.storefront_outlined,
              emoji: '🏢',
              title: store.tr('role.organization'),
              subtitle: store.tr('role.organization.desc'),
              accent: AppTheme.green,
              onTap: () => _openOrganization(context),
            ),
            const SizedBox(height: 14),
            _RoleOption(
              icon: Icons.shopping_bag_outlined,
              emoji: '🛒',
              title: store.tr('role.buyer'),
              subtitle: store.tr('role.buyer.desc'),
              accent: AppTheme.orangeDark,
              onTap: () => _openBuyer(context),
            ),
            const SizedBox(height: 14),
            _RoleOption(
              icon: Icons.qr_code_scanner_rounded,
              emoji: '📱',
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

  void _openOrganization(BuildContext context) {
    final store = HoneyChainStore.instance;
    store.setFpoRole(true);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OrgLoginScreen()),
    );
  }

  void _openBuyer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BuyerPortalScreen()),
    );
  }

  void _openConsumer(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConsumerScreen()),
    );
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.icon,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String emoji;
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
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
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