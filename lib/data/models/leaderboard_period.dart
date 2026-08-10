import '../../core/utils/manila_day.dart';

/// Ranking window used by the full leaderboard screen.
enum LeaderboardPeriod {
  today,
  thisMonth,
  allTime;

  String get selectorLabel => switch (this) {
    LeaderboardPeriod.today => 'Today',
    LeaderboardPeriod.thisMonth => 'This month',
    LeaderboardPeriod.allTime => 'All time',
  };

  String get subtitle => switch (this) {
    LeaderboardPeriod.today => 'Rankings based on XP earned today.',
    LeaderboardPeriod.thisMonth => 'Rankings based on XP earned this month.',
    LeaderboardPeriod.allTime => 'All-time rankings by total XP.',
  };

  String get xpHeading => switch (this) {
    LeaderboardPeriod.today => 'XP today',
    LeaderboardPeriod.thisMonth => 'XP this month',
    LeaderboardPeriod.allTime => 'Total XP',
  };

  bool get hasPeriodKey => this != LeaderboardPeriod.allTime;

  String? keyFor(DateTime instantUtc) => switch (this) {
    LeaderboardPeriod.today => ManilaDay.dayKeyFor(instantUtc),
    LeaderboardPeriod.thisMonth => ManilaDay.monthKeyFor(instantUtc),
    LeaderboardPeriod.allTime => null,
  };

  String? get keyField => switch (this) {
    LeaderboardPeriod.today => 'daily_key',
    LeaderboardPeriod.thisMonth => 'monthly_key',
    LeaderboardPeriod.allTime => null,
  };

  String get xpField => switch (this) {
    LeaderboardPeriod.today => 'daily_xp',
    LeaderboardPeriod.thisMonth => 'monthly_xp',
    LeaderboardPeriod.allTime => 'total_xp',
  };

  String get sessionsCompletedField => switch (this) {
    LeaderboardPeriod.today => 'daily_sessions_completed',
    LeaderboardPeriod.thisMonth => 'monthly_sessions_completed',
    LeaderboardPeriod.allTime => 'sessions_completed',
  };

  String get scoreSumField => switch (this) {
    LeaderboardPeriod.today => 'daily_score_sum',
    LeaderboardPeriod.thisMonth => 'monthly_score_sum',
    LeaderboardPeriod.allTime => 'score_sum',
  };

  String get averageScoreField => switch (this) {
    LeaderboardPeriod.today => 'daily_average_score',
    LeaderboardPeriod.thisMonth => 'monthly_average_score',
    LeaderboardPeriod.allTime => 'average_score',
  };

  String get bestScoreField => switch (this) {
    LeaderboardPeriod.today => 'daily_best_score',
    LeaderboardPeriod.thisMonth => 'monthly_best_score',
    LeaderboardPeriod.allTime => 'best_score',
  };

  int? get keyLength => switch (this) {
    LeaderboardPeriod.today => 8,
    LeaderboardPeriod.thisMonth => 6,
    LeaderboardPeriod.allTime => null,
  };

  bool isValidKey(String value) {
    final expectedLength = keyLength;
    if (expectedLength == null || value.length != expectedLength) return false;
    if (!RegExp(r'^\d+$').hasMatch(value)) return false;

    final year = int.parse(value.substring(0, 4));
    final month = int.parse(value.substring(4, 6));
    if (year < 1 || month < 1 || month > 12) return false;
    if (this == LeaderboardPeriod.thisMonth) return true;

    final day = int.parse(value.substring(6, 8));
    if (day < 1 || day > 31) return false;
    final parsed = DateTime.utc(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }
}

/// Selected-period aggregate exposed by [LeaderboardEntry.metricsFor].
class LeaderboardMetrics {
  const LeaderboardMetrics({
    required this.xp,
    required this.sessionsCompleted,
    required this.scoreSum,
    required this.averageScore,
    required this.bestScore,
  });

  final int xp;
  final int sessionsCompleted;
  final double scoreSum;
  final double averageScore;
  final int bestScore;
}
