import 'package:flutter/material.dart' show Color;

/// Feature IDs in the exact order used by the trained Decision Tree.
/// 0 = No, 1 = Yes, -1 = Not sure. Unasked features default to Not sure (-1).
class BeeHealthFeature {
  const BeeHealthFeature._(this.id, this.name, this.area);
  final String id;
  final String name;
  final String area;

  static const _ids = <String>[
    'brood_spotted_comb',
    'brood_larvae_yellow_curled',
    'brood_sour_odor',
    'adult_crawling_unable_to_fly',
    'adult_k_wing',
    'adult_scattered_clusters',
    'adult_yellow_fecal_spots',
    'adult_swollen_black_abdomen',
  ];

  static const all = <BeeHealthFeature>[
    BeeHealthFeature._('brood_spotted_comb', 'Spotted brood', 'brood'),
    BeeHealthFeature._(
      'brood_larvae_yellow_curled',
      'Larvae yellow/curled',
      'brood',
    ),
    BeeHealthFeature._('brood_sour_odor', 'Sour odor', 'brood'),
    BeeHealthFeature._('adult_crawling_unable_to_fly', 'Crawling', 'adult'),
    BeeHealthFeature._('adult_k_wing', 'K-wing', 'adult'),
    BeeHealthFeature._(
      'adult_scattered_clusters',
      'Scattered clusters',
      'adult',
    ),
    BeeHealthFeature._('adult_yellow_fecal_spots', 'Fecal spots', 'adult'),
    BeeHealthFeature._(
      'adult_swollen_black_abdomen',
      'Swollen abdomen',
      'adult',
    ),
  ];

  static int indexOf(String id) => _ids.indexOf(id);
  static const kCrawling = 'adult_crawling_unable_to_fly';
  static const kWing = 'adult_k_wing';
  static const kScattered = 'adult_scattered_clusters';
  static const kFecal = 'adult_yellow_fecal_spots';
  static const kSwollen = 'adult_swollen_black_abdomen';
  static const kLarvae = 'brood_larvae_yellow_curled';
  static const kSpotted = 'brood_spotted_comb';
  static const kSour = 'brood_sour_odor';
}

enum BeeHealthValue { yes, no, notSure }

extension BeeHealthValueX on BeeHealthValue {
  int get code => switch (this) {
    BeeHealthValue.yes => 1,
    BeeHealthValue.no => 0,
    BeeHealthValue.notSure => -1,
  };
}

BeeHealthValue beeHealthValueFromCode(int code) => switch (code) {
  1 => BeeHealthValue.yes,
  0 => BeeHealthValue.no,
  _ => BeeHealthValue.notSure,
};

/// A condition the screening may report, matching the exported class labels.
class BeeCondition {
  const BeeCondition._(this.id, this.index);
  final String id;
  final int index;

  static const all = <BeeCondition>[
    BeeCondition._('EFB', 0),
    BeeCondition._('Acarine', 1),
    BeeCondition._('Nosema', 2),
    BeeCondition._('Healthy', 3),
    BeeCondition._('Unknown', 4),
  ];

  static BeeCondition byIndex(int i) => all[i.clamp(0, all.length - 1)];
  static BeeCondition? byId(String? id) =>
      all.where((c) => c.id == id).firstOrNull;

  Color get color => switch (id) {
    'EFB' => const Color(0xFFD84315),
    'Acarine' => const Color(0xFF6A1B9A),
    'Nosema' => const Color(0xFF2E7D32),
    'Healthy' => const Color(0xFF2E7D32),
    _ => const Color(0xFF757575),
  };
}

class BeeHealthPrediction {
  const BeeHealthPrediction({
    required this.condition,
    required this.leafPurity,
    required this.isUnknownCoerced,
    this.notes = const [],
  });
  final BeeCondition condition;
  final double leafPurity;
  final bool isUnknownCoerced;
  final List<String> notes;
}

class BeeHealthEvent {
  const BeeHealthEvent({
    required this.id,
    required this.hiveId,
    required this.checkedAt,
    required this.conditionId,
    required this.answers,
    required this.questionsAsked,
    this.note,
  });
  final String id;
  final String hiveId;
  final DateTime checkedAt;
  final String conditionId;
  final Map<String, int> answers;
  final int questionsAsked;
  final String? note;

  Map<String, dynamic> toJson() => {
    'id': id,
    'hiveId': hiveId,
    'checkedAt': checkedAt.toIso8601String(),
    'conditionId': conditionId,
    'answers': answers,
    'questionsAsked': questionsAsked,
    'note': note,
  };

  factory BeeHealthEvent.fromJson(Map<String, dynamic> json) => BeeHealthEvent(
    id: json['id'] as String? ?? '',
    hiveId: json['hiveId'] as String? ?? '',
    checkedAt:
        DateTime.tryParse(json['checkedAt'] as String? ?? '') ?? DateTime.now(),
    conditionId: json['conditionId'] as String? ?? 'Unknown',
    answers: Map<String, int>.from(
      (json['answers'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? -1),
          ) ??
          {},
    ),
    questionsAsked: (json['questionsAsked'] as num?)?.toInt() ?? 0,
    note: json['note'] as String?,
  );
}

class TreatmentRecord {
  const TreatmentRecord({
    required this.id,
    required this.hiveId,
    required this.eventId,
    required this.startedAt,
    required this.treatment,
    this.status = TreatmentStatus.active,
    this.note,
    this.updatedAt,
  });
  final String id;
  final String hiveId;
  final String eventId;
  final DateTime startedAt;
  final String treatment;
  final TreatmentStatus status;
  final String? note;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'hiveId': hiveId,
    'eventId': eventId,
    'startedAt': startedAt.toIso8601String(),
    'treatment': treatment,
    'status': status.name,
    'note': note,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory TreatmentRecord.fromJson(Map<String, dynamic> json) =>
      TreatmentRecord(
        id: json['id'] as String? ?? '',
        hiveId: json['hiveId'] as String? ?? '',
        eventId: json['eventId'] as String? ?? '',
        startedAt:
            DateTime.tryParse(json['startedAt'] as String? ?? '') ??
            DateTime.now(),
        treatment: json['treatment'] as String? ?? '',
        status: TreatmentStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => TreatmentStatus.active,
        ),
        note: json['note'] as String?,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String)
            : null,
      );

  TreatmentRecord copyWith({TreatmentStatus? status, String? note}) =>
      TreatmentRecord(
        id: id,
        hiveId: hiveId,
        eventId: eventId,
        startedAt: startedAt,
        treatment: treatment,
        status: status ?? this.status,
        note: note ?? this.note,
        updatedAt: DateTime.now(),
      );
}

enum TreatmentStatus { active, completed }

class BeeHealthFollowUp {
  const BeeHealthFollowUp({
    required this.id,
    required this.hiveId,
    required this.eventId,
    required this.dueAt,
    required this.note,
    this.status = FollowUpStatus.pending,
    this.createdAt,
  });
  final String id;
  final String hiveId;
  final String eventId;
  final DateTime dueAt;
  final String note;
  final FollowUpStatus status;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'hiveId': hiveId,
    'eventId': eventId,
    'dueAt': dueAt.toIso8601String(),
    'note': note,
    'status': status.name,
    'createdAt': (createdAt ?? dueAt).toIso8601String(),
  };

  factory BeeHealthFollowUp.fromJson(Map<String, dynamic> json) =>
      BeeHealthFollowUp(
        id: json['id'] as String? ?? '',
        hiveId: json['hiveId'] as String? ?? '',
        eventId: json['eventId'] as String? ?? '',
        dueAt:
            DateTime.tryParse(json['dueAt'] as String? ?? '') ?? DateTime.now(),
        note: json['note'] as String? ?? '',
        status: FollowUpStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => FollowUpStatus.pending,
        ),
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );

  BeeHealthFollowUp copyWith({FollowUpStatus? status, DateTime? doneAt}) =>
      BeeHealthFollowUp(
        id: id,
        hiveId: hiveId,
        eventId: eventId,
        dueAt: dueAt,
        note: note,
        status: status ?? this.status,
        createdAt: createdAt ?? doneAt,
      );
}

enum FollowUpStatus { pending, done }
