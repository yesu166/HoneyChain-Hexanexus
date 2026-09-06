import 'dart:convert';

import 'package:flutter/services.dart';

class DiseaseGuidance {
  const DiseaseGuidance({
    required this.id,
    required this.description,
    required this.signs,
    required this.management,
    required this.warning,
    required this.confirmationRequired,
  });
  final String id;
  final String description;
  final List<String> signs;
  final List<String> management;
  final String warning;
  final String confirmationRequired;
}

class BeeHealthKnowledge {
  BeeHealthKnowledge._();
  static final BeeHealthKnowledge instance = BeeHealthKnowledge._();

  Map<String, dynamic>? _raw;
  String _lang = 'en';

  Future<void> load(String lang) async {
    _lang = lang;
    try {
      final json = await rootBundle.loadString(
        'assets/bee_health/disease_knowledge.json',
      );
      _raw = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      _raw = null;
    }
  }

  String _tr(Map<String, dynamic>? node, String key, [String fallback = '']) {
    if (node == null) return fallback;
    return (node[key] as String?) ?? (node['en'] as String?) ?? fallback;
  }

  DiseaseGuidance guidance(String conditionId) {
    final diseases = (_raw?['diseases'] as Map<String, dynamic>?) ?? {};
    final node = diseases[_jsonKey(conditionId)] as Map<String, dynamic>?;
    final langNode =
        node?[_lang] as Map<String, dynamic>? ??
        node?['en'] as Map<String, dynamic>?;
    final signs = (langNode?['signs'] as List?)?.cast<String>() ?? <String>[];
    final mgmt =
        (langNode?['management'] as List?)?.cast<String>() ?? <String>[];
    return DiseaseGuidance(
      id: conditionId,
      description: _tr(langNode, 'description'),
      signs: signs,
      management: mgmt,
      warning: _tr(langNode, 'warning'),
      confirmationRequired: _tr(langNode, 'confirmationRequired'),
    );
  }

  String get syntheticNotice => (_raw?['syntheticDataNotice'] as String?) ?? '';

  /// Maps canonical condition IDs to the JSON knowledge keys.
  String _jsonKey(String conditionId) => switch (conditionId) {
    'Healthy' => 'healthy',
    'Unknown' => 'unknown',
    _ => conditionId,
  };
}
