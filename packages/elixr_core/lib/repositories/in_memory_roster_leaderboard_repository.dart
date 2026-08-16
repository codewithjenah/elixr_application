import '../models/roster_leaderboard_entry.dart';
import 'roster_leaderboard_repository.dart';

class InMemoryRosterLeaderboardRepository
    implements RosterLeaderboardRepository {
  InMemoryRosterLeaderboardRepository({
    Map<String, List<RosterLeaderboardEntry>>? rosterRows,
    List<RosterLeaderboardEntry>? globalRows,
  }) : rosterRows = rosterRows ?? {},
       globalRows = globalRows ?? const [];

  final Map<String, List<RosterLeaderboardEntry>> rosterRows;
  final List<RosterLeaderboardEntry> globalRows;

  @override
  Future<List<RosterLeaderboardEntry>> fetchRosterRanking(
    String teacherId,
  ) async {
    final rows = <RosterLeaderboardEntry>[
      ...(rosterRows[teacherId] ?? const <RosterLeaderboardEntry>[]),
    ]..sort(RosterLeaderboardEntry.compare);
    return [
      for (var index = 0; index < rows.length; index++)
        rows[index].withRank(index + 1),
    ];
  }

  @override
  Future<int?> fetchGlobalRank(String userId) async {
    final rows = [...globalRows]..sort(RosterLeaderboardEntry.compare);
    final index = rows.indexWhere((row) => row.userId == userId);
    return index < 0 ? null : index + 1;
  }
}
