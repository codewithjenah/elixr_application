import '../../core/constants/gamification_rules.dart';
import 'leaderboard_period.dart';

/// Public aggregate ranking row. May include a Cloud Storage download URL for
/// the player's avatar. Never includes email, storage object paths, or local
/// filesystem paths.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.totalXp,
    required this.sessionsCompleted,
    required this.scoreSum,
    required this.averageScore,
    required this.bestScore,
    this.questXp = 0,
    this.dailyKey,
    this.dailyXp = 0,
    this.dailySessionsCompleted = 0,
    this.dailyScoreSum = 0,
    this.dailyAverageScore = 0,
    this.dailyBestScore = 0,
    this.monthlyKey,
    this.monthlyXp = 0,
    this.monthlySessionsCompleted = 0,
    this.monthlyScoreSum = 0,
    this.monthlyAverageScore = 0,
    this.monthlyBestScore = 0,
    this.profilePictureUrl,
    this.equippedBorderId,
    this.lastSessionAt,
    this.updatedAt,
  });

  final String userId;
  final String displayName;
  final int totalXp;
  final int sessionsCompleted;
  final double scoreSum;
  final double averageScore;
  final int bestScore;

  /// Cumulative XP awarded from daily-quest claims. Defaults to `0` both
  /// here and in [tryFromMap] so legacy leaderboard documents created before
  /// Phase 1 (and any direct construction that omits it) behave identically
  /// to a document with `quest_xp: 0`. `totalXp` is always the authoritative
  /// combined value (`sessionsCompleted * 25 + questXp`).
  final int questXp;

  /// Optional latest Manila-day aggregate. Legacy documents omit this block.
  final String? dailyKey;
  final int dailyXp;
  final int dailySessionsCompleted;
  final double dailyScoreSum;
  final double dailyAverageScore;
  final int dailyBestScore;

  /// Optional latest Manila-month aggregate. Legacy documents omit this block.
  final String? monthlyKey;
  final int monthlyXp;
  final int monthlySessionsCompleted;
  final double monthlyScoreSum;
  final double monthlyAverageScore;
  final int monthlyBestScore;

  /// HTTPS download URL mirrored from the owner's public profile metadata.
  final String? profilePictureUrl;

  /// Public equipped cosmetic border id from the profile-border catalog.
  /// Missing or empty Firestore values parse as null (no equipped border).
  /// Never stored on `users` or `user_cosmetics` — this field is the public
  /// source of truth for avatar chrome.
  final String? equippedBorderId;

  final String? lastSessionAt;
  final String? updatedAt;

  int get level => GamificationRules.levelForXp(totalXp);

  int get xpIntoLevel => GamificationRules.xpIntoLevel(totalXp);

  LeaderboardMetrics metricsFor(LeaderboardPeriod period) => LeaderboardMetrics(
    xp: xpFor(period),
    sessionsCompleted: sessionsCompletedFor(period),
    scoreSum: scoreSumFor(period),
    averageScore: averageScoreFor(period),
    bestScore: bestScoreFor(period),
  );

  int xpFor(LeaderboardPeriod period) => switch (period) {
    LeaderboardPeriod.today => dailyXp,
    LeaderboardPeriod.thisMonth => monthlyXp,
    LeaderboardPeriod.allTime => totalXp,
  };

  int sessionsCompletedFor(LeaderboardPeriod period) => switch (period) {
    LeaderboardPeriod.today => dailySessionsCompleted,
    LeaderboardPeriod.thisMonth => monthlySessionsCompleted,
    LeaderboardPeriod.allTime => sessionsCompleted,
  };

  double scoreSumFor(LeaderboardPeriod period) => switch (period) {
    LeaderboardPeriod.today => dailyScoreSum,
    LeaderboardPeriod.thisMonth => monthlyScoreSum,
    LeaderboardPeriod.allTime => scoreSum,
  };

  double averageScoreFor(LeaderboardPeriod period) => switch (period) {
    LeaderboardPeriod.today => dailyAverageScore,
    LeaderboardPeriod.thisMonth => monthlyAverageScore,
    LeaderboardPeriod.allTime => averageScore,
  };

  int bestScoreFor(LeaderboardPeriod period) => switch (period) {
    LeaderboardPeriod.today => dailyBestScore,
    LeaderboardPeriod.thisMonth => monthlyBestScore,
    LeaderboardPeriod.allTime => bestScore,
  };

  /// Parses a Firestore map. Returns null when identity fields are unusable.
  static LeaderboardEntry? tryFromMap(Map<String, dynamic> map, {String? id}) {
    final userId = _readString(map['user_id']) ?? id;
    if (userId == null || userId.isEmpty) return null;

    final displayName = _readString(map['display_name'])?.trim();
    if (displayName == null || displayName.isEmpty) return null;

    final totalXp = _readInt(map['total_xp']) ?? 0;
    final sessionsCompleted = _readInt(map['sessions_completed']) ?? 0;
    final scoreSum = _readDouble(map['score_sum']) ?? 0;
    final averageScore = _readDouble(map['average_score']) ?? 0;
    final bestScore = _readInt(map['best_score']) ?? 0;
    final questXp = _readInt(map['quest_xp']) ?? 0;
    final dailyKey = _readPeriodKey(map['daily_key'], LeaderboardPeriod.today);
    final dailyXp = _readInt(map['daily_xp']) ?? 0;
    final dailySessionsCompleted =
        _readInt(map['daily_sessions_completed']) ?? 0;
    final dailyScoreSum = _readDouble(map['daily_score_sum']) ?? 0;
    final dailyAverageScore = _readDouble(map['daily_average_score']) ?? 0;
    final dailyBestScore = _readInt(map['daily_best_score']) ?? 0;
    final monthlyKey = _readPeriodKey(
      map['monthly_key'],
      LeaderboardPeriod.thisMonth,
    );
    final monthlyXp = _readInt(map['monthly_xp']) ?? 0;
    final monthlySessionsCompleted =
        _readInt(map['monthly_sessions_completed']) ?? 0;
    final monthlyScoreSum = _readDouble(map['monthly_score_sum']) ?? 0;
    final monthlyAverageScore = _readDouble(map['monthly_average_score']) ?? 0;
    final monthlyBestScore = _readInt(map['monthly_best_score']) ?? 0;

    return LeaderboardEntry(
      userId: userId,
      displayName: displayName,
      totalXp: totalXp < 0 ? 0 : totalXp,
      sessionsCompleted: sessionsCompleted < 0 ? 0 : sessionsCompleted,
      scoreSum: scoreSum < 0 ? 0 : scoreSum,
      averageScore: averageScore < 0 ? 0 : averageScore,
      bestScore: bestScore < 0 ? 0 : bestScore,
      questXp: questXp < 0 ? 0 : questXp,
      dailyKey: dailyKey,
      dailyXp: dailyXp < 0 ? 0 : dailyXp,
      dailySessionsCompleted: dailySessionsCompleted < 0
          ? 0
          : dailySessionsCompleted,
      dailyScoreSum: dailyScoreSum < 0 ? 0 : dailyScoreSum,
      dailyAverageScore: dailyAverageScore < 0 ? 0 : dailyAverageScore,
      dailyBestScore: dailyBestScore < 0 ? 0 : dailyBestScore,
      monthlyKey: monthlyKey,
      monthlyXp: monthlyXp < 0 ? 0 : monthlyXp,
      monthlySessionsCompleted: monthlySessionsCompleted < 0
          ? 0
          : monthlySessionsCompleted,
      monthlyScoreSum: monthlyScoreSum < 0 ? 0 : monthlyScoreSum,
      monthlyAverageScore: monthlyAverageScore < 0 ? 0 : monthlyAverageScore,
      monthlyBestScore: monthlyBestScore < 0 ? 0 : monthlyBestScore,
      profilePictureUrl: _readProfilePictureUrl(map['profile_picture_url']),
      equippedBorderId: _readEquippedBorderId(map['equipped_border_id']),
      lastSessionAt: _readTimestampString(map['last_session_at']),
      updatedAt: _readTimestampString(map['updated_at']),
    );
  }

  static String? _readProfilePictureUrl(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _readEquippedBorderId(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _readString(dynamic value) {
    if (value is String) return value;
    return null;
  }

  static String? _readPeriodKey(dynamic value, LeaderboardPeriod period) {
    if (value is! String || !period.isValidKey(value)) return null;
    return value;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is num) return value.toInt();
    return null;
  }

  static double? _readDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return null;
  }

  static String? _readTimestampString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    // Timestamp-like objects expose toDate() in cloud_firestore.
    try {
      final toDate = (value as dynamic).toDate;
      if (toDate is Function) {
        final date = toDate() as DateTime?;
        return date?.toIso8601String();
      }
    } catch (_) {
      // Fall through for plain maps in unit tests.
    }
    return null;
  }
}
