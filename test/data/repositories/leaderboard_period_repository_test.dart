import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/leaderboard_period.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry _entry({
  required String id,
  int totalXp = 0,
  int bestScore = 0,
  int dailyXp = 0,
  int dailyBestScore = 0,
  int monthlyXp = 0,
  int monthlyBestScore = 0,
}) {
  return LeaderboardEntry(
    userId: id,
    displayName: id,
    totalXp: totalXp,
    sessionsCompleted: 0,
    scoreSum: 0,
    averageScore: 0,
    bestScore: bestScore,
    dailyXp: dailyXp,
    dailyBestScore: dailyBestScore,
    monthlyXp: monthlyXp,
    monthlyBestScore: monthlyBestScore,
  );
}

void main() {
  test('daily ordering is XP desc, best desc, then UID asc', () {
    final entries = [
      _entry(id: 'z', dailyXp: 100, dailyBestScore: 90),
      _entry(id: 'b', dailyXp: 120, dailyBestScore: 70),
      _entry(id: 'y', dailyXp: 100, dailyBestScore: 95),
      _entry(id: 'a', dailyXp: 100, dailyBestScore: 95),
    ];

    LeaderboardRepository.sortLeaderboardEntries(
      entries,
      period: LeaderboardPeriod.today,
    );

    expect(entries.map((entry) => entry.userId), ['b', 'a', 'y', 'z']);
  });

  test('monthly ordering is XP desc, best desc, then UID asc', () {
    final entries = [
      _entry(id: 'z', monthlyXp: 80, monthlyBestScore: 99),
      _entry(id: 'c', monthlyXp: 100, monthlyBestScore: 85),
      _entry(id: 'b', monthlyXp: 100, monthlyBestScore: 90),
      _entry(id: 'a', monthlyXp: 100, monthlyBestScore: 90),
    ];

    LeaderboardRepository.sortLeaderboardEntries(
      entries,
      period: LeaderboardPeriod.thisMonth,
    );

    expect(entries.map((entry) => entry.userId), ['a', 'b', 'c', 'z']);
  });

  test('default all-time ordering remains unchanged', () {
    final entries = [
      _entry(id: 'z', totalXp: 100, bestScore: 90, dailyXp: 999),
      _entry(id: 'b', totalXp: 125, bestScore: 70),
      _entry(id: 'y', totalXp: 100, bestScore: 95),
      _entry(id: 'a', totalXp: 100, bestScore: 95),
    ];

    LeaderboardRepository.sortLeaderboardEntries(entries);

    expect(entries.map((entry) => entry.userId), ['b', 'a', 'y', 'z']);
  });

  test('pagination cursor identity includes period and resolved key', () {
    final cursor = FakeLeaderboardPageCursor(
      'today-page-1',
      period: LeaderboardPeriod.today,
      periodKey: '20260810',
    );

    expect(
      LeaderboardRepository.isCursorCompatible(
        cursor: cursor,
        period: LeaderboardPeriod.today,
        periodKey: '20260810',
      ),
      isTrue,
    );
    expect(
      LeaderboardRepository.isCursorCompatible(
        cursor: cursor,
        period: LeaderboardPeriod.thisMonth,
        periodKey: '202608',
      ),
      isFalse,
    );
    expect(
      LeaderboardRepository.isCursorCompatible(
        cursor: cursor,
        period: LeaderboardPeriod.today,
        periodKey: '20260811',
      ),
      isFalse,
    );
  });
}
