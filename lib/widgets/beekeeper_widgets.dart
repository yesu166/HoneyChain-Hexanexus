import 'package:flutter/material.dart';

import '../data/honeychain_store.dart';
import '../models/domain.dart';
import '../services/speech/text_to_speech_service.dart';
import '../theme/app_theme.dart';
import '../theme/beekeeper_tokens.dart';

// ============================================================================
// Reusable beekeeper-only UI foundation.
//
// These components are used exclusively by the beekeeper portal. Shared
// widgets used by other portals (status_pill, section_label, info_tile,
// metric_card, buttons themed in AppTheme.theme) are intentionally NOT used
// here so the beekeeper foundation can evolve without affecting other roles.
//
// Every user-facing label is passed in from localized call sites — components
// never hardcode English strings.
// ============================================================================

// ----------------------------------------------------------------------------
// Card system
// ----------------------------------------------------------------------------

/// Base rounded beekeeper card. Generous padding, subtle elevation, warm
/// white surface. Optionally tappable.
class BeekeeperCard extends StatelessWidget {
  const BeekeeperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BeeTokens.spaceLg),
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: borderColor ?? AppTheme.border),
        boxShadow: const [BeeTokens.shadow],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppTheme.radiusCard,
        child: InkWell(
          borderRadius: AppTheme.radiusCard,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Large tappable action row (icon tile + title + subtitle + chevron).
class BeekeeperActionCard extends StatelessWidget {
  const BeekeeperActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor = AppTheme.orangeDark,
    this.iconTint = AppTheme.orangeSoft,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color iconTint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BeekeeperCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: BeeTokens.iconTile,
            height: BeeTokens.iconTile,
            decoration: BoxDecoration(
              color: iconTint,
              borderRadius:
                  BorderRadius.circular(BeeTokens.radiusLg - 4),
            ),
            child: Icon(icon, color: iconColor, size: BeeTokens.iconLeading),
          ),
          const SizedBox(width: BeeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: BeeTokens.typeCardTitle,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: BeeTokens.typeCaption,
                    color: AppTheme.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppTheme.inkFaint,
            size: BeeTokens.iconLeading,
          ),
        ],
      ),
    );
  }
}

/// Blue informational note card (used for guidance, not diagnosis warnings).
class BeekeeperInfoCard extends StatelessWidget {
  const BeekeeperInfoCard({
    super.key,
    required this.text,
    this.icon = Icons.info_rounded,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: BeeTokens.spaceMd,
        vertical: BeeTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        color: BeeTokens.colorInformation.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(BeeTokens.radiusMd),
        border: Border.all(
          color: BeeTokens.colorInformation.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: BeeTokens.iconBadge, color: BeeTokens.colorInformation),
          const SizedBox(width: BeeTokens.spaceSm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: BeeTokens.typeCaption,
                height: 1.35,
                color: AppTheme.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Status system
// ----------------------------------------------------------------------------

/// Icon + text status pill. Color is NEVER the only indicator.
/// [block] renders a full-width status strip (with optional sublabel);
/// otherwise a compact trailing pill suitable for list rows.
class BeekeeperStatusPill extends StatelessWidget {
  const BeekeeperStatusPill({
    super.key,
    required this.label,
    required this.level,
    this.sublabel,
    this.icon,
    this.block = false,
  });

  final String label;
  final String? sublabel;
  final BeeStatusLevel level;
  final IconData? icon;
  final bool block;

  @override
  Widget build(BuildContext context) {
    final color = level.color;
    final glyph = icon ?? level.icon;
    if (block) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: BeeTokens.spaceLg,
          vertical: BeeTokens.spaceMd,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(BeeTokens.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(glyph, color: color, size: 22),
            ),
            const SizedBox(width: BeeTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(
                      fontSize: BeeTokens.typeStatus,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: color,
                    ),
                  ),
                  if (sublabel != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      sublabel!,
                      style: const TextStyle(
                        fontSize: BeeTokens.typeCaption,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BeeTokens.spaceMd,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.all(Radius.circular(BeeTokens.radiusPill)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(glyph, size: 15, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: BeeTokens.typeCaption,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tall status card for a single hive in a list. Full-card tappable, large
/// hive icon, name + real hive code + detail, trailing status pill.
class BeekeeperHiveStatusCard extends StatelessWidget {
  const BeekeeperHiveStatusCard({
    super.key,
    required this.title,
    required this.level,
    required this.statusLabel,
    this.code,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final BeeStatusLevel level;
  final String statusLabel;

  /// Short machine-readable hive id (e.g. "HC-H001"), derived from the real
  /// hive id — shown under the hive name.
  final String? code;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = level.color;
    return BeekeeperCard(
      borderColor: color.withValues(alpha: 0.35),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 106),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                level == BeeStatusLevel.healthy
                    ? Icons.hive_rounded
                    : Icons.warning_amber_rounded,
                color: color,
                size: 30,
              ),
            ),
            const SizedBox(width: BeeTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: BeeTokens.typeCardTitle + 2,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.ink,
                      height: 1.2,
                    ),
                  ),
                  if (code != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      code!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: BeeTokens.typeCaption,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.inkFaint,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: BeeTokens.typeLabel,
                        color: AppTheme.inkSoft,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: BeeTokens.spaceXs + 4),
            Flexible(
              child: BeekeeperStatusPill(level: level, label: statusLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical metric tile: tinted icon, large value, small label.
class BeekeeperMetricTile extends StatelessWidget {
  const BeekeeperMetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor = AppTheme.orangeDark,
    this.iconTint = AppTheme.orangeSoft,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color iconColor;
  final Color iconTint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: BeeTokens.spaceMd,
        horizontal: BeeTokens.spaceXs + 2,
      ),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(BeeTokens.radiusLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: BeeTokens.iconBadge),
          ),
          const SizedBox(height: BeeTokens.spaceXs + 2),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: BeeTokens.typeStatus,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: BeeTokens.typeCaption,
              color: AppTheme.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Button system
// ----------------------------------------------------------------------------

/// Primary action — full width, minimum 56 dp touch height.
/// Example: [ Record Harvest ]
class BeekeeperPrimaryButton extends StatelessWidget {
  const BeekeeperPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final button = (icon == null)
        ? FilledButton(onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: BeeTokens.iconBadge),
            label: Text(label),
          );
    return SizedBox(
      width: double.infinity,
      height: BeeTokens.touchPrimary,
      child: button,
    );
  }
}

/// Attention action — full width red, minimum 56 dp touch height.
/// Example: [ Check Hive ]
class BeekeeperAttentionButton extends StatelessWidget {
  const BeekeeperAttentionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: BeeTokens.colorAttention,
      foregroundColor: Colors.white,
      elevation: 0,
      minimumSize: const Size(0, BeeTokens.touchPrimary),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(BeeTokens.radiusPill)),
      ),
      textStyle: const TextStyle(
        fontSize: BeeTokens.typeCardTitle,
        fontWeight: FontWeight.w800,
      ),
    );
    final button = (icon == null)
        ? FilledButton(style: style, onPressed: onPressed, child: Text(label))
        : FilledButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon, size: BeeTokens.iconBadge),
            label: Text(label),
          );
    return SizedBox(
      width: double.infinity,
      height: BeeTokens.touchPrimary,
      child: button,
    );
  }
}

/// Secondary action — outlined, 52 dp touch height.
/// Example: [ View Hive ]
class BeekeeperSecondaryButton extends StatelessWidget {
  const BeekeeperSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final button = (icon == null)
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: BeeTokens.iconBadge),
            label: Text(label),
          );
    return SizedBox(
      width: double.infinity,
      height: BeeTokens.touchSecondary,
      child: button,
    );
  }
}

/// Low-emphasis action — text only, minimum 44 dp touch height.
class BeekeeperTextButton extends StatelessWidget {
  const BeekeeperTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, BeeTokens.touchMin),
      ),
      child: Text(label),
    );
  }
}

/// Large tappable action card for the two main jobs on Home (My Hives /
/// Record Harvest). Big touch area, tinted surface, clear single-line title.
class BeekeeperPrimaryAction extends StatelessWidget {
  const BeekeeperPrimaryAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = AppTheme.orangeDark,
    this.iconTint = AppTheme.orangeSoft,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  final Color iconTint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.card,
      borderRadius: AppTheme.radiusCard,
      child: InkWell(
        borderRadius: AppTheme.radiusCard,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 120),
          width: double.infinity,
          padding: const EdgeInsets.all(BeeTokens.spaceLg),
          decoration: BoxDecoration(
            borderRadius: AppTheme.radiusCard,
            border: Border.all(
              color: iconColor.withValues(alpha: 0.35),
              width: 1.4,
            ),
            boxShadow: const [BeeTokens.shadow],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: iconTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(height: BeeTokens.spaceMd),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: BeeTokens.typeCardTitle,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: BeeTokens.typeCaption,
                  color: AppTheme.inkSoft,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single prominent alert row (attention or all-clear). Color is always paired
/// with icon and text. [time] is an optional relative-time hint suffix.
class BeekeeperAlertRow extends StatelessWidget {
  const BeekeeperAlertRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.level = BeeStatusLevel.attention,
    this.time,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final BeeStatusLevel level;
  final String? time;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = level.color;
    final glyph = level == BeeStatusLevel.healthy
        ? Icons.check_circle_rounded
        : Icons.warning_amber_rounded;
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: AppTheme.radiusCard,
      child: InkWell(
        borderRadius: AppTheme.radiusCard,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(BeeTokens.spaceLg),
          decoration: BoxDecoration(
            borderRadius: AppTheme.radiusCard,
            border: Border.all(color: color.withValues(alpha: 0.4), width: 1.4),
          ),
          child: Row(
            children: [
              Container(
                width: BeeTokens.iconTile,
                height: BeeTokens.iconTile,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(glyph, color: color, size: 26),
              ),
              const SizedBox(width: BeeTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: BeeTokens.typeCardTitle,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: BeeTokens.typeLabel,
                        color: AppTheme.inkSoft,
                        height: 1.4,
                      ),
                    ),
                    if (time != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        time!,
                        style: const TextStyle(
                          fontSize: BeeTokens.typeCaption,
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
                size: BeeTokens.iconLeading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wide reading row: tinted icon tile, label + large value, trailing status
/// badge. Optional [delta] shows a change since the previous reading.
class BeekeeperMetricRow extends StatelessWidget {
  const BeekeeperMetricRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.status,
    required this.statusColor,
    this.delta,
    this.iconColor,
    this.iconTint,
  });

  final IconData icon;
  final String label;
  final String value;
  final String status;
  final Color statusColor;

  /// e.g. "+0.5 kg since last check" (localized by the caller).
  final String? delta;
  final Color? iconColor;
  final Color? iconTint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BeeTokens.spaceLg,
        vertical: BeeTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(BeeTokens.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconTint ?? statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor ?? statusColor, size: 24),
          ),
          const SizedBox(width: BeeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: BeeTokens.typeCaption,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkFaint,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: BeeTokens.typeScreenTitle,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                    height: 1.1,
                  ),
                ),
                if (delta != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    delta!,
                    style: TextStyle(
                      fontSize: BeeTokens.typeCaption,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: BeeTokens.spaceMd),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              border: Border.all(color: statusColor.withValues(alpha: 0.35)),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: BeeTokens.typeCaption,
                fontWeight: FontWeight.w800,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Extra-large full-width voice entry button (mic icon + two lines of text).
/// Opens the existing voice harvest flow — text always stays on screen too.
class BeekeeperVoiceButton extends StatelessWidget {
  const BeekeeperVoiceButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: BeeTokens.touchPrimary + 12,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.orangeDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BeeTokens.radiusPill),
          ),
        ),
        icon: const Icon(Icons.mic_rounded, size: 26),
        label: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width "hear this aloud" button. Reads the localized [text] through
/// platform TTS when available, degrading gracefully (text always visible).
class BeekeeperListenButton extends StatelessWidget {
  const BeekeeperListenButton({super.key, required this.text, this.label});

  /// The text to read aloud (already localized by the caller).
  final String text;

  /// Optional custom label; defaults to the shared "Listen" label.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final tts = createTextToSpeechService();
    return SizedBox(
      width: double.infinity,
      height: BeeTokens.touchPrimary + 8,
      child: FilledButton.icon(
        onPressed: () {
          if (!tts.speak(text)) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(content: Text(store.tr('listen.unsupported'))),
              );
          }
        },
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.honey,
          foregroundColor: AppTheme.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BeeTokens.radiusPill),
          ),
        ),
        icon: const Icon(Icons.volume_up_rounded, size: 24),
        label: Text(
          label ?? store.tr('listen.label'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Sync status
// ----------------------------------------------------------------------------

/// Persistent connectivity + sync status banner. Plain language for the
/// beekeeper; automatic sync is handled by the store (there is never a manual
/// "tap to sync" button or technical details).
class BeekeeperSyncStatus extends StatelessWidget {
  const BeekeeperSyncStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final online = store.isOnline;
        final pending = store.pendingCount;
        final (icon, color, label) = online
            ? (Icons.wifi_rounded, BeeTokens.colorHealthy,
                store.tr('home.online.synced'))
            : (Icons.wifi_off_rounded, BeeTokens.colorAttention,
                store.tr('home.offline.synclater'));
        final subtitle = pending > 0
            ? '${store.tr('status.sync.pending')} (${store.pendingCount})'
            : null;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: BeeTokens.spaceMd),
          padding: const EdgeInsets.symmetric(
            horizontal: BeeTokens.spaceMd,
            vertical: BeeTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(BeeTokens.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: BeeTokens.spaceSm),
              Expanded(
                child: Text(
                  subtitle != null ? '$label · $subtitle' : label,
                  style: TextStyle(
                    fontSize: BeeTokens.typeCaption,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Headings
// ----------------------------------------------------------------------------

/// Small uppercase section heading used across the beekeeper UI.
class BeekeeperSectionHeader extends StatelessWidget {
  const BeekeeperSectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: BeeTokens.spaceSm + 2),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: BeeTokens.typeSection,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: AppTheme.inkFaint,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Ambient hive conditions
// ----------------------------------------------------------------------------

/// Informational strip of ambient hive conditions (temperature / humidity)
/// derived from the actual hive readings. Clearly labelled as hive readings —
/// no external weather service is claimed.
class BeekeeperAmbientStrip extends StatelessWidget {
  const BeekeeperAmbientStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final store = HoneyChainStore.instance;
    final hives = store.hives;
    HiveReading? newest;
    for (final h in hives) {
      final readings = store.readingsForHive(h.id);
      if (readings.isEmpty) continue;
      final latest = readings.last;
      if (newest == null || latest.recordedAt.isAfter(newest.recordedAt)) {
        newest = latest;
      }
    }
    final r = newest;
    if (r == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: BeeTokens.spaceMd + 2,
        vertical: BeeTokens.spaceSm + 2,
      ),
      decoration: BoxDecoration(
        color: AppTheme.cardWarm,
        borderRadius: BorderRadius.circular(BeeTokens.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(Icons.wb_sunny_rounded,
              color: AppTheme.honeyDark, size: BeeTokens.iconBadge),
          const SizedBox(width: BeeTokens.spaceSm),
          Text(
            '${r.temperatureC.round()}°C',
            style: const TextStyle(
              fontSize: BeeTokens.typeBody,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(width: BeeTokens.spaceMd),
          Icon(Icons.water_drop_outlined,
              color: AppTheme.blue, size: BeeTokens.iconBadge),
          const SizedBox(width: BeeTokens.spaceSm),
          Text(
            '${r.humidityPercent.round()}%',
            style: const TextStyle(
              fontSize: BeeTokens.typeBody,
              fontWeight: FontWeight.w800,
              color: AppTheme.ink,
            ),
          ),
          const SizedBox(width: BeeTokens.spaceMd),
          Expanded(
            child: Text(
              store.tr('home.weather.title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: BeeTokens.typeCaption,
                color: AppTheme.inkFaint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Short, stable hive code derived from the real hive id
/// (e.g. "hive-001" -> "HC-H001"). Never fabricates a fresh id — it is a
/// display transform of the id already stored for the hive.
String hiveCode(Hive hive) {
  final parts = hive.id.split('-');
  if (parts.length > 1 && parts.last.isNotEmpty) {
    return 'HC-H${parts.last.toUpperCase()}';
  }
  return hive.id.toUpperCase();
}

/// Relative "x time ago" helper for alert surfacing, localised through the
/// existing store translation table.
String relativeTime(DateTime t, HoneyChainStore store) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return store.tr('time.just.now');
  if (diff.inMinutes < 60) {
    return store.tr('time.minutes.ago').replaceFirst('{n}', '${diff.inMinutes}');
  }
  if (diff.inHours < 24) {
    return store.tr('time.hours.ago').replaceFirst('{n}', '${diff.inHours}');
  }
  return store.tr('time.days.ago').replaceFirst('{n}', '${diff.inDays}');
}