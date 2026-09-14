import 'package:flutter/material.dart';

/// Canonical session state derived from the persisted login, the compiled-in
/// backend configuration and live connectivity — one source of truth instead
/// of uncoordinated booleans.
enum AuthState {
  /// Session unknown (app still starting).
  unknown,

  /// No active session; the first-launch gate is shown.
  signedOut,

  /// Session active and the backend health probe succeeded.
  authenticated,

  /// Session active but no backend is reachable: either no API_BASE_URL was
  /// compiled in, the backend is unreachable, or the device is offline. The
  /// app keeps working on local data in this state (never fakes success).
  offlineAuthenticated,
}

/// A first-class workspace of the single user session. Switching workspaces
/// changes the portal that is shown without logging out and without re-entering
/// any persona login.
enum Workspace {
  beekeeper,
  organization,
  lab,
  processor,
  buyer,
  institution,
  consumer,
  platform;

  String get code => name;

  static Workspace fromCode(String? code) {
    for (final w in Workspace.values) {
      if (w.code == code) return w;
    }
    return Workspace.beekeeper;
  }

  String get title => switch (this) {
        Workspace.beekeeper => 'Beekeeper',
        Workspace.organization => 'FPO',
        Workspace.lab => 'Laboratory',
        Workspace.processor => 'Processor',
        Workspace.buyer => 'Buyer',
        Workspace.institution => 'Institution',
        Workspace.consumer => 'Consumer',
        Workspace.platform => 'Platform Oversight',
      };

  String get subtitle => switch (this) {
        Workspace.beekeeper => 'Hives, harvests and traceability',
        Workspace.organization => 'Collections, batches and products',
        Workspace.lab => 'Lab verification and certificates',
        Workspace.processor => 'Processing and packaging',
        Workspace.buyer => 'Jars and product purchases',
        Workspace.institution => 'Programme oversight',
        Workspace.consumer => 'Scan, verify and read the Honey Passport',
        Workspace.platform => 'Organization lifecycle and membership governance',
      };

  IconData get icon => switch (this) {
        Workspace.beekeeper => Icons.hive_outlined,
        Workspace.organization => Icons.storefront_outlined,
        Workspace.lab => Icons.science_outlined,
        Workspace.processor => Icons.factory_outlined,
        Workspace.buyer => Icons.shopping_bag_outlined,
        Workspace.institution => Icons.account_balance_outlined,
        Workspace.consumer => Icons.qr_code_scanner_rounded,
        Workspace.platform => Icons.admin_panel_settings_outlined,
      };

  /// Backend role an identity must have for this workspace (when the account
  /// is backed by the FastAPI backend). Null means the workspace is only
  /// reachable through demo/local personas.
  String? get backendRole => switch (this) {
        Workspace.beekeeper => 'beekeeper',
        Workspace.organization => 'fpo',
        Workspace.lab => 'lab',
        Workspace.processor => 'processor',
        Workspace.buyer => 'buyer',
        Workspace.institution => null,
        Workspace.consumer => null,
        Workspace.platform => 'platform_oversight',
      };

  /// Seeded demo login for this workspace (used only by the demo drawer, never
  /// invented — the account must actually exist in the backend).
  String? get demoLogin => switch (this) {
        Workspace.beekeeper => 'demo@honeychain.in',
        Workspace.organization => 'org@honeychain.in',
        Workspace.lab => 'lab@honeychain.in',
        Workspace.buyer => null,
        Workspace.processor => null,
        Workspace.institution => null,
        Workspace.consumer => null,
        Workspace.platform => null,
      };
}