import '../../core/constants/gamification_rules.dart';

/// Pure computation for a leaderboard XP award. No Firestore I/O.
class LeaderboardAwardPlan {
  const LeaderboardAwardPlan._({
    required this.alreadyProcessed,
    required this.totalXp,
    required this.sessionsCompleted,
    required this.scoreSum,
    required this.averageScore,
    required this.bestScore,
  });

  const LeaderboardAwardPlan.alreadyProcessed()
    : alreadyProcessed = true,
      totalXp = 0,
      sessionsCompleted = 0,
      scoreSum = 0,
      averageScore = 0,
      bestScore = 0;

  final bool alreadyProcessed;
  final int totalXp;
  final int sessionsCompleted;
  final double scoreSum;
  final double averageScore;
  final int bestScore;

  /// Builds the next aggregate from an optional existing leaderboard map.
  /// [existing] uses snake_case Firestore field names when present.
  factory LeaderboardAwardPlan.fromExisting({
    required bool markerExists,
    required Map<String, dynamic>? existing,
    required int score,
  }) {
    if (markerExists) {
      return const LeaderboardAwardPlan.alreadyProcessed();
    }

    final prevSessions = _readInt(existing?['sessions_completed']) ?? 0;
    final prevXp = _readInt(existing?['total_xp']) ?? 0;
    final prevSum = _readDouble(existing?['score_sum']) ?? 0;
    final prevBest = _readInt(existing?['best_score']) ?? 0;

    final sessionsCompleted = prevSessions + 1;
    final totalXp = prevXp + GamificationRules.xpPerSession;
    final scoreSum = prevSum + score;
    final bestScore = score > prevBest ? score : prevBest;

    return LeaderboardAwardPlan._(
      alreadyProcessed: false,
      totalXp: totalXp,
      sessionsCompleted: sessionsCompleted,
      scoreSum: scoreSum,
      averageScore: scoreSum / sessionsCompleted,
      bestScore: bestScore,
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

/// Result of per-user automatic leaderboard synchronization.
class LeaderboardSyncResult {
  const LeaderboardSyncResult({
    required this.totalSessionsChecked,
    required this.alreadyProcessed,
    required this.newlyProcessed,
    required this.failures,
    this.publicProfileSynced = false,
  });

  final int totalSessionsChecked;
  final int alreadyProcessed;
  final int newlyProcessed;
  final int failures;
  final bool publicProfileSynced;

  static const empty = LeaderboardSyncResult(
    totalSessionsChecked: 0,
    alreadyProcessed: 0,
    newlyProcessed: 0,
    failures: 0,
  );
}

/// Helpers for selecting which sessions still need awards.
abstract final class LeaderboardSyncPlanner {
  static List<SessionRef> sessionsMissingAwards({
    required List<SessionRef> sessions,
    required Set<String> processedSessionIds,
  }) {
    final missing = sessions
        .where(
          (session) =>
              session.id.isNotEmpty &&
              !processedSessionIds.contains(session.id),
        )
        .toList();
    missing.sort((a, b) {
      final aMs = a.createdAtMs ?? 0;
      final bMs = b.createdAtMs ?? 0;
      final byTime = aMs.compareTo(bMs);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    return missing;
  }
}

/// Lightweight session identity used by sync planning (no private payloads).
class SessionRef {
  const SessionRef({required this.id, required this.userId, this.createdAtMs});

  final String id;
  final String userId;
  final int? createdAtMs;
}
