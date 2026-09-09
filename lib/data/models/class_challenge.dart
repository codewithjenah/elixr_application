import 'package:cloud_firestore/cloud_firestore.dart';

import 'training_prop.dart';

enum ClassChallengeStatus { upcoming, active, ended, archived }

/// A classroom-scoped competitive run using ELIXR's official rubric scoring.
class ClassChallenge {
  const ClassChallenge({
    required this.id,
    required this.groupId,
    required this.teacherId,
    required this.teacherDisplayName,
    required this.title,
    required this.description,
    required this.movementName,
    required this.difficulty,
    required this.prop,
    required this.startAt,
    required this.deadline,
    this.attemptLimit,
    this.targetScore,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
    this.completedCount = 0,
    this.topScore,
  });

  static const maxTitleLength = 80;
  static const maxDescriptionLength = 500;

  final String id;
  final String groupId;
  final String teacherId;
  final String teacherDisplayName;
  final String title;
  final String description;
  final String movementName;
  final String difficulty;
  final TrainingProp prop;
  final DateTime startAt;
  final DateTime deadline;
  final int? attemptLimit;
  final int? targetScore;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int completedCount;
  final int? topScore;

  ClassChallengeStatus statusAt([DateTime? value]) {
    if (archivedAt != null) return ClassChallengeStatus.archived;
    final now = (value ?? DateTime.now()).toUtc();
    if (now.isBefore(startAt.toUtc())) return ClassChallengeStatus.upcoming;
    if (!now.isBefore(deadline.toUtc())) return ClassChallengeStatus.ended;
    return ClassChallengeStatus.active;
  }

  bool canStartAt(DateTime value) =>
      statusAt(value) == ClassChallengeStatus.active;

  Map<String, dynamic> toFunctionPayload() => {
    'group_id': groupId,
    'title': title.trim(),
    'description': description.trim(),
    'movement_name': movementName,
    'difficulty': difficulty,
    'prop_type': prop.protocolValue,
    'start_at': startAt.toUtc().toIso8601String(),
    'deadline': deadline.toUtc().toIso8601String(),
    if (attemptLimit != null) 'attempt_limit': attemptLimit,
    if (targetScore != null) 'target_score': targetScore,
  };

  static ClassChallenge? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final startAt = _date(map['start_at']);
    final deadline = _date(map['deadline']);
    final prop = TrainingProp.tryParseStrict(map['prop_type']);
    if (startAt == null ||
        deadline == null ||
        prop == null ||
        !deadline.isAfter(startAt) ||
        map['group_id'] is! String ||
        map['teacher_id'] is! String ||
        map['teacher_display_name'] is! String ||
        map['title'] is! String ||
        map['description'] is! String ||
        map['movement_name'] is! String ||
        map['difficulty'] is! String) {
      return null;
    }
    final attemptLimit = (map['attempt_limit'] as num?)?.toInt();
    final targetScore = (map['target_score'] as num?)?.toInt();
    if ((attemptLimit != null && (attemptLimit < 1 || attemptLimit > 20)) ||
        (targetScore != null && (targetScore < 0 || targetScore > 12))) {
      return null;
    }
    return ClassChallenge(
      id: id,
      groupId: map['group_id'] as String,
      teacherId: map['teacher_id'] as String,
      teacherDisplayName: map['teacher_display_name'] as String,
      title: map['title'] as String,
      description: map['description'] as String,
      movementName: map['movement_name'] as String,
      difficulty: map['difficulty'] as String,
      prop: prop,
      startAt: startAt,
      deadline: deadline,
      attemptLimit: attemptLimit,
      targetScore: targetScore,
      archivedAt: _date(map['archived_at']),
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
      completedCount: (map['completed_count'] as num?)?.toInt() ?? 0,
      topScore: (map['top_score'] as num?)?.toInt(),
    );
  }
}

class ClassChallengeAttempt {
  const ClassChallengeAttempt({
    required this.id,
    required this.challengeId,
    required this.groupId,
    required this.teacherId,
    required this.traineeId,
    required this.attemptNumber,
    required this.status,
    this.sessionId,
    this.score,
    this.startedAt,
    this.completedAt,
  });

  final String id;
  final String challengeId;
  final String groupId;
  final String teacherId;
  final String traineeId;
  final int attemptNumber;
  final String status;
  final String? sessionId;
  final int? score;
  final DateTime? startedAt;
  final DateTime? completedAt;

  static ClassChallengeAttempt? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final attemptNumber = (map['attempt_number'] as num?)?.toInt();
    if (map['challenge_id'] is! String ||
        map['group_id'] is! String ||
        map['teacher_id'] is! String ||
        map['trainee_id'] is! String ||
        map['status'] is! String ||
        attemptNumber == null ||
        attemptNumber < 1) {
      return null;
    }
    return ClassChallengeAttempt(
      id: id,
      challengeId: map['challenge_id'] as String,
      groupId: map['group_id'] as String,
      teacherId: map['teacher_id'] as String,
      traineeId: map['trainee_id'] as String,
      attemptNumber: attemptNumber,
      status: map['status'] as String,
      sessionId: map['session_id'] as String?,
      score: (map['score'] as num?)?.toInt(),
      startedAt: _date(map['started_at']),
      completedAt: _date(map['completed_at']),
    );
  }
}

class ClassChallengeParticipant {
  const ClassChallengeParticipant({
    required this.challengeId,
    required this.traineeId,
    required this.attemptsStarted,
    this.activeAttemptId,
  });

  final String challengeId;
  final String traineeId;
  final int attemptsStarted;
  final String? activeAttemptId;

  int? attemptsRemaining(int? limit) =>
      limit == null ? null : (limit - attemptsStarted).clamp(0, limit);

  static ClassChallengeParticipant? tryFromMap(Map<String, dynamic> map) {
    final attempts = (map['attempts_started'] as num?)?.toInt();
    if (map['challenge_id'] is! String ||
        map['trainee_id'] is! String ||
        attempts == null ||
        attempts < 0) {
      return null;
    }
    return ClassChallengeParticipant(
      challengeId: map['challenge_id'] as String,
      traineeId: map['trainee_id'] as String,
      attemptsStarted: attempts,
      activeAttemptId: map['active_attempt_id'] as String?,
    );
  }
}

class ClassChallengeLeaderboardEntry {
  const ClassChallengeLeaderboardEntry({
    required this.challengeId,
    required this.groupId,
    required this.traineeId,
    required this.displayName,
    required this.score,
    required this.bestAttemptNumber,
    required this.bestAchievedAt,
    required this.sessionId,
    this.profilePictureUrl,
  });

  final String challengeId;
  final String groupId;
  final String traineeId;
  final String displayName;
  final String? profilePictureUrl;
  final int score;
  final int bestAttemptNumber;
  final DateTime bestAchievedAt;
  final String sessionId;

  static ClassChallengeLeaderboardEntry? tryFromMap(
    Map<String, dynamic> map,
  ) {
    final score = (map['score'] as num?)?.toInt();
    final attempt = (map['best_attempt_number'] as num?)?.toInt();
    final achievedAt = _date(map['best_achieved_at']);
    if (map['challenge_id'] is! String ||
        map['group_id'] is! String ||
        map['trainee_id'] is! String ||
        map['display_name'] is! String ||
        map['session_id'] is! String ||
        score == null ||
        score < 0 ||
        score > 12 ||
        attempt == null ||
        attempt < 1 ||
        achievedAt == null) {
      return null;
    }
    return ClassChallengeLeaderboardEntry(
      challengeId: map['challenge_id'] as String,
      groupId: map['group_id'] as String,
      traineeId: map['trainee_id'] as String,
      displayName: map['display_name'] as String,
      profilePictureUrl: map['profile_picture_url'] as String?,
      score: score,
      bestAttemptNumber: attempt,
      bestAchievedAt: achievedAt,
      sessionId: map['session_id'] as String,
    );
  }
}

List<ClassChallengeLeaderboardEntry> rankClassChallengeEntries(
  Iterable<ClassChallengeLeaderboardEntry> entries,
) {
  final bestByTrainee = <String, ClassChallengeLeaderboardEntry>{};
  for (final entry in entries) {
    final current = bestByTrainee[entry.traineeId];
    if (current == null ||
        entry.score > current.score ||
        (entry.score == current.score &&
            entry.bestAchievedAt.isBefore(current.bestAchievedAt))) {
      bestByTrainee[entry.traineeId] = entry;
    }
  }
  final ranked = bestByTrainee.values.toList()
    ..sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final achieved = a.bestAchievedAt.compareTo(b.bestAchievedAt);
      if (achieved != 0) return achieved;
      return a.traineeId.compareTo(b.traineeId);
    });
  return List.unmodifiable(ranked);
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate().toUtc();
  if (value is DateTime) return value.toUtc();
  if (value is String) return DateTime.tryParse(value)?.toUtc();
  return null;
}
