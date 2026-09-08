import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../theme/app_theme.dart';
import '../widgets/section_label.dart';

/// Adds a new hive to the beekeeper's apiary. Collects a friendly name,
/// location, nectar/honey source and optional notes, then persists it through
/// the store (offline-first). Follows the same form conventions as
/// [RecordHarvestScreen].
class CreateHiveScreen extends StatefulWidget {
  const CreateHiveScreen({super.key});

  @override
  State<CreateHiveScreen> createState() => _CreateHiveScreenState();
}

class _CreateHiveScreenState extends State<CreateHiveScreen> {
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _honeyType = TextEditingController();
  final _detail = TextEditingController();
  String? _nameError;
  String? _locationError;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _honeyType.dispose();
    _detail.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final location = _location.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'name' : null;
      _locationError = location.isEmpty ? 'location' : null;
    });
    if (name.isEmpty || location.isEmpty) return;

    final store = HoneyChainStore.instance;
    store.addHive(
      name: name,
      location: location,
      honeyType: _honeyType.text,
      detail: _detail.text,
    );
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(store.tr('create.hive.saved'))));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        foregroundColor: AppTheme.ink,
        title: Text(
          store.tr('create.hive.title'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              store.tr('create.hive.subtitle'),
              style: const TextStyle(fontSize: 14, color: AppTheme.inkSoft),
            ),
          ),
          SectionLabel(store.tr('create.hive.name')),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: store.tr('create.hive.name.hint'),
              prefixIcon: const Icon(Icons.hive_rounded, color: AppTheme.honeyDark),
              errorText: _nameError != null ? store.tr('create.hive.invalid.name') : null,
              filled: true,
              fillColor: AppTheme.cardWarm,
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
            ),
          ),
          const SizedBox(height: 22),
          SectionLabel(store.tr('create.hive.location')),
          TextField(
            controller: _location,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: store.tr('create.hive.location.hint'),
              prefixIcon: const Icon(Icons.place_outlined, color: AppTheme.orangeDark),
              errorText: _locationError != null ? store.tr('create.hive.invalid.location') : null,
              filled: true,
              fillColor: AppTheme.cardWarm,
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
            ),
          ),
          const SizedBox(height: 22),
          SectionLabel(store.tr('create.hive.honey.type')),
          TextField(
            controller: _honeyType,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: store.tr('create.hive.honey.type.hint'),
              prefixIcon: const Icon(Icons.local_florist_outlined, color: AppTheme.honeyDark),
              filled: true,
              fillColor: AppTheme.cardWarm,
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
            ),
          ),
          const SizedBox(height: 22),
          SectionLabel(store.tr('create.hive.detail')),
          TextField(
            controller: _detail,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: store.tr('create.hive.detail.hint'),
              prefixIcon: const Icon(Icons.notes_rounded, color: AppTheme.inkSoft),
              filled: true,
              fillColor: AppTheme.cardWarm,
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
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.green,
                disabledBackgroundColor: AppTheme.grey,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                store.tr('create.hive.save'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
