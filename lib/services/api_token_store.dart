import 'dart:convert';

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
  });

  final String token;
  final String id;
  final String email;
  final String name;
  final String role;
  final String organizationId;

  Map<String, dynamic> toJson() => {
        'token': token,
        'id': id,
        'email': email,
        'name': name,
        'role': role,
        'organizationId': organizationId,
      };

  factory ApiIdentity.fromJson(Map<String, dynamic> json) => ApiIdentity(
        token: json['token'] as String? ?? '',
        id: json['id'] as String? ?? '',
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? '',
        organizationId: json['organizationId'] as String? ?? '',
      );
}

/// Persists the FastAPI JWT + profile across restarts (offline-first: a restart
/// during a sync pass keeps the token so the pending queue can still flush).
class ApiTokenStore {
  ApiTokenStore._();

  static final ApiTokenStore instance = ApiTokenStore._();

  static const _kToken = 'honey.apiToken';
  static const _kIdentity = 'honey.apiIdentity';

  SharedPreferences? _prefs;
  ApiIdentity? _cached;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    // Re-read every time so restart-restore and tests always mirror the
    // persisted identity (the store is a long-lived singleton).
    final raw = _prefs!.getString(_kIdentity);
    if (raw != null) {
      try {
        _cached = ApiIdentity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } on FormatException {
        _cached = null;
      }
    } else {
      _cached = null;
    }
  }

  ApiIdentity? get identity => _cached;

  String? get token => _cached?.token;

  Future<void> save(ApiIdentity identity) async {
    _cached = identity;
    await _prefs?.setString(_kToken, identity.token);
    await _prefs?.setString(_kIdentity, jsonEncode(identity.toJson()));
  }

  Future<void> clear() async {
    _cached = null;
    await _prefs?.remove(_kToken);
    await _prefs?.remove(_kIdentity);
  }
}