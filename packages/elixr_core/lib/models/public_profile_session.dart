import 'rubric_assessment.dart';
import 'training_prop.dart';

/// Sanitized practice-history projection at
/// `public_profiles/{userId}/sessions/{sessionId}`.
class PublicProfileSession {
  const PublicProfileSession({
    required this.sessionId,
    required this.userId,
    required this.movementName,
    required this.difficulty,
    this.legacyScore,
    this.rubric,
    this.assessmentVersion = 1,
    required this.durationSeconds,
    required this.propType,
    this.createdAt,
    this.evidenceAvailable,
  });

  final String sessionId;
  final String userId;
  final String movementName;
  final String difficulty;

  /// Legacy Assessment V1 percentage. Null for V2 projections.
  final int? legacyScore;
  final RubricAssessment? rubric;
  final int assessmentVersion;
  final int durationSeconds;
  final TrainingProp propType;
  final String? createdAt;
  final bool? evidenceAvailable;

  bool get isRubricAssessed => assessmentVersion == 2 && rubric != null;

  static PublicProfileSession? tryFromMap(
    Map<String, dynamic> map, {
    String? id,
  }) {
    final sessionId = _readString(map['session_id']) ?? id;
    final userId = _readString(map['user_id']);
    final movementName = _readString(map['movement_name']);
    final difficulty = _readString(map['difficulty']);
    final durationSeconds = _readInt(map['duration_seconds']);

    if (sessionId == null ||
        sessionId.isEmpty ||
        userId == null ||
        userId.isEmpty ||
        movementName == null ||
        movementName.isEmpty ||
        difficulty == null ||
        difficulty.isEmpty ||
        durationSeconds == null ||
        durationSeconds < 0) {
      return null;
    }

    final version = _readInt(map['assessment_version']);
    if (map.containsKey('assessment_version') && version == null) return null;
    final rubric = RubricAssessment.tryFromFirestore(map);
    if (version == 2) {
      if (rubric == null) return null;
      return PublicProfileSession(
        sessionId: sessionId,
        userId: userId,
        movementName: movementName,
        difficulty: difficulty,
        rubric: rubric,
        assessmentVersion: 2,
        durationSeconds: durationSeconds,
        propType: TrainingProp.fromProtocolValue(map['prop_type']),
        createdAt: _readTimestampString(map['created_at']),
        evidenceAvailable: _readOptionalBool(map['evidence_available']),
      );
    }

    if (version != null && version != 1) return null;
    // A malformed explicit V2 payload must never fall back to legacy parsing.
    if (map.containsKey('rubric') ||
        map.containsKey('rubric_total') ||
        map.containsKey('performance_level')) {
      return null;
    }
    final score = _readInt(map['score']);
    if (score == null || score < 0 || score > 100) return null;

    return PublicProfileSession(
      sessionId: sessionId,
      userId: userId,
      movementName: movementName,
      difficulty: difficulty,
      legacyScore: score,
      assessmentVersion: 1,
      durationSeconds: durationSeconds,
      propType: TrainingProp.fromProtocolValue(map['prop_type']),
      createdAt: _readTimestampString(map['created_at']),
      evidenceAvailable: _readOptionalBool(map['evidence_available']),
    );
  }

  static String? _readString(dynamic value) {
    if (value is String) return value;
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }

  static bool? _readOptionalBool(Object? value) => value is bool ? value : null;

  static String? _readTimestampString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    try {
      final toDate = (value as dynamic).toDate;
      if (toDate is Function) {
        final date = toDate() as DateTime?;
        return date?.toIso8601String();
      }
    } catch (_) {}
    return null;
  }
}
