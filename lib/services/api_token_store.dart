import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identity returned by the FastAPI backend after a successful login.
class ApiIdentity {
  const ApiIdentity({
    required this.token,
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.organizationId = '',
    this.producerId = '',
  });

  final String token;
  final String id;
  final String email;
  final String name;
  final String role;
  final String organizationId;
  final String producerId;

  Map<String, dynamic> toJson() => {
        'token': token,
        'id': id,
        'email': email,
        'name': name,
        'role': role,
        'organizationId': organizationId,
        'producerId': producerId,
      };

  factory ApiIdentity.fromJson(Map<String, dynamic> json) => ApiIdentity(
        token: json['token'] as String? ?? '',
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? '',
        organizationId: json['organizationId'] as String? ?? '',
        producerId: json['producerId'] as String? ?? '',
      );
}

/// Persists the FastAPI JWT + profile across restarts.
///
/// New sessions use platform secure storage. Older SharedPreferences sessions
/// are migrated once and removed. SharedPreferences remains only as a fallback
/// for test/unsupported runners where secure storage is unavailable.
class ApiTokenStore {
  ApiTokenStore._();

  static final ApiTokenStore instance = ApiTokenStore._();

  static const _kToken = 'honey.apiToken';
  static const _kIdentity = 'honey.apiIdentity';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  SharedPreferences? _legacyPrefs;
  ApiIdentity? _cached;

  Future<void> init() async {
    _legacyPrefs ??= await SharedPreferences.getInstance();

    String? raw;
    try {
      raw = await _secure.read(key: _kIdentity);
    } catch (_) {
      // Unit tests and unsupported runners may not expose a platform plugin.
    }

    // Migrate the JWT/profile left by older builds in SharedPreferences.
    if (raw == null) {
      raw = _legacyPrefs!.getString(_kIdentity);
      if (raw != null) {
        try {
          await _secure.write(key: _kIdentity, value: raw);
          final legacyToken = _legacyPrefs!.getString(_kToken);
          if (legacyToken != null) {
            await _secure.write(key: _kToken, value: legacyToken);
          }
          await _legacyPrefs!.remove(_kIdentity);
          await _legacyPrefs!.remove(_kToken);
        } catch (_) {
          // Keep the legacy copy only when secure storage is unavailable.
        }
      }
    }

    if (raw == null) {
      _cached = null;
      return;
    }

    try {
      _cached = ApiIdentity.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on FormatException {
      _cached = null;
    } on TypeError {
      _cached = null;
    }
  }

  ApiIdentity? get identity => _cached;

  String? get token => _cached?.token;

  Future<void> save(ApiIdentity identity) async {
    _cached = identity;
    final raw = jsonEncode(identity.toJson());
    try {
      await _secure.write(key: _kIdentity, value: raw);
      await _secure.write(key: _kToken, value: identity.token);
      await _legacyPrefs?.remove(_kIdentity);
      await _legacyPrefs?.remove(_kToken);
    } catch (_) {
      // Test/unsupported-platform fallback only.
      await _legacyPrefs?.setString(_kToken, identity.token);
      await _legacyPrefs?.setString(_kIdentity, raw);
    }
  }

  Future<void> clear() async {
    _cached = null;
    try {
      await _secure.delete(key: _kToken);
      await _secure.delete(key: _kIdentity);
    } catch (_) {
      // Clear the fallback below even when the secure plugin is unavailable.
    }
    await _legacyPrefs?.remove(_kToken);
    await _legacyPrefs?.remove(_kIdentity);
  }
}
