import 'rubric_assessment.dart';
import 'training_prop.dart';

class Session {
  const Session({
    this.id,
    required this.userId,
    required this.movementName,
    required this.difficulty,
    this.legacyScore,
    this.rubric,
    this.assessmentVersion = 1,
    required this.durationSeconds,
    this.createdAt,
    this.propType = TrainingProp.bottle,
    this.evidenceStoragePath,
    this.evidenceKind,
    this.evidenceSizeBytes,
  });

  final String? id;
  final String userId;
  final String movementName;
  final String difficulty;

  /// Legacy Assessment V1 percentage (0..100). Null for Assessment V2 sessions.
  final int? legacyScore;

  /// Assessment V2 rubric. Null for legacy sessions.
  final RubricAssessment? rubric;

  /// 1 = legacy percentage, 2 = rubric.
  final int assessmentVersion;

  final int durationSeconds;
  final String? createdAt;
  final TrainingProp propType;
  final String? evidenceStoragePath;
  final String? evidenceKind;
  final int? evidenceSizeBytes;

  bool get isRubricAssessed => assessmentVersion == 2 && rubric != null;

  /// Convenience: rubric total for V2, else null (never mix with legacyScore).
  int? get rubricTotal => rubric?.total;

  PerformanceLevel? get performanceLevel => rubric?.performanceLevel;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'user_id': userId,
      'movement_name': movementName,
      'difficulty': difficulty,
      'duration_seconds': durationSeconds,
      'created_at': createdAt,
      'prop_type': propType.protocolValue,
      'assessment_version': assessmentVersion,
      if (evidenceStoragePath != null)
        'evidence_storage_path': evidenceStoragePath,
      if (evidenceKind != null) 'evidence_kind': evidenceKind,
      if (evidenceSizeBytes != null) 'evidence_size_bytes': evidenceSizeBytes,
    };
    if (isRubricAssessed && rubric != null) {
      map.addAll(rubric!.toFirestoreFields());
    } else if (legacyScore != null) {
      map['score'] = legacyScore;
    }
    return map;
  }

  factory Session.fromMap(Map<String, dynamic> map) {
    final rubric = RubricAssessment.tryFromFirestore(map);
    final versionRaw = map['assessment_version'];
    final version = versionRaw is num
        ? versionRaw.toInt()
        : (rubric != null ? 2 : 1);

    int? legacyScore;
    final scoreRaw = map['score'];
    if (scoreRaw is num) {
      legacyScore = scoreRaw.toInt();
    }

    // Prefer V2 when rubric parses successfully.
    if (rubric != null) {
      return Session(
        id: map['id'] as String?,
        userId: map['user_id'] as String,
        movementName: map['movement_name'] as String,
        difficulty: map['difficulty'] as String,
        rubric: rubric,
        assessmentVersion: 2,
        durationSeconds: (map['duration_seconds'] as num).toInt(),
        createdAt: map['created_at'] as String?,
        propType: TrainingProp.fromProtocolValue(map['prop_type']),
        evidenceStoragePath: map['evidence_storage_path'] as String?,
        evidenceKind: map['evidence_kind'] as String?,
        evidenceSizeBytes: (map['evidence_size_bytes'] as num?)?.toInt(),
      );
    }

    return Session(
      id: map['id'] as String?,
      userId: map['user_id'] as String,
      movementName: map['movement_name'] as String,
      difficulty: map['difficulty'] as String,
      legacyScore: legacyScore,
      assessmentVersion: version == 2 ? 1 : version, // incomplete V2 → legacy
      durationSeconds: (map['duration_seconds'] as num).toInt(),
      createdAt: map['created_at'] as String?,
      propType: TrainingProp.fromProtocolValue(map['prop_type']),
      evidenceStoragePath: map['evidence_storage_path'] as String?,
      evidenceKind: map['evidence_kind'] as String?,
      evidenceSizeBytes: (map['evidence_size_bytes'] as num?)?.toInt(),
    );
  }
}
