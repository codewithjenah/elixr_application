import '../../data/models/leaderboard_entry.dart';
import '../../data/models/leaderboard_period.dart';
import '../../core/utils/user_name.dart';

typedef LeaderboardPeriodMetrics = ({
  int xp,
  int sessionsCompleted,
  double averageScore,
  int bestScore,
});

abstract final class LeaderboardPresentation {
  static String periodLabel(LeaderboardPeriod period) {
    return period.selectorLabel;
  }

  static String periodSubtitle(LeaderboardPeriod period) {
    return period.subtitle;
  }

  static String periodXpHeading(LeaderboardPeriod period) {
    return period.xpHeading;
  }

  static String periodTopThreeHeading(LeaderboardPeriod period) {
    return switch (period) {
      LeaderboardPeriod.today => "Today's top 3",
      LeaderboardPeriod.thisMonth => "This month's top 3",
      LeaderboardPeriod.allTime => 'All-time top 3',
    };
  }

  /// Profile statistics are lifetime aggregates. Carry a preloaded rank only
  /// when it was produced by the all-time ordering; other periods must let the
  /// profile controller compute the user's lifetime rank instead.
  static int? profileRankForNavigation({
    required LeaderboardPeriod period,
    required int selectedPeriodRank,
  }) {
    return period == LeaderboardPeriod.allTime ? selectedPeriodRank : null;
  }

  static LeaderboardPeriodMetrics metricsFor(
    LeaderboardEntry entry,
    LeaderboardPeriod period,
  ) {
    return (
      xp: entry.xpFor(period),
      sessionsCompleted: entry.sessionsCompletedFor(period),
      averageScore: entry.averageScoreFor(period),
      bestScore: entry.bestScoreFor(period),
    );
  }

  static List<LeaderboardEntry> podiumOf(List<LeaderboardEntry> entries) {
    if (entries.isEmpty) return const [];
    return entries.take(3).toList(growable: false);
  }

  static List<({int rank, LeaderboardEntry entry})> podiumDisplayOrder(
    List<LeaderboardEntry> podium,
  ) {
    if (podium.length != 3) {
      return [
        for (var i = 0; i < podium.length; i++) (rank: i + 1, entry: podium[i]),
      ];
    }
    return [
      (rank: 2, entry: podium[1]),
      (rank: 1, entry: podium[0]),
      (rank: 3, entry: podium[2]),
    ];
  }

  static List<({int rank, LeaderboardEntry entry})> rankedRowsOf(
    List<LeaderboardEntry> entries,
  ) {
    if (entries.length < 4) return const [];
    return [
      for (var i = 3; i < entries.length; i++) (rank: i + 1, entry: entries[i]),
    ];
  }

  static String initialsFor(String displayName) => userInitials(displayName);

  /// Resolves the avatar URL for a leaderboard row, falling back to the
  /// authenticated user's profile URL for their own row while Firestore
  /// backfill is still in flight.
  static String? profilePictureUrlFor({
    required LeaderboardEntry entry,
    required bool isCurrentUser,
    String? currentUserProfilePictureUrl,
  }) {
    if (isCurrentUser) return currentUserProfilePictureUrl?.trim();
    return entry.profilePictureUrl?.trim();
  }
}
