import 'package:flutter/material.dart';

import 'package:honeychain/theme/app_theme.dart';

/// Public-domain / CC0 visual references used as learning aids.
/// These images are never treated as model predictions or proof of disease.
class DiseaseReferenceGallery extends StatelessWidget {
  const DiseaseReferenceGallery({super.key});

  static const _items = <_ReferenceImage>[
    _ReferenceImage(
      title: 'Deformed wing virus',
      url: 'https://upload.wikimedia.org/wikipedia/commons/a/af/Deformed_wing_virus.png',
    ),
    _ReferenceImage(
      title: 'Varroa / deformed wing signs',
      url: 'https://upload.wikimedia.org/wikipedia/commons/d/d5/Honey_bee_with_Deformed_Wing_Virus_and_Varroa_destructor.jpg',
    ),
    _ReferenceImage(
      title: 'Tracheal mite · Acarapis woodi',
      url: 'https://commons.wikimedia.org/wiki/Special:Redirect/file/Tracheal_mite_-_Acarapis_woodi.jpg',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF8E8), Color(0xFFF4F8F0)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppTheme.honeyGold.withValues(alpha: 0.30),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.honeyGold.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: AppTheme.orangeDark,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Visual reference guide',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Compare signs before answering',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = _items[index];
                return SizedBox(
                  width: 154,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          item.url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppTheme.cardWarm,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.image_not_supported_outlined,
                              color: AppTheme.inkFaint,
                            ),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: AppTheme.cardWarm,
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(9, 18, 9, 8),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color(0xD9000000),
                                ],
                              ),
                            ),
                            child: Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Reference images are educational only — they do not confirm a disease in your hive.',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: AppTheme.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceImage {
  const _ReferenceImage({
    required this.title,
    required this.url,
  });

  final String title;
  final String url;
}
