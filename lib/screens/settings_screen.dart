import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';

/// Lightweight Settings panel for the beekeeper. Currently shows the app
/// language (moved here so More stays clean) — everything else that would be
/// "settings" lives in Profile. Kept minimal and honest.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('more.settings'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            SectionTitle(store.tr('settings.general')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language_rounded, color: AppTheme.orangeDark),
              title: Text(
                store.tr('settings.language'),
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.ink),
              ),
              subtitle: Text(
                store.currentLang.nativeName,
                style: const TextStyle(color: AppTheme.inkFaint),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.inkFaint),
              onTap: () => _pickLanguage(context),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardWarm,
                borderRadius: AppTheme.radiusCard,
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                store.tr('settings.note'),
                style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLanguage(BuildContext context) async {
    final store = HoneyChainStore.instance;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                store.tr('prompt.language'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ),
            for (final lang in AppLanguages.all)
              ListTile(
                leading: Icon(
                  store.currentLang == lang
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: store.currentLang == lang
                      ? AppTheme.orange
                      : AppTheme.inkFaint,
                ),
                title: Text(
                  lang.nativeName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                onTap: () {
                  store.setLanguage(lang.code);
                  Navigator.of(sheetContext).pop();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppTheme.inkFaint,
        ),
      ),
    );
  }
}
