import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';
import 'ask_my_bee_screen.dart';
import 'home_tab.dart';
import 'hives_tab.dart';
import 'more_tab.dart';
import 'alerts_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        backgroundColor: AppTheme.bg,
        body: IndexedStack(
          index: _index,
          children: [
            HomeTab(
              onGoToHives: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    backgroundColor: AppTheme.bg,
                    appBar: AppBar(
                      backgroundColor: AppTheme.bg,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      foregroundColor: AppTheme.ink,
                      title: Text(
                        store.tr('my.hives.title'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    body: const HivesTab(),
                  ),
                ),
              ),
              onGoToAlerts: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    backgroundColor: AppTheme.bg,
                    appBar: AppBar(
                      backgroundColor: AppTheme.bg,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      foregroundColor: AppTheme.ink,
                      title: Text(
                        store.tr('alerts.title'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    body: const AlertsTab(),
                  ),
                ),
              ),
            ),
            const AskMyBeeScreen(),
            const MoreTab(),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              backgroundColor: AppTheme.card,
              surfaceTintColor: Colors.transparent,
              height: 72,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.10),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: store.tr('nav.home'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.mic_outlined),
                  selectedIcon: const Icon(Icons.mic_rounded),
                  label: store.tr('ask.title'),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.more_horiz_rounded),
                  selectedIcon: const Icon(Icons.menu_rounded),
                  label: store.tr('nav.more'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


