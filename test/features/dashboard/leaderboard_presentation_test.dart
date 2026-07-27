import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/features/dashboard/leaderboard_presentation.dart';
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
      entry(id: '5', name: 'E', xp: 175),
      entry(id: 'me', name: 'Me', xp: 150),
      entry(id: '7', name: 'G', xp: 125),
      entry(id: '8', name: 'H', xp: 100),
      entry(id: '9', name: 'I', xp: 75),
      entry(id: '10', name: 'J', xp: 50),
    ];

    test('correct top-three ordering', () {
      final podium = LeaderboardPresentation.podiumOf(top);
      expect(podium.map((e) => e.userId), ['1', '2', '3']);
    });

    test('compact rows are ranks 4–10', () {
      final rows = LeaderboardPresentation.compactRowsOf(top);
      expect(rows.length, 7);
      expect(rows.first.rank, 4);
      expect(rows.last.rank, 10);
      expect(rows.map((r) => r.entry.userId).contains('me'), isTrue);
    });

    test('current-user detection', () {
      expect(LeaderboardPresentation.containsUser(top, 'me'), isTrue);
      expect(LeaderboardPresentation.containsUser(top, 'missing'), isFalse);
      expect(LeaderboardPresentation.containsUser(top, null), isFalse);
    });

    test('current user outside Top 10', () {
      final outside = entry(id: 'me', name: 'Me', xp: 10);
      final standing = LeaderboardPresentation.standingOutsideTop(
        topPlayers: top.where((e) => e.userId != 'me').toList(),
        currentUserId: 'me',
        currentUserEntry: outside,
      );
      expect(standing, isNotNull);
      expect(standing!.userId, 'me');
      expect(standing.totalXp, 10);
    });

    test('no standing row when user is in Top 10', () {
      final standing = LeaderboardPresentation.standingOutsideTop(
        topPlayers: top,
        currentUserId: 'me',
        currentUserEntry: top.firstWhere((e) => e.userId == 'me'),
      );
      expect(standing, isNull);
    });

    test('empty top players produces empty podium and rows', () {
      expect(LeaderboardPresentation.podiumOf(const []), isEmpty);
      expect(LeaderboardPresentation.compactRowsOf(const []), isEmpty);
    });

    test('initials helper', () {
      expect(LeaderboardPresentation.initialsFor('Ada Lovelace'), 'AL');
      expect(LeaderboardPresentation.initialsFor('Grace'), 'GR');
      expect(LeaderboardPresentation.initialsFor('  '), '?');
    });

    test('current-user highlight detection for YOU badge', () {
      expect(LeaderboardPresentation.containsUser(top, 'me'), isTrue);
      final standing = LeaderboardPresentation.standingOutsideTop(
        topPlayers: top,
        currentUserId: 'me',
        currentUserEntry: top.firstWhere((e) => e.userId == 'me'),
      );
      expect(standing, isNull);
    });
  });
}
