import 'training_prop.dart';

/// Sanitized practice-history projection at
/// `public_profiles/{userId}/sessions/{sessionId}`.
class PublicProfileSession {
  const PublicProfileSession({
    required this.sessionId,
    required this.userId,
    required this.movementName,
    required this.difficulty,
    required this.score,
    required this.durationSeconds,
    required this.propType,
    this.createdAt,
  });

  final String sessionId;
  final String userId;
  final String movementName;
  final String difficulty;
  final int score;
  final int durationSeconds;
  final TrainingProp propType;
  final String? createdAt;

  static PublicProfileSession? tryFromMap(
    Map<String, dynamic> map, {
    String? id,
  }) {
    final sessionId = _readString(map['session_id']) ?? id;
    final userId = _readString(map['user_id']);
    final movementName = _readString(map['movement_name']);
    final difficulty = _readString(map['difficulty']);
    final score = _readInt(map['score']);
    final durationSeconds = _readInt(map['duration_seconds']);

    if (sessionId == null ||
        sessionId.isEmpty ||
        userId == null ||
        userId.isEmpty ||
        movementName == null ||
        movementName.isEmpty ||
        difficulty == null ||
        difficulty.isEmpty ||
        score == null ||
        durationSeconds == null) {
      return null;
    }

    return PublicProfileSession(
      sessionId: sessionId,
      userId: userId,
      movementName: movementName,
      difficulty: difficulty,
      score: score,
      durationSeconds: durationSeconds < 0 ? 0 : durationSeconds,
      propType: TrainingProp.fromProtocolValue(map['prop_type']),
      createdAt: _readTimestampString(map['created_at']),
    );
  }

  static String? _readString(dynamic value) {
    if (value is String) return value;
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

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
