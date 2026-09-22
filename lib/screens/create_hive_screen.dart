import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../theme/app_theme.dart';
import '../widgets/section_label.dart';

/// Creates a beekeeper-owned hive using the same local-first store as every
/// other beekeeper workflow.
///
/// The hive name is the human identity shown throughout the app. The store
/// keeps its generated id separately, so a name such as "LSO" can never be
/// replaced by the display code (for example HC-H1).
class CreateHiveScreen extends StatefulWidget {
  const CreateHiveScreen({super.key});

  @override
  State<CreateHiveScreen> createState() => _CreateHiveScreenState();
}

class _CreateHiveScreenState extends State<CreateHiveScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _honeyType = TextEditingController();
  final _detail = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _honeyType.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _name.text.trim();
    final location = _location.text.trim();
    final honeyType = _honeyType.text.trim();
    final detail = _detail.text.trim();

    setState(() => _saving = true);

    final store = HoneyChainStore.instance;

    // Local-first: the hive exists in the app even when the backend is
    // unavailable. The returned domain object is the canonical object for
    // this navigation flow.
    final created = store.addHive(
      name: name,
      location: location,
      honeyType: honeyType,
      detail: detail,
    );

    ServerHive? serverHive;
    Object? backendError;

    if (store.backendModeActive) {
      try {
        serverHive = await store.addHiveToBackend(
          name: name,
          location: location.isEmpty ? null : location,
        );
      } catch (error) {
        // Never discard a successfully persisted local hive because the
        // optional backend write failed.
        backendError = error;
      }
    }

    if (!mounted) return;

    final message = serverHive != null
        ? '${created.name} saved and synced'
        : backendError != null
            ? '${created.name} saved offline; backend sync will retry'
            : store.tr('create.hive.saved');

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              backendError == null ? AppTheme.greenDark : AppTheme.orangeDark,
        ),
      );

    Navigator.of(context).pop<Hive>(created);
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, color: AppTheme.honeyDark),
      filled: true,
      fillColor: AppTheme.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: AppTheme.radiusField,
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppTheme.radiusField,
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppTheme.radiusField,
        borderSide: const BorderSide(color: AppTheme.orange, width: 1.6),
      ),
    );
  }

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
        title: Text(
          store.tr('create.hive.title'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.greenSoft.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppTheme.green.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.hive_rounded,
                      color: AppTheme.greenDark,
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.tr('create.hive.subtitle'),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.inkSoft,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Create it once. Use the same hive everywhere.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.greenDark,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionLabel(store.tr('create.hive.name')),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('create-hive-name'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 64,
              decoration: _fieldDecoration(
                label: store.tr('create.hive.name.hint'),
                hintText: 'e.g. LSO',
                icon: Icons.badge_outlined,
              ).copyWith(counterText: ''),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return store.tr('create.hive.invalid.name');
                }
                return null;
              },
            ),
            const SizedBox(height: 18),
            SectionLabel(store.tr('create.hive.location')),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('create-hive-location'),
              controller: _location,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                label: store.tr('create.hive.location.hint'),
                hintText: 'Optional',
                icon: Icons.place_outlined,
              ),
            ),
            const SizedBox(height: 18),
            SectionLabel(store.tr('create.hive.honey.type')),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('create-hive-honey-type'),
              controller: _honeyType,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                label: store.tr('create.hive.honey.type.hint'),
                hintText: 'Optional',
                icon: Icons.local_florist_outlined,
              ),
            ),
            const SizedBox(height: 18),
            SectionLabel(store.tr('create.hive.detail')),
            const SizedBox(height: 8),
            TextFormField(
              key: const ValueKey('create-hive-detail'),
              controller: _detail,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 4,
              decoration: _fieldDecoration(
                label: store.tr('create.hive.detail.hint'),
                hintText: 'Optional notes',
                icon: Icons.notes_rounded,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardWarm,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.offline_bolt_outlined,
                    color: AppTheme.honeyDark,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'The hive is saved locally first. If the backend is unavailable, it stays available for offline work and can sync later.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.inkSoft,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                key: const ValueKey('create-hive-save'),
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.green,
                  disabledBackgroundColor: AppTheme.grey,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add_rounded, size: 20),
                label: Text(
                  store.tr('create.hive.save'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
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
