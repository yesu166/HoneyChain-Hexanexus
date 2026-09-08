import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';
import 'home_tab.dart';
import 'hives_tab.dart';
import 'more_tab.dart';
import 'voice_harvest_screen.dart';

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
                      elevation: 0,
                      foregroundColor: AppTheme.ink,
                      title: Text(
                        store.tr('my.hives.title'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    body: const HivesTab(),
                  ),
                ),
              ),
            ),
            const VoiceHarvestScreen(),
            const MoreTab(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: store.tr('nav.home'),
            ),
            NavigationDestination(
              icon: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.orangeSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.orange.withValues(alpha: 0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_rounded, color: AppTheme.orangeDark, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Ask',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.orangeDark,
                      ),
                    ),
                  ],
                ),
              ),
              selectedIcon: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Ask',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              label: store.tr('voice.ask'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.more_horiz_rounded),
              selectedIcon: const Icon(Icons.menu_rounded),
              label: store.tr('nav.more'),
            ),
          ],
        ),
      ),
    );
  }
}
