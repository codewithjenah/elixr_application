import '../../data/models/leaderboard_entry.dart';

abstract final class LeaderboardPresentation {
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
