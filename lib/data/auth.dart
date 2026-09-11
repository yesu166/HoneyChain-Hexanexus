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
  buyer,
  consumer;

  String get code => name;

  static Workspace fromCode(String? code) {
    for (final w in Workspace.values) {
      if (w.code == code) return w;
    }
    return Workspace.beekeeper;
  }

  String get title => switch (this) {
        Workspace.beekeeper => 'Beekeeper',
        Workspace.organization => 'Organization / FPO',
        Workspace.buyer => 'Buyer',
        Workspace.consumer => 'Consumer',
      };

  String get subtitle => switch (this) {
        Workspace.beekeeper => 'Production, harvests and traceability',
        Workspace.organization => 'Collections, batches, products',
        Workspace.buyer => 'Jars and product purchases',
        Workspace.consumer => 'Scan, verify and read the Honey Passport',
      };

  IconData get icon => switch (this) {
        Workspace.beekeeper => Icons.hive_outlined,
        Workspace.organization => Icons.storefront_outlined,
        Workspace.buyer => Icons.shopping_bag_outlined,
        Workspace.consumer => Icons.qr_code_scanner_rounded,
      };

  /// Backend role an identity must have for this workspace (when the account
  /// is backed by the FastAPI backend). Null means the workspace is only
  /// reachable through demo/local personas.
  String? get backendRole => switch (this) {
        Workspace.beekeeper => 'beekeeper',
        Workspace.organization => 'fpo',
        Workspace.buyer => 'buyer',
        Workspace.consumer => null,
      };
}