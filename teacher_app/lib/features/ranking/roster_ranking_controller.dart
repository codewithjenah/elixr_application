import 'package:elixr_core/models/roster_leaderboard_entry.dart';
import 'package:elixr_core/repositories/roster_leaderboard_repository.dart';
import 'package:flutter/foundation.dart';

enum RosterRankingState { loading, empty, ready, error }

class RosterRankingController extends ChangeNotifier {
  RosterRankingController({required this.repository, required this.teacherId});

  final RosterLeaderboardRepository repository;
  final String teacherId;
  List<RosterLeaderboardEntry> entries = const [];
  RosterRankingState state = RosterRankingState.loading;

  Future<void> load() async {
    state = RosterRankingState.loading;
    notifyListeners();
    try {
      entries = await repository.fetchRosterRanking(teacherId);
      state = entries.isEmpty
          ? RosterRankingState.empty
          : RosterRankingState.ready;
    } catch (_) {
      entries = const [];
      state = RosterRankingState.error;
    }
    notifyListeners();
  }
}
