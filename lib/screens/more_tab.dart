import 'package:flutter/material.dart';

import '../data/auth.dart';
import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';
import '../screens/alerts_tab.dart';
import '../screens/iot_simulator_screen.dart';
import '../bee_health/screens/bee_health_home_screen.dart';
import 'buyer/buyer_portal_screen.dart';
import 'consumer_screen.dart';
import 'developer_screen.dart';
import 'honey_tab.dart';
import 'lab_screen.dart';
import 'org/org_portal_screen.dart';
import 'platform/platform_shell.dart';
import 'productivity_screen.dart';
import 'profile_tab.dart';
import 'settings_screen.dart';
import '../theme/beekeeper_tokens.dart';
import '../widgets/beekeeper_widgets.dart';

/// The consolidated 3rd destination: a single scrollable menu that keeps every
/// beekeeper feature reachable (My Honey/Batches, Bee Health, Alerts, Guides,
/// Profile, Language, Settings, Developer) without crowding the Home dashboard.
///
/// The user's role comes from their authenticated session only — there is no
/// manual "switch role" control here. The current workspace (set at sign-in) is
/// shown as context, and a single portal entry opens that workspace's portal
/// (FPO / Lab / Buyer / Consumer / Platform) when the account is entitled to it.
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
              _CurrentWorkspaceCard(),
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
                icon: Icons.insights_rounded,
                iconColor: AppTheme.honeyDark,
                iconTint: AppTheme.tint(AppTheme.honey),
                title: store.tr('more.productivity'),
                subtitle: store.tr('more.productivity.sub'),
                onTap: () => _push(context, const ProductivityScreen()),
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
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: AppTheme.border,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'DEMO & DIAGNOSTICS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppTheme.inkFaint,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: AppTheme.border,
                    ),
                  ),
                ],
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
              const SizedBox(height: 12),
              BeekeeperActionCard(
                icon: Icons.memory_rounded,
                iconColor: AppTheme.teal,
                iconTint: AppTheme.tint(AppTheme.teal),
                title: 'IoT Simulator',
                subtitle: 'Register devices, run demos, view telemetry '
                    '(demo/admin, needs a running backend).',
                onTap: () => _push(context, const IotSimulatorScreen()),
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

  /// The portal screen modeled for a workspace, or null when the app has no
  /// dedicated portal for it (the beekeeper experience IS this shell).
  static Widget? _portalFor(Workspace workspace) {
    return switch (workspace) {
      Workspace.organization => const OrgPortalScreen(),
      Workspace.lab => const LabScreen(),
      Workspace.buyer => const BuyerPortalScreen(),
      Workspace.consumer => const ConsumerScreen(),
      Workspace.platform => const PlatformShell(),
      Workspace.beekeeper ||
      Workspace.processor ||
      Workspace.institution =>
        null,
    };
  }

  /// Opens the current workspace's portal in place of a persona login. Same
  /// session, no re-authentication: switching only changes the screen. If the
  /// workspace has no modeled portal we say so honestly instead of pretending.
  static void _openWorkspace(BuildContext context, Workspace workspace) {
    final portal = _portalFor(workspace);
    if (portal == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            '${workspace.title} workspace selected. A dedicated portal is not '
            'modeled in this demo; backend authorization still scopes any '
            'server data to the signed-in role.',
          ),
          backgroundColor: AppTheme.honeyDark,
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _wrap('${workspace.title} portal', portal),
      ),
    );
  }
}

/// The user's workspace as derived from the authenticated session — shown as
/// context, never as a role picker. If the current workspace has a modeled
/// portal, a single button opens it; otherwise the card is informational.
class _CurrentWorkspaceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final workspace = store.activeWorkspace;
        final portal = MoreTab._portalFor(workspace);
        if (portal != null) {
          return BeekeeperActionCard(
            icon: workspace.icon,
            iconColor: AppTheme.orangeDark,
            iconTint: AppTheme.orangeSoft,
            title: workspace.title,
            subtitle: workspace.subtitle,
            onTap: () => MoreTab._openWorkspace(context, workspace),
          );
        }
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: AppTheme.radiusCard,
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: AppTheme.orangeSoft,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(workspace.icon,
                    size: 20, color: AppTheme.honeyDark),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${store.authStateLabel} · ${workspace.subtitle}',
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
      },
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Divider(color: AppTheme.border, height: 1);
  }
}
