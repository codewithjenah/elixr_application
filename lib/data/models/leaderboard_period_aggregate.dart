import 'leaderboard_period.dart';

enum LeaderboardPeriodTransitionKind { reset, accumulate, preserve }

/// Result of applying one XP event to a stored period aggregate.
class LeaderboardPeriodTransition {
  const LeaderboardPeriodTransition({
    required this.kind,
    required this.aggregate,
  });

  final LeaderboardPeriodTransitionKind kind;
  final LeaderboardPeriodAggregate aggregate;
}

/// Pure daily/monthly aggregate state used by both session and quest awards.
///
/// Period keys are lexicographically sortable because they are fixed-width
/// `yyyyMMdd`/`yyyyMM` values. An older event deliberately returns the stored
/// aggregate unchanged so delayed synchronization cannot roll a user back.
class LeaderboardPeriodAggregate {
  const LeaderboardPeriodAggregate({
    required this.period,
    required this.key,
    required this.xp,
    required this.sessionsCompleted,
    required this.scoreSum,
    required this.averageScore,
    required this.bestScore,
  }) : assert(period != LeaderboardPeriod.allTime);

  factory LeaderboardPeriodAggregate.fromExisting({
    required LeaderboardPeriod period,
    required Map<String, dynamic>? existing,
  }) {
    if (!period.hasPeriodKey) {
      throw ArgumentError.value(period, 'period', 'must be daily or monthly');
    }

    final rawKey = existing?[period.keyField];
    final key = rawKey is String && period.isValidKey(rawKey) ? rawKey : null;
    return LeaderboardPeriodAggregate(
      period: period,
      key: key,
      xp: _nonNegativeInt(existing?[period.xpField]),
      sessionsCompleted: _nonNegativeInt(
        existing?[period.sessionsCompletedField],
      ),
      scoreSum: _nonNegativeDouble(existing?[period.scoreSumField]),
      averageScore: _nonNegativeDouble(existing?[period.averageScoreField]),
      bestScore: _nonNegativeInt(existing?[period.bestScoreField]),
    );
  }

  final LeaderboardPeriod period;
  final String? key;
  final int xp;
  final int sessionsCompleted;
  final double scoreSum;
  final double averageScore;
  final int bestScore;

  LeaderboardPeriodTransition applySession({
    required String eventKey,
    required int xpAwarded,
    required int score,
  }) {
    if (score < 0) {
      throw ArgumentError.value(score, 'score', 'must be non-negative');
    }
    return _applyEvent(
      eventKey: eventKey,
      xpAwarded: xpAwarded,
      sessionScore: score,
    );
  }

  LeaderboardPeriodTransition applyQuest({
    required String eventKey,
    required int xpAwarded,
  }) {
    return _applyEvent(eventKey: eventKey, xpAwarded: xpAwarded);
  }

  LeaderboardPeriodTransition _applyEvent({
    required String eventKey,
    required int xpAwarded,
    int? sessionScore,
  }) {
    if (!period.isValidKey(eventKey)) {
      throw FormatException('Invalid ${period.name} leaderboard key', eventKey);
    }
    if (xpAwarded < 0) {
      throw ArgumentError.value(xpAwarded, 'xpAwarded', 'must be non-negative');
    }

    final storedKey = key;
    if (storedKey != null && eventKey.compareTo(storedKey) < 0) {
      return LeaderboardPeriodTransition(
        kind: LeaderboardPeriodTransitionKind.preserve,
        aggregate: this,
      );
    }

    final resets = storedKey == null || eventKey.compareTo(storedKey) > 0;
    final baseXp = resets ? 0 : xp;
    final baseSessions = resets ? 0 : sessionsCompleted;
    final baseScoreSum = resets ? 0.0 : scoreSum;
    final baseAverage = resets ? 0.0 : averageScore;
    final baseBest = resets ? 0 : bestScore;

    if (sessionScore == null) {
      return LeaderboardPeriodTransition(
        kind: resets
            ? LeaderboardPeriodTransitionKind.reset
            : LeaderboardPeriodTransitionKind.accumulate,
        aggregate: LeaderboardPeriodAggregate(
          period: period,
          key: eventKey,
          xp: baseXp + xpAwarded,
          sessionsCompleted: baseSessions,
          scoreSum: baseScoreSum,
          averageScore: baseAverage,
          bestScore: baseBest,
        ),
      );
    }

    final nextSessions = baseSessions + 1;
    final nextScoreSum = baseScoreSum + sessionScore;
    return LeaderboardPeriodTransition(
      kind: resets
          ? LeaderboardPeriodTransitionKind.reset
          : LeaderboardPeriodTransitionKind.accumulate,
      aggregate: LeaderboardPeriodAggregate(
        period: period,
        key: eventKey,
        xp: baseXp + xpAwarded,
        sessionsCompleted: nextSessions,
        scoreSum: nextScoreSum,
        averageScore: nextScoreSum / nextSessions,
        bestScore: sessionScore > baseBest ? sessionScore : baseBest,
      ),
    );
  }

  Map<String, dynamic> toFirestoreFields() {
    final resolvedKey = key;
    if (resolvedKey == null) {
      throw StateError('Cannot persist an aggregate without a period key');
    }
    return {
      period.keyField!: resolvedKey,
      period.xpField: xp,
      period.sessionsCompletedField: sessionsCompleted,
      period.scoreSumField: scoreSum,
      period.averageScoreField: averageScore,
      period.bestScoreField: bestScore,
    };
  }

  static int _nonNegativeInt(dynamic value) {
    final parsed = value is num ? value.toInt() : 0;
    return parsed < 0 ? 0 : parsed;
  }

  static double _nonNegativeDouble(dynamic value) {
    final parsed = value is num ? value.toDouble() : 0.0;
    return parsed < 0 ? 0 : parsed;
  }
}
