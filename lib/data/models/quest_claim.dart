/// Idempotent, replay-proof quest-claim marker. Immutable after creation —
/// `firestore.rules` disallows `update`/`delete` entirely on
/// `daily_quest_claims/{claimId}`.
class QuestClaim {
  const QuestClaim({
    required this.userId,
    required this.boardId,
    required this.dayKey,
    required this.dayStart,
    required this.questId,
    required this.xpAwarded,
  });

  final String userId;
  final String boardId;
  final String dayKey;
  final DateTime dayStart;
  final String questId;
  final int xpAwarded;

  static String documentId(String userId, String dayKey, String questId) =>
      '${userId}_${dayKey}_$questId';

  String get id => documentId(userId, dayKey, questId);

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'board_id': boardId,
      'day_key': dayKey,
      'day_start': dayStart,
      'quest_id': questId,
      'xp_awarded': xpAwarded,
    };
  }
}

/// Pure computation for a quest-claim leaderboard update. Mirrors
/// `LeaderboardAwardPlan` (session awards): no Firestore I/O, fully unit
/// testable. Preserves every session aggregate untouched and only adds
/// [xpAwarded] to `quest_xp`/`total_xp`.
class QuestAwardPlan {
  const QuestAwardPlan._({
    required this.alreadyClaimed,
    required this.totalXp,
    required this.questXp,
    required this.sessionsCompleted,
    required this.scoreSum,
    required this.averageScore,
    required this.bestScore,
    required this.lastAwardedSessionId,
    required this.lastSessionAt,
  });

  const QuestAwardPlan.alreadyClaimed()
    : alreadyClaimed = true,
      totalXp = 0,
      questXp = 0,
      sessionsCompleted = 0,
      scoreSum = 0,
      averageScore = 0,
      bestScore = 0,
      lastAwardedSessionId = null,
      lastSessionAt = null;

  final bool alreadyClaimed;
  final int totalXp;
  final int questXp;
  final int sessionsCompleted;
  final double scoreSum;
  final double averageScore;
  final int bestScore;
  final String? lastAwardedSessionId;
  final Object? lastSessionAt;

  /// Builds the next leaderboard aggregate from an optional existing map.
  /// [existing] uses snake_case Firestore field names when present.
  factory QuestAwardPlan.fromExisting({
    required bool claimExists,
    required Map<String, dynamic>? existing,
    required int xpAwarded,
  }) {
    if (claimExists) {
      return const QuestAwardPlan.alreadyClaimed();
    }

    final prevSessions = _readInt(existing?['sessions_completed']) ?? 0;
    final prevXp = _readInt(existing?['total_xp']) ?? 0;
    final prevQuestXp = _readInt(existing?['quest_xp']) ?? 0;
    final prevSum = _readDouble(existing?['score_sum']) ?? 0;
    final prevAverage = _readDouble(existing?['average_score']) ?? 0;
    final prevBest = _readInt(existing?['best_score']) ?? 0;

    return QuestAwardPlan._(
      alreadyClaimed: false,
      totalXp: prevXp + xpAwarded,
      questXp: prevQuestXp + xpAwarded,
      sessionsCompleted: prevSessions,
      scoreSum: prevSum,
      averageScore: prevAverage,
      bestScore: prevBest,
      lastAwardedSessionId: existing?['last_awarded_session_id'] as String?,
      lastSessionAt: existing?['last_session_at'],
    );
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static double? _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return null;
  }
}

/// Typed outcome of [GamificationRepository.claimQuest]. Expected flows
/// (including "not yet completed" and "already claimed") are returned as
/// values, not thrown — only genuinely unexpected Firestore errors
/// (permission-denied from a rules bug, network failure) propagate as
/// exceptions.
enum QuestClaimStatus {
  claimed,
  alreadyClaimed,
  questNotCompleted,
  boardMissing,
  boardExpired,
  leaderboardMissing,
  invalidQuest,
}

class QuestClaimResult {
  const QuestClaimResult._(this.status, {this.xpAwarded = 0});

  final QuestClaimStatus status;
  final int xpAwarded;

  const QuestClaimResult.claimed(int xp)
    : this._(QuestClaimStatus.claimed, xpAwarded: xp);
  const QuestClaimResult.alreadyClaimed()
    : this._(QuestClaimStatus.alreadyClaimed);
  const QuestClaimResult.questNotCompleted()
    : this._(QuestClaimStatus.questNotCompleted);
  const QuestClaimResult.boardMissing() : this._(QuestClaimStatus.boardMissing);
  const QuestClaimResult.boardExpired() : this._(QuestClaimStatus.boardExpired);
  const QuestClaimResult.leaderboardMissing()
    : this._(QuestClaimStatus.leaderboardMissing);
  const QuestClaimResult.invalidQuest() : this._(QuestClaimStatus.invalidQuest);
}
