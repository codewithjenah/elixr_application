import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/features/leaderboard/leaderboard_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry entry({
  required String id,
  required String name,
  required int xp,
}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: xp ~/ 25,
    scoreSum: 0,
    averageScore: 0,
    bestScore: 0,
  );
}

void main() {
  group('LeaderboardPresentation', () {
    final top = [
      entry(id: '1', name: 'A', xp: 300),
      entry(id: '2', name: 'B', xp: 275),
      entry(id: '3', name: 'C', xp: 250),
      entry(id: '4', name: 'D', xp: 200),
      entry(id: 'me', name: 'Me', xp: 150),
    ];

    test('podium takes first three in rank order', () {
      final podium = LeaderboardPresentation.podiumOf(top);
      expect(podium.map((e) => e.userId), ['1', '2', '3']);
    });

    test('podium handles 0–3 entries', () {
      expect(LeaderboardPresentation.podiumOf(const []), isEmpty);
      expect(LeaderboardPresentation.podiumOf(top.take(1).toList()).length, 1);
      expect(LeaderboardPresentation.podiumOf(top.take(2).toList()).length, 2);
      expect(LeaderboardPresentation.podiumOf(top.take(3).toList()).length, 3);
    });

    test('display order is 2nd, 1st, 3rd with ranks retained', () {
      final podium = LeaderboardPresentation.podiumOf(top);
      final display = LeaderboardPresentation.podiumDisplayOrder(podium);
      expect(display.map((s) => s.entry.userId), ['2', '1', '3']);
      expect(display.map((s) => s.rank), [2, 1, 3]);
    });

    test('ranked rows start at rank 4 from same list', () {
      final rows = LeaderboardPresentation.rankedRowsOf(top);
      expect(rows.map((r) => r.rank), [4, 5]);
      expect(rows.map((r) => r.entry.userId), ['4', 'me']);
    });

    test('podium and rows partition the same list', () {
      final podium = LeaderboardPresentation.podiumOf(top);
      final rows = LeaderboardPresentation.rankedRowsOf(top);
      expect([
        ...podium.map((e) => e.userId),
        ...rows.map((r) => r.entry.userId),
      ], top.map((e) => e.userId).toList());
    });

    test('YOU matching is identity equality on loaded entries only', () {
      const currentUserId = 'me';
      expect(top.any((e) => e.userId == currentUserId), isTrue);
      expect(
        LeaderboardPresentation.podiumOf(
          top,
        ).any((e) => e.userId == currentUserId),
        isFalse,
      );
      expect(
        LeaderboardPresentation.rankedRowsOf(
          top,
        ).any((r) => r.entry.userId == currentUserId),
        isTrue,
      );
      // Off-page user: not in loaded list → no standing helper exists.
      expect(top.any((e) => e.userId == 'missing'), isFalse);
    });

    test('initials helper', () {
      expect(LeaderboardPresentation.initialsFor('Ada Lovelace'), 'AL');
      expect(LeaderboardPresentation.initialsFor('Grace'), 'GR');
      expect(LeaderboardPresentation.initialsFor('  '), '?');
    });
  });
}
