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
            ),
            const VoiceHarvestScreen(),
            const MoreTab(),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.card.withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                height: 70,
                elevation: 0,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.home_outlined),
                  selectedIcon: const Icon(Icons.home_rounded),
                  label: store.tr('nav.home'),
                ),
                NavigationDestination(
                  icon: _AskButton(selected: false),
                  selectedIcon: _AskButton(selected: true),
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
        ),
      ),
    );
  }
}

class _AskButton extends StatelessWidget {
  const _AskButton({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: selected ? 52 : 46,
      height: selected ? 52 : 46,
      decoration: BoxDecoration(
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFD76A), Color(0xFFE9A52D)],
              )
            : null,
        color: selected ? null : AppTheme.orangeSoft,
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.honeyGold.withValues(alpha: selected ? 0.0 : 0.35),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppTheme.honeyGold.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.mic_rounded,
        color: selected ? AppTheme.ink : AppTheme.honeyDark,
        size: 23,
      ),
    );
  }
}
