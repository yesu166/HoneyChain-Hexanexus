import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/section_label.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final profile = store.profile;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppTheme.orangeSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: AppTheme.orangeDark,
                    size: 40,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  profile.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  store.tr('profile.member').replaceFirst(
                      '{id}', profile.memberId),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.inkFaint,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.greenSoft,
                  borderRadius: AppTheme.radiusCard,
                  border: Border.all(
                    color: AppTheme.green.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.tr('profile.organization.label').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: AppTheme.green,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.organizationName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.location,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _StatCard(
                    value: '${store.hives.length}',
                    label: store.tr('profile.hives.managed'),
                  ),
                  const SizedBox(width: 10),
                  _StatCard(
                    value: '${store.harvestCount}',
                    label: store.tr('profile.total.harvests'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SectionLabel(store.tr('profile.language')),
              _ActionTile(
                icon: Icons.language_rounded,
                title: store.currentLang.nativeName,
                subtitle: store.tr('profile.language.change'),
                onTap: () => _pickLanguage(context),
              ),
              const SizedBox(height: 16),
              _ActionTile(
                icon: Icons.edit_outlined,
                title: store.tr('profile.edit'),
                onTap: () => _editProfile(context),
              ),
              const SizedBox(height: 16),
              _ActionTile(
                icon: Icons.logout_rounded,
                title: store.tr('profile.logout'),
                destructive: true,
                onTap: () => _confirmLogout(context),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
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

  Future<void> _editProfile(BuildContext context) async {
    final store = HoneyChainStore.instance;
    final name = TextEditingController(text: store.profile.name);
    final location = TextEditingController(text: store.profile.location);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          store.tr('profile.edit'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: store.tr('profile.field.name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: location,
              decoration: InputDecoration(
                labelText: store.tr('profile.field.location'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              store.tr('action.cancel'),
              style: const TextStyle(color: AppTheme.inkFaint),
            ),
          ),
          FilledButton(
            onPressed: () {
              store.updateProfile(
                name: name.text.trim().isEmpty ? null : name.text.trim(),
                location: location.text.trim().isEmpty
                    ? null
                    : location.text.trim(),
              );
              Navigator.of(dialogContext).pop();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.orange,
            ),
            child: Text(
              store.tr('profile.edit.save'),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final store = HoneyChainStore.instance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          store.tr('profile.logout'),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.ink,
          ),
        ),
        content: Text(
          store.tr('prompt.logout'),
          style: const TextStyle(color: AppTheme.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              store.tr('action.cancel'),
              style: const TextStyle(color: AppTheme.inkFaint),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              store.tr('action.confirm'),
              style: const TextStyle(
                color: AppTheme.red,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      store.logout();
      // Profile is opened as a pushed destination from the More menu; pop it
      // so the app returns to the first-launch role gate after logout.
      if (!context.mounted) return;
      Navigator.of(context).pop();
    }
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: AppTheme.ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.inkFaint,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.destructive = false,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = destructive ? AppTheme.red : AppTheme.orangeDark;
    return Material(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: destructive
                  ? AppTheme.red.withValues(alpha: 0.35)
                  : AppTheme.border,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: destructive ? AppTheme.ink : AppTheme.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.inkFaint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}