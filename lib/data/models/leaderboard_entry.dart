import '../../core/constants/gamification_rules.dart';

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
    this.profilePictureUrl,
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

  /// HTTPS download URL mirrored from the owner's public profile metadata.
  final String? profilePictureUrl;
  final String? lastSessionAt;
  final String? updatedAt;

  int get level => GamificationRules.levelForXp(totalXp);

  int get xpIntoLevel => GamificationRules.xpIntoLevel(totalXp);

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

    return LeaderboardEntry(
      userId: userId,
      displayName: displayName,
      totalXp: totalXp < 0 ? 0 : totalXp,
      sessionsCompleted: sessionsCompleted < 0 ? 0 : sessionsCompleted,
      scoreSum: scoreSum < 0 ? 0 : scoreSum,
      averageScore: averageScore < 0 ? 0 : averageScore,
      bestScore: bestScore < 0 ? 0 : bestScore,
      questXp: questXp < 0 ? 0 : questXp,
      profilePictureUrl: _readProfilePictureUrl(map['profile_picture_url']),
      lastSessionAt: _readTimestampString(map['last_session_at']),
      updatedAt: _readTimestampString(map['updated_at']),
    );
  }

  static String? _readProfilePictureUrl(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _readString(dynamic value) {
    if (value is String) return value;
    return null;
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
