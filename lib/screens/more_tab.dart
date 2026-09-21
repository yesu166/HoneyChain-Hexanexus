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
/// Also the workspace switcher: switching to the Organization / FPO portal,
/// Buyer or Consumer opens that experience directly — no separate persona
/// login, because it is the same session.
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
              _WorkspaceSwitcher(),
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

  /// Opens the selected workspace's portal in place of a persona login. Same
  /// session, no re-authentication: switching only changes the screen.
  static void _openWorkspace(BuildContext context, Workspace workspace) {
    if (workspace == Workspace.beekeeper) return;
    if (workspace == Workspace.processor || workspace == Workspace.institution) {
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
        builder: (_) => switch (workspace) {
          Workspace.organization => const OrgPortalScreen(),
          Workspace.lab => const LabScreen(),
          Workspace.buyer => const BuyerPortalScreen(),
          Workspace.consumer => const ConsumerScreen(),
          Workspace.platform => const PlatformShell(),
          Workspace.beekeeper => const SizedBox.shrink(),
          Workspace.processor => const SizedBox.shrink(),
          Workspace.institution => const SizedBox.shrink(),
        },
      ),
    );
  }
}

/// One-tap workspace switching. Shows every workspace the current account can
/// actually enter; switching never ends the session and never re-prompts for a
/// persona login.
class _WorkspaceSwitcher extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final available = store.availableWorkspaces;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Workspace',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.inkSoft,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    store.authStateLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.inkFaint,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final workspace in available)
                  ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          workspace.icon,
                          size: 16,
                          color: workspace == store.activeWorkspace
                              ? AppTheme.ink
                              : AppTheme.inkSoft,
                        ),
                        const SizedBox(width: 6),
                        Text(workspace.title),
                      ],
                    ),
                    selected: workspace == store.activeWorkspace,
                    showCheckmark: false,
                    selectedColor: const Color(0x1FE8A33D),
                    backgroundColor: AppTheme.card,
                    side: BorderSide(
                      color: workspace == store.activeWorkspace
                          ? AppTheme.honeyGold
                          : AppTheme.border,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          workspace == store.activeWorkspace
                              ? FontWeight.w800
                              : FontWeight.w600,
                      color: workspace == store.activeWorkspace
                          ? AppTheme.ink
                          : AppTheme.inkSoft,
                    ),
                    onSelected: (_) {
                      final switched = store.switchWorkspace(workspace);
                      if (!switched || workspace == store.activeWorkspace) {
                        return;
                      }
                      MoreTab._openWorkspace(context, workspace);
                    },
                  ),
              ],
            ),
          ],
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
