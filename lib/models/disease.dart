/// Disease screening domain types.
///
/// The screening feature is an AI-assisted FIRST-LINE check only — it is never
/// a confirmed veterinary/medical diagnosis. All wording stays qualitative
/// ("possible disease signs") and no fabricated accuracy/confidence numbers
/// are ever shown.
library;

/// Qualitative outcome of a photo-based hive screening.
enum DiseaseScreenOutcome { possibleDisease, noObviousSigns, unableToAssess }

/// A possible bee disease the screening model can look for.
///
/// Kept as a small catalog so additional classes can be added later without
/// any UI redesign.
class DiseaseClass {
  const DiseaseClass({required this.id, required this.label});

  final String id;
  final String label;
}

class DiseaseClassCatalog {
  DiseaseClassCatalog._();

  /// Demo classes currently configured for the screening model.
  static const List<DiseaseClass> all = [
    DiseaseClass(id: 'efb', label: 'EFB'),
  ];

  static DiseaseClass byId(String? id) {
    for (final c in all) {
      if (c.id == id) return c;
    }
    return all.first;
  }
}

/// Qualitative result of a photo screening. The UI only consumes this; it never
/// talks to the machine-learning backend directly.
class DiseaseScreeningResult {
  const DiseaseScreeningResult({
    required this.outcome,
    this.condition,
    this.indicators = const [],
    this.actions = const [],
  });

  final DiseaseScreenOutcome outcome;

  /// Possible condition when [outcome] is [DiseaseScreenOutcome.possibleDisease].
  final DiseaseClass? condition;

  /// Observed visual indicators (State A).
  final List<String> indicators;

  /// Recommended next actions (State A).
  final List<String> actions;
}

/// A locally stored health screening event for a hive (offline-first).
class HealthCheckEvent {
  const HealthCheckEvent({
    required this.id,
    required this.hiveId,
    required this.checkedAt,
    required this.outcome,
    this.conditionId,
    this.note,
  });

  final String id;
  final String hiveId;
  final DateTime checkedAt;
  final DiseaseScreenOutcome outcome;
  final String? conditionId;
  final String? note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'hiveId': hiveId,
        'checkedAt': checkedAt.toIso8601String(),
        'outcome': outcome.name,
        'conditionId': conditionId,
        'note': note,
      };

  factory HealthCheckEvent.fromJson(Map<String, dynamic> json) =>
      HealthCheckEvent(
        id: json['id'] as String? ?? '',
        hiveId: json['hiveId'] as String? ?? '',
        checkedAt: DateTime.tryParse(json['checkedAt'] as String? ?? '') ??
            DateTime.now(),
        outcome: DiseaseScreenOutcome.values.firstWhere(
          (o) => o.name == json['outcome'],
          orElse: () => DiseaseScreenOutcome.noObviousSigns,
        ),
        conditionId: json['conditionId'] as String?,
        note: json['note'] as String?,
      );
}