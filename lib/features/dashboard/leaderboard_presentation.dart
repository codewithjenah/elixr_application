import '../../data/models/leaderboard_entry.dart';

/// Pure ranking presentation helpers for the dashboard leaderboard.
abstract final class LeaderboardPresentation {
  /// Top three entries in podium order (1st, 2nd, 3rd).
  static List<LeaderboardEntry> podiumOf(List<LeaderboardEntry> topPlayers) {
    if (topPlayers.isEmpty) return const [];
    return topPlayers.take(3).toList(growable: false);
  }

  /// Ranked rows for places 4–10 as (rank, entry).
  static List<({int rank, LeaderboardEntry entry})> compactRowsOf(
    List<LeaderboardEntry> topPlayers,
  ) {
    if (topPlayers.length < 4) return const [];
    final rows = <({int rank, LeaderboardEntry entry})>[];
    for (var i = 3; i < topPlayers.length && i < 10; i++) {
      rows.add((rank: i + 1, entry: topPlayers[i]));
    }
    return rows;
  }

  static bool containsUser(List<LeaderboardEntry> topPlayers, String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return topPlayers.any((entry) => entry.userId == userId);
  }

  /// Standing entry when the signed-in user is not in the Top 10.
  static LeaderboardEntry? standingOutsideTop({
    required List<LeaderboardEntry> topPlayers,
    required String? currentUserId,
    required LeaderboardEntry? currentUserEntry,
  }) {
    if (currentUserId == null || currentUserId.isEmpty) return null;
    if (currentUserEntry == null) return null;
    if (containsUser(topPlayers, currentUserId)) return null;
    return currentUserEntry;
  }

  static String initialsFor(String displayName) {
    final parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
    }
    return ('${parts[0][0]}${parts[1][0]}').toUpperCase();
  }
}
