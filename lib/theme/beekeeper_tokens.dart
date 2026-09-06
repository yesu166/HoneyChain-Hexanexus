import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Beekeeper-only design tokens.
///
/// These sit ON TOP of the shared [AppTheme] and are never referenced by other
/// portals. They centralise spacing, radii, elevation, touch targets and the
/// type scale so screens and widgets do not scatter arbitrary numbers.
/// Colors are re-used from [AppTheme] so the warm agricultural identity is
/// preserved across the whole app.
abstract class BeeTokens {
  BeeTokens._();

  // ---- Spacing (4 pt scale, generous for field use) ----
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 20;
  static const double spaceXxl = 24;
  static const double spaceGutter = 20; // screen horizontal padding

  // ---- Corner radius ----
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18; // matches AppTheme.radiusCard
  static const double radiusPill = 999;

  // ---- Elevation ----
  static const BoxShadow shadow = AppTheme.shadowCard;

  // ---- Touch targets (gloves / one-handed field use) ----
  static const double touchPrimary = 56;
  static const double touchSecondary = 52;
  static const double touchMin = 44;

  // ---- Type hierarchy (beekeeper intent) ----
  static const double typeScreenTitle = 24;
  static const double typeCardTitle = 16;
  static const double typeStatus = 15;
  static const double typeBody = 14;
  static const double typeLabel = 13;
  static const double typeCaption = 12;
  static const double typeSection = 11;

  // ---- Iconography ----
  static const double iconLeading = 24;
  static const double iconBadge = 20;
  static const double iconTile = 48;

  // ---- Semantic colors ----
  // A status always pairs color with an icon and text (never color alone).
  static Color get colorHealthy => AppTheme.green;
  static Color get colorAttention => AppTheme.red;
  static Color get colorMonitoring => AppTheme.honeyDark;
  static Color get colorInformation => AppTheme.blue;
}

/// Semantic status level used by the beekeeper status system.
enum BeeStatusLevel { healthy, attention, monitoring, information }

extension BeeStatusLevelX on BeeStatusLevel {
  Color get color => switch (this) {
        BeeStatusLevel.healthy => BeeTokens.colorHealthy,
        BeeStatusLevel.attention => BeeTokens.colorAttention,
        BeeStatusLevel.monitoring => BeeTokens.colorMonitoring,
        BeeStatusLevel.information => BeeTokens.colorInformation,
      };

  IconData get icon => switch (this) {
        BeeStatusLevel.healthy => Icons.check_circle_rounded,
        BeeStatusLevel.attention => Icons.error_rounded,
        BeeStatusLevel.monitoring => Icons.query_stats_rounded,
        BeeStatusLevel.information => Icons.info_rounded,
      };
}