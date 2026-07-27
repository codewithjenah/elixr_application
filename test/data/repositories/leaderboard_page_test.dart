import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry e(String id, int xp) => LeaderboardEntry(
  userId: id,
  displayName: id,
  totalXp: xp,
  sessionsCompleted: 1,
  scoreSum: 0,
  averageScore: 0,
  bestScore: xp,
);

void main() {
  test('full document page sets hasMore and requires cursor', () {
    final entries = [for (var i = 0; i < 49; i++) e('u$i', 100 - i)];
    final cursor = FakeLeaderboardPageCursor('page1');
    final page = LeaderboardRepository.buildPage(
      entries: entries, // one malformed doc dropped → 49 entries
      returnedDocumentCount: 50,
      limit: 50,
      cursorFromLastDoc: cursor,
    );
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, same(cursor));
    expect(page.entries.length, 49);
  });

  test('hasMore true without cursor throws', () {
    expect(
      () => LeaderboardRepository.buildPage(
        entries: [for (var i = 0; i < 50; i++) e('u$i', 100 - i)],
        returnedDocumentCount: 50,
        limit: 50,
        cursorFromLastDoc: null,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('short document page sets hasMore false and null cursor', () {
    final page = LeaderboardRepository.buildPage(
      entries: [e('a', 10), e('b', 5)],
      returnedDocumentCount: 2,
      limit: 50,
      cursorFromLastDoc: FakeLeaderboardPageCursor('ignored'),
    );
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
  });

  test('empty page sets hasMore false', () {
    final page = LeaderboardRepository.buildPage(
      entries: const [],
      returnedDocumentCount: 0,
      limit: 50,
      cursorFromLastDoc: null,
    );
    expect(page.entries, isEmpty);
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
  });
}
