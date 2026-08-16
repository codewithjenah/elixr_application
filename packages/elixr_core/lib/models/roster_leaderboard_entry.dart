class RosterLeaderboardEntry {
  const RosterLeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.totalXp,
    required this.sessionsCompleted,
    required this.bestScore,
    required this.rosterRank,
    this.profilePictureUrl,
  });

  final String userId;
  final String displayName;
  final int totalXp;
  final int sessionsCompleted;
  final int bestScore;
  final int rosterRank;
  final String? profilePictureUrl;

  RosterLeaderboardEntry withRank(int rank) => RosterLeaderboardEntry(
    userId: userId,
    displayName: displayName,
    totalXp: totalXp,
    sessionsCompleted: sessionsCompleted,
    bestScore: bestScore,
    rosterRank: rank,
    profilePictureUrl: profilePictureUrl,
  );

  static RosterLeaderboardEntry? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
    required String fallbackName,
  }) {
    final userId = _string(map['user_id']) ?? id;
    if (userId.isEmpty) return null;
    return RosterLeaderboardEntry(
      userId: userId,
      displayName: _string(map['display_name']) ?? fallbackName,
      totalXp: _nonNegativeInt(map['total_xp']),
      sessionsCompleted: _nonNegativeInt(map['sessions_completed']),
      bestScore: _nonNegativeInt(map['best_score']),
      rosterRank: 0,
      profilePictureUrl: _string(map['profile_picture_url']),
    );
  }

  static int compare(RosterLeaderboardEntry a, RosterLeaderboardEntry b) {
    final xp = b.totalXp.compareTo(a.totalXp);
    if (xp != 0) return xp;
    final score = b.bestScore.compareTo(a.bestScore);
    if (score != 0) return score;
    return a.userId.compareTo(b.userId);
  }

  static String? _string(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int _nonNegativeInt(Object? value) {
    final number = value is num ? value.toInt() : 0;
    return number < 0 ? 0 : number;
  }
}
