import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';
import 'alerts_tab.dart';
import '../bee_health/screens/bee_health_home_screen.dart';
import 'developer_screen.dart';
import 'honey_tab.dart';
import 'profile_tab.dart';
import 'settings_screen.dart';
import '../theme/beekeeper_tokens.dart';
import '../widgets/beekeeper_widgets.dart';

/// The consolidated 3rd destination: a single scrollable menu that keeps every
/// beekeeper feature reachable (My Honey/Batches, Bee Health, Alerts, Guides,
/// Profile, Language, Settings, Developer) without crowding the Home dashboard.
///
/// Deliberately NOT listed here: the Organization / FPO portal, which belongs
/// to the FPO/login role flow, not the beekeeper's menu.
class MoreTab extends StatelessWidget {
  const MoreTab({super.key});

  static void _push(BuildContext context, Widget child) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: BeeTokens.spaceGutter, vertical: BeeTokens.spaceMd),
            children: [
              Text(
                store.tr('more.title'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                store.profile.organizationName,
                style: const TextStyle(color: AppTheme.inkSoft, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              BeekeeperActionCard(
                icon: Icons.pending_actions_rounded,
                iconColor: AppTheme.orangeDark,
                iconTint: AppTheme.orangeSoft,
                title: store.tr('more.my.honey'),
                subtitle: store.tr('more.my.honey.sub'),
                onTap: () => _push(context, _wrap(store.tr('more.my.honey'), const HoneyTab())),
              ),
              const SizedBox(height: 12),
              BeekeeperActionCard(
                icon: Icons.health_and_safety_rounded,
                iconColor: AppTheme.greenDark,
                iconTint: AppTheme.greenSoft,
                title: store.tr('more.bee.health'),
                subtitle: store.tr('more.bee.health.sub'),
                onTap: () => _push(context, const BeeHealthHomeScreen()),
              ),
              const SizedBox(height: 12),
              BeekeeperActionCard(
                icon: Icons.notifications_active_outlined,
                iconColor: AppTheme.red,
                iconTint: AppTheme.redSoft,
                title: store.tr('more.alerts'),
                subtitle: store.tr('more.alerts.sub'),
                onTap: () => _push(context, _wrap(store.tr('more.alerts'), const AlertsTab())),
              ),
              const SizedBox(height: 12),
              BeekeeperActionCard(
                icon: Icons.person_outline_rounded,
                iconColor: AppTheme.ink,
                iconTint: AppTheme.orangeSoft,
                title: store.tr('more.profile'),
                subtitle: store.tr('more.profile.sub'),
                onTap: () => _push(context, _wrap(store.tr('more.profile'), const ProfileTab())),
              ),
              const SizedBox(height: 12),
              _Divider(),
              const SizedBox(height: 12),
              BeekeeperActionCard(
                icon: Icons.translate_rounded,
                iconColor: AppTheme.teal,
                iconTint: AppTheme.tint(AppTheme.teal),
                title: store.tr('more.language'),
                subtitle: store.tr('more.language.sub'),
                onTap: () => _push(context, const SettingsScreen()),
              ),
              const SizedBox(height: 12),
              BeekeeperActionCard(
                icon: Icons.settings_outlined,
                iconColor: AppTheme.blue,
                iconTint: AppTheme.tint(AppTheme.blue),
                title: store.tr('more.settings'),
                subtitle: store.tr('more.settings.sub'),
                onTap: () => _push(context, const SettingsScreen()),
              ),
              const SizedBox(height: 12),
              BeekeeperActionCard(
                icon: Icons.developer_mode_rounded,
                iconColor: AppTheme.ink,
                iconTint: AppTheme.greenSoft,
                title: store.tr('more.developer'),
                subtitle: store.tr('more.developer.sub'),
                onTap: () => _push(context, const DeveloperScreen()),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// Wraps an existing single-purpose tab/panel in a scaffold with a back bar,
  /// reusing it unchanged as a pushed destination.
  static Widget _wrap(String title, Widget body) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
      ),
      body: body,
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(color: AppTheme.border, height: 1);
  }
}
