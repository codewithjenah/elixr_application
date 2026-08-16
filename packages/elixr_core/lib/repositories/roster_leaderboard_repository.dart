import '../models/roster_leaderboard_entry.dart';

abstract class RosterLeaderboardRepository {
  Future<List<RosterLeaderboardEntry>> fetchRosterRanking(String teacherId);

  /// One-based all-time rank, or null when [userId] has no leaderboard row.
  Future<int?> fetchGlobalRank(String userId);
}
