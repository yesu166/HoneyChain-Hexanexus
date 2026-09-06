import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ShellDestination {
  final String label;
  final IconData icon;
  final Widget builder;
  const ShellDestination({required this.label, required this.icon, required this.builder});
}

/// Shared responsive shell with role navigation.
/// Uses a NavigationRail on wide (web) layouts and a bottom bar on mobile.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.title, required this.destinations, this.initialIndex = 0});

  final String title;
  final List<ShellDestination> destinations;
  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  for (var i = 0; i < widget.destinations.length; i++)
                    _NavChip(
                      label: widget.destinations[i].label,
                      selected: i == _index,
                      onTap: () => setState(() => _index = i),
                    ),
                ],
              ),
            ),
        ],
      ),
      body: wide ? Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            backgroundColor: AppTheme.cream,
            selectedIconTheme: const IconThemeData(color: AppTheme.honeyDark),
            selectedLabelTextStyle: const TextStyle(color: AppTheme.honeyDark, fontWeight: FontWeight.w700),
            destinations: [
              for (final d in widget.destinations)
                NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: widget.destinations[_index].builder),
        ],
      ) : Scaffold(
        body: widget.destinations[_index].builder,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: Colors.white,
          indicatorColor: AppTheme.honey.withValues(alpha: 0.25),
          destinations: [
            for (final d in widget.destinations)
              NavigationDestination(icon: Icon(d.icon), label: d.label),
          ],
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.honey.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: selected ? AppTheme.honeyDark : Colors.black87)),
        ),
      ),
    );
  }
}
