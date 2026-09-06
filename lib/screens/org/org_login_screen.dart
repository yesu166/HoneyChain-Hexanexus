import 'package:flutter/material.dart';

import '../../data/demo_seed.dart';
import '../../data/honeychain_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_label.dart';
import 'org_portal_screen.dart';

/// Lightweight organization / FPO sign-in for the demo.
///
/// No complex auth — selects the active organization and continues into the
/// [OrgPortalScreen]. Keeps the same cream/orange/green theme as the rest of
/// the app (this is NOT a separate blue admin dashboard).
class OrgLoginScreen extends StatefulWidget {
  const OrgLoginScreen({super.key});

  @override
  State<OrgLoginScreen> createState() => _OrgLoginScreenState();
}

class _OrgLoginScreenState extends State<OrgLoginScreen> {
  final _name = TextEditingController(text: '');
  String _orgId = 'ORG-TN-001';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final store = HoneyChainStore.instance;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.tr('org.login.name.error'))),
      );
      return;
    }
    store.setActiveFpoOrg(_orgId);
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OrgPortalScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(store.tr('org.login.appbar')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          children: [
            Text(
              store.tr('org.login.heading'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              store.tr('org.login.desc'),
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.inkSoft,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 26),
            SectionLabel(store.tr('org.login.select.org')),
            Card(
              child: Column(
                children: [
                  for (final org in DemoSeed.organizations)
                    _OrgTile(
                      name: org.name,
                      id: org.id,
                      selected: org.id == _orgId,
                      onTap: () => setState(() => _orgId = org.id),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SectionLabel(store.tr('org.login.your.name')),
            TextField(
              controller: _name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.ink,
              ),
              decoration: InputDecoration(
                hintText: store.tr('org.login.hint'),
                border: OutlineInputBorder(
                  borderRadius: AppTheme.radiusField,
                ),
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _busy ? null : _continue,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.green,
                  disabledBackgroundColor: AppTheme.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward, size: 20),
                label: Text(
                  store.tr('org.login.continue'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrgTile extends StatelessWidget {
  const _OrgTile({
    required this.name,
    required this.id,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String id;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected ? AppTheme.green : AppTheme.inkFaint,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.ink,
                    ),
                  ),
                  Text(
                    id,
                    style: const TextStyle(
                      color: AppTheme.inkFaint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}