import '../../core/utils/manila_day.dart';
import '../../core/utils/user_name.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/models/leaderboard_period.dart';

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
      LeaderboardPeriod.thisMonth => 'Current Season top 3',
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

  static const _fullMonthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const _shortMonthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const lastActiveRecentlyWindow = Duration(minutes: 10);

  static String headerSubtitle(
    LeaderboardPeriod period, {
    required DateTime nowUtc,
  }) {
    if (period == LeaderboardPeriod.thisMonth) {
      return seasonStatusText(nowUtc: nowUtc);
    }
    return periodSubtitle(period);
  }

  static String seasonName({required DateTime nowUtc}) {
    final key = ManilaDay.monthKeyFor(nowUtc);
    final month = int.parse(key.substring(4, 6));
    return '${_fullMonthNames[month - 1]} Season';
  }

  static DateTime nextSeasonStartUtc(DateTime nowUtc) {
    final key = ManilaDay.monthKeyFor(nowUtc);
    final year = int.parse(key.substring(0, 4));
    final month = int.parse(key.substring(4, 6));
    final nextCivil = month == 12
        ? DateTime.utc(year + 1, 1, 1)
        : DateTime.utc(year, month + 1, 1);
    return nextCivil.subtract(const Duration(hours: 8));
  }

  static String seasonResetText({required DateTime nowUtc}) {
    final remaining = nextSeasonStartUtc(nowUtc).difference(nowUtc.toUtc());
    if (remaining.inDays >= 1) return 'Resets in ${remaining.inDays}d';
    if (remaining.inHours >= 1) return 'Resets in ${remaining.inHours}h';
    final minutes = remaining.inMinutes < 1 ? 1 : remaining.inMinutes;
    return 'Resets in ${minutes}m';
  }

  static String seasonStatusText({required DateTime nowUtc}) {
    return '${seasonName(nowUtc: nowUtc)} • ${seasonResetText(nowUtc: nowUtc)}';
  }

  /// Relative last-active label. Returns null when the timestamp is missing
  /// or in the future so the UI never fabricates an "Online" heartbeat.
  static String? lastActiveStatus({
    required DateTime? lastActiveAt,
    required DateTime nowUtc,
  }) {
    if (lastActiveAt == null) return null;
    final last = lastActiveAt.toUtc();
    final now = nowUtc.toUtc();
    if (last.isAfter(now)) return null;

    final elapsed = now.difference(last);
    if (elapsed < lastActiveRecentlyWindow) return 'Active recently';
    if (elapsed.inMinutes < 60) return 'Last active ${elapsed.inMinutes}m ago';

    final lastDay = ManilaDay.dayKeyFor(last);
    final nowDay = ManilaDay.dayKeyFor(now);
    if (lastDay == nowDay) {
      return 'Last active ${elapsed.inHours}h ago';
    }

    final yesterday = ManilaDay.addCalendarDays(nowDay, -1);
    if (lastDay == yesterday) return 'Last active yesterday';

    final civil = ManilaDay.civilDateFromDayKey(lastDay);
    final monthLabel = _shortMonthNames[civil.month - 1];
    final nowCivil = ManilaDay.civilDateFromDayKey(ManilaDay.dayKeyFor(now));
    if (civil.year == nowCivil.year) {
      return 'Last active $monthLabel ${civil.day}';
    }
    return 'Last active $monthLabel ${civil.day}, ${civil.year}';
  }
}
