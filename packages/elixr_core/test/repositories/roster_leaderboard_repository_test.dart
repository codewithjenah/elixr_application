import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = RosterLeaderboardEntry(
    userId: 'a',
    displayName: 'A',
    totalXp: 50,
    sessionsCompleted: 2,
    bestScore: 10,
    rosterRank: 0,
  );
  const b = RosterLeaderboardEntry(
    userId: 'b',
    displayName: 'B',
    totalXp: 50,
    sessionsCompleted: 2,
    bestScore: 11,
    rosterRank: 0,
  );
  const z = RosterLeaderboardEntry(
    userId: 'z',
    displayName: 'Zero',
    totalXp: 0,
    sessionsCompleted: 0,
    bestScore: 0,
    rosterRank: 0,
  );

  test('orders by XP, best score, then UID and assigns ranks', () async {
    final repository = InMemoryRosterLeaderboardRepository(
      rosterRows: {
        'teacher': [z, a, b],
      },
    );
    final rows = await repository.fetchRosterRanking('teacher');
    expect(rows.map((row) => row.userId), ['b', 'a', 'z']);
    expect(rows.map((row) => row.rosterRank), [1, 2, 3]);
  });

  test('global rank is null for missing leaderboard document', () async {
    final repository = InMemoryRosterLeaderboardRepository(
      globalRows: const [a, b],
    );
    expect(await repository.fetchGlobalRank('a'), 2);
    expect(await repository.fetchGlobalRank('missing'), isNull);
  });

  test('malformed leaderboard numbers are clamped to zero', () {
    final entry = RosterLeaderboardEntry.tryFromMap(
      {
        'display_name': 'Player',
        'total_xp': -10,
        'sessions_completed': 'bad',
        'best_score': -1,
      },
      id: 'player',
      fallbackName: 'Fallback',
    );
    expect(entry?.totalXp, 0);
    expect(entry?.sessionsCompleted, 0);
    expect(entry?.bestScore, 0);
  });
}
