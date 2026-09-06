import 'package:flutter/material.dart';
import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/screens/disease_screening_screen.dart';
import 'package:honeychain/theme/app_theme.dart';

class BeePhotoEntryCard extends StatelessWidget {
  const BeePhotoEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: AppTheme.radiusCard,
          border: Border.all(color: AppTheme.border),
          boxShadow: const [AppTheme.shadowCard],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: AppTheme.radiusCard,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _onTap(context, store),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppTheme.orangeSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.photo_camera_outlined,
                      color: AppTheme.orangeDark,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          store.tr('bh.photo.title'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          store.tr('bh.photo.subtitle'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.inkFaint,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, HoneyChainStore store) async {
    if (store.hives.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(store.tr('bh.photo.no.hives'))));
      return;
    }

    final hive = await showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                store.tr('bh.photo.pick.hive'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ),
            for (final h in store.hives)
              ListTile(
                leading: const Icon(
                  Icons.hive_outlined,
                  color: AppTheme.orangeDark,
                ),
                title: Text(
                  h.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                subtitle: h.detail.isNotEmpty ? Text(h.detail) : null,
                onTap: () => Navigator.of(sheetContext).pop(h),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (hive == null || !context.mounted) return;

    final source = await showDiseasePhotoSourceSheet(context);
    if (source == null) return;
    try {
      final picked = source
          ? await store.imageInput.pickFromCamera()
          : await store.imageInput.pickFromGallery();
      if (!context.mounted || picked == null) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DiseaseScreeningScreen(hive: hive, image: picked),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.tr('screening.pick.failed'))),
      );
    }
  }
}
