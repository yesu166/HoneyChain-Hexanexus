import 'package:flutter/material.dart';

/// Consistent section heading with optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onSeeAll,
    this.seeAllLabel = 'See all',
  });

  final String title;
  final Widget? trailing;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF3E2A0C)),
          ),
        ),
        if (trailing != null)
          trailing!
        else if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: Text(seeAllLabel)),
      ],
    );
  }
}
