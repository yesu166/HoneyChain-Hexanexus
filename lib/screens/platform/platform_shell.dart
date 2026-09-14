import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../theme/app_theme.dart';
import 'platform_audit_screen.dart';
import 'platform_organizations_screen.dart';
import 'platform_overview_screen.dart';

/// Platform Oversight workspace shell.
///
/// A distinct, HoneyChain-themed workbench for the `platform_oversight` role:
/// platform-wide stats, FPO organization lifecycle, membership governance and a
/// verifiable audit trail. Every number is read live from the verified
/// `/api/v1/platform/...` endpoints (never fabricated) and the backend's RBAC
/// rejects anyone who is not `platform_oversight`.
class PlatformShell extends StatefulWidget {
  const PlatformShell({super.key});

  @override
  State<PlatformShell> createState() => _PlatformShellState();
}

class _PlatformShellState extends State<PlatformShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Platform Oversight',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppTheme.ink),
            ),
            ListenableBuilder(
              listenable: store,
              builder: (context, _) => Text(
                store.authStateLabel,
                style: const TextStyle(fontSize: 11.5, color: AppTheme.inkFaint),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          PlatformOverviewScreen(),
          PlatformOrganizationsScreen(),
          PlatformAuditScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance_rounded),
            label: 'Organizations',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Audit',
          ),
        ],
      ),
    );
  }
}