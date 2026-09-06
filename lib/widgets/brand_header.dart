import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Brand header with honey hexagon logo and HoneyChain wordmark.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.subtitle});

  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.honey.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.hexagon_outlined, color: AppTheme.honeyDark, size: 28),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HONEYCHAIN',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1, color: Color(0xFF3E2A0C)),
            ),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ],
    );
  }
}
