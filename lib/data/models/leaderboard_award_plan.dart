import '../../core/constants/gamification_rules.dart';
import 'leaderboard_period.dart';
import 'leaderboard_period_aggregate.dart';

/// Pure computation for a leaderboard XP award. No Firestore I/O.
class LeaderboardAwardPlan {
  const LeaderboardAwardPlan._({
    required this.alreadyProcessed,
    required this.totalXp,
    required this.questXp,
    required this.sessionsCompleted,
    required this.scoreSum,
    required this.averageScore,
    required this.bestScore,
    required this.daily,
    required this.monthly,
  });

  const LeaderboardAwardPlan.alreadyProcessed()
    : alreadyProcessed = true,
      totalXp = 0,
      questXp = 0,
      sessionsCompleted = 0,
      scoreSum = 0,
      averageScore = 0,
      bestScore = 0,
      daily = const LeaderboardPeriodAggregate(
        period: LeaderboardPeriod.today,
        key: null,
        xp: 0,
        sessionsCompleted: 0,
        scoreSum: 0,
        averageScore: 0,
        bestScore: 0,
      ),
      monthly = const LeaderboardPeriodAggregate(
        period: LeaderboardPeriod.thisMonth,
        key: null,
        xp: 0,
        sessionsCompleted: 0,
        scoreSum: 0,
        averageScore: 0,
        bestScore: 0,
      );

  final bool alreadyProcessed;
  final int totalXp;

  /// Carried through unchanged from the existing document (defaults to 0
  /// for legacy documents) — a session award never touches quest XP.
  final int questXp;
  final int sessionsCompleted;
  final double scoreSum;
  final double averageScore;
  final int bestScore;
  final LeaderboardPeriodAggregate daily;
  final LeaderboardPeriodAggregate monthly;

  Map<String, dynamic> get periodFields => {
    ...daily.toFirestoreFields(),
    ...monthly.toFirestoreFields(),
  };

  /// Builds the next aggregate from an optional existing leaderboard map.
  /// [existing] uses snake_case Firestore field names when present.
  ///
  /// [score] is the legacy Assessment V1 percentage of the awarded session.
  /// Pass `null` for an Assessment V2 (rubric) session: XP, session counts,
  /// and the period XP/session counters still advance, but `score_sum`,
  /// `average_score`, `best_score` and their daily/monthly mirrors are frozen
  /// at their stored values. Rubric totals are 0..12 and must never be mixed
  /// into the 0..100 percentage aggregates those fields represent.
  factory LeaderboardAwardPlan.fromExisting({
    required bool markerExists,
    required Map<String, dynamic>? existing,
    required int? score,
    required DateTime sessionCreatedAtUtc,
  }) {
    if (markerExists) {
      return const LeaderboardAwardPlan.alreadyProcessed();
    }

    final prevSessions = _readInt(existing?['sessions_completed']) ?? 0;
    final prevXp = _readInt(existing?['total_xp']) ?? 0;
    final prevQuestXp = _readInt(existing?['quest_xp']) ?? 0;
    final prevSum = _readDouble(existing?['score_sum']) ?? 0;
    final prevAverage = _readDouble(existing?['average_score']) ?? 0;
    final prevBest = _readInt(existing?['best_score']) ?? 0;

    final sessionsCompleted = prevSessions + 1;
    final totalXp = prevXp + GamificationRules.xpPerSession;
    final scoreSum = score == null ? prevSum : prevSum + score;
    final averageScore = score == null
        ? prevAverage
        : scoreSum / sessionsCompleted;
    final bestScore = score != null && score > prevBest ? score : prevBest;
    final eventDayKey = LeaderboardPeriod.today.keyFor(sessionCreatedAtUtc)!;
    final eventMonthKey = LeaderboardPeriod.thisMonth.keyFor(
      sessionCreatedAtUtc,
    )!;
    final daily =
        LeaderboardPeriodAggregate.fromExisting(
              period: LeaderboardPeriod.today,
              existing: existing,
            )
            .applySession(
              eventKey: eventDayKey,
              xpAwarded: GamificationRules.xpPerSession,
              score: score,
            )
            .aggregate;
    final monthly =
        LeaderboardPeriodAggregate.fromExisting(
              period: LeaderboardPeriod.thisMonth,
              existing: existing,
            )
            .applySession(
              eventKey: eventMonthKey,
              xpAwarded: GamificationRules.xpPerSession,
              score: score,
            )
            .aggregate;

    return LeaderboardAwardPlan._(
      alreadyProcessed: false,
      totalXp: totalXp,
      questXp: prevQuestXp,
      sessionsCompleted: sessionsCompleted,
      scoreSum: scoreSum,
      averageScore: averageScore,
      bestScore: bestScore,
      daily: daily,
      monthly: monthly,
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
