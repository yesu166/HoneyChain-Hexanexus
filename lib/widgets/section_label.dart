import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small uppercase section label used across beekeeper screens.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: AppTheme.inkFaint,
        ),
      ),
    );
  }
}