import 'dart:async';

import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/features/leaderboard/leaderboard_list_controller.dart';
import 'package:elixr_application/features/leaderboard/leaderboard_presentation.dart';
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

LeaderboardPage page(
  List<LeaderboardEntry> entries, {
  bool hasMore = false,
  LeaderboardPageCursor? cursor,
}) {
  return LeaderboardPage(
    entries: entries,
    hasMore: hasMore,
    nextCursor: hasMore
        ? (cursor ?? FakeLeaderboardPageCursor('cursor'))
        : null,
  );
}

class FakePages {
  FakePages(this.pages);

  final List<LeaderboardPage> pages;
  int calls = 0;
  int? failOnCall;
  final pendingGates = <int, Completer<void>>{};

  Future<LeaderboardPage> fetch({LeaderboardPageCursor? startAfter}) async {
    final call = calls++;
    if (failOnCall == call) throw Exception('network');
    final gate = pendingGates[call];
    if (gate != null) await gate.future;
    if (call >= pages.length) {
      return const LeaderboardPage(
        entries: [],
        nextCursor: null,
        hasMore: false,
      );
    }
    return pages[call];
  }
}

void main() {
  group('LeaderboardListController', () {
    late FakePages fake;
    late LeaderboardListController controller;

    setUp(() {
      fake = FakePages(const []);
      controller = LeaderboardListController(fetchPage: fake.fetch);
    });

    tearDown(() {
      controller.dispose();
    });

    test(
      'initial load populates entries and clears isInitialLoading',
      () async {
        fake = FakePages([
          page([e('a', 100), e('b', 90)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);

        expect(controller.isInitialLoading, isFalse);
        final load = controller.loadInitial();
        expect(controller.isInitialLoading, isTrue);

        await load;

        expect(controller.isInitialLoading, isFalse);
        expect(controller.initialError, isNull);
        expect(controller.entries.map((entry) => entry.userId), ['a', 'b']);
        expect(controller.hasMore, isFalse);
        expect(fake.calls, 1);
      },
    );

    test('loadMore appends entries', () async {
      final cursor = FakeLeaderboardPageCursor('p1');
      fake = FakePages([
        page([e('a', 100), e('b', 90)], hasMore: true, cursor: cursor),
        page([e('c', 80), e('d', 70)]),
      ]);
      controller = LeaderboardListController(fetchPage: fake.fetch);

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.entries.map((entry) => entry.userId), [
        'a',
        'b',
        'c',
        'd',
      ]);
      expect(controller.isLoadingMore, isFalse);
      expect(fake.calls, 2);
    });

    test('loadMore skips duplicate userId on append', () async {
      final cursor = FakeLeaderboardPageCursor('p1');
      fake = FakePages([
        page([e('a', 100), e('b', 90)], hasMore: true, cursor: cursor),
        page([e('b', 50), e('c', 80)]),
      ]);
      controller = LeaderboardListController(fetchPage: fake.fetch);

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.entries.map((entry) => entry.userId), ['a', 'b', 'c']);
    });

    test('second loadMore while first in flight is a no-op', () async {
      final cursor = FakeLeaderboardPageCursor('p1');
      fake = FakePages([
        page([e('a', 100)], hasMore: true, cursor: cursor),
        page([e('b', 90)]),
      ]);
      controller = LeaderboardListController(fetchPage: fake.fetch);
      await controller.loadInitial();

      final gate = Completer<void>();
      fake.pendingGates[1] = gate;

      final first = controller.loadMore();
      expect(controller.isLoadingMore, isTrue);

      await controller.loadMore();
      expect(fake.calls, 2);

      gate.complete();
      await first;

      expect(controller.entries.map((entry) => entry.userId), ['a', 'b']);
      expect(fake.calls, 2);
    });

    test('empty next page ends pagination without error', () async {
      final cursor = FakeLeaderboardPageCursor('p1');
      fake = FakePages([
        page([e('a', 100)], hasMore: true, cursor: cursor),
      ]);
      controller = LeaderboardListController(fetchPage: fake.fetch);

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.entries.map((entry) => entry.userId), ['a']);
      expect(controller.hasMore, isFalse);
      expect(controller.loadMoreError, isNull);
    });

    test('loadMore error preserves rows and sets loadMoreError only', () async {
      final cursor = FakeLeaderboardPageCursor('p1');
      fake = FakePages([
        page([e('a', 100)], hasMore: true, cursor: cursor),
        page([e('b', 90)]),
      ]);
      fake.failOnCall = 1;
      controller = LeaderboardListController(fetchPage: fake.fetch);

      await controller.loadInitial();
      await controller.loadMore();

      expect(controller.entries.map((entry) => entry.userId), ['a']);
      expect(controller.loadMoreError, isA<Exception>());
      expect(controller.initialError, isNull);
    });

    test(
      'refresh clears and restarts; stale loadMore result ignored',
      () async {
        final cursor = FakeLeaderboardPageCursor('p1');
        fake = FakePages([
          page([e('a', 100)], hasMore: true, cursor: cursor),
          page([e('stale', 1)]),
          page([e('fresh', 200)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);
        await controller.loadInitial();

        final gate = Completer<void>();
        fake.pendingGates[1] = gate;
        final loadMoreFuture = controller.loadMore();

        final refreshFuture = controller.refresh();
        expect(controller.entries, isEmpty);
        expect(controller.isInitialLoading, isTrue);

        gate.complete();
        await loadMoreFuture;
        await refreshFuture;

        await pumpEventQueue();

        expect(controller.entries.map((entry) => entry.userId), ['fresh']);
        expect(controller.isInitialLoading, isFalse);
        expect(fake.calls, 3);
      },
    );

    test(
      'ranks via presentation helpers remain index + 1 after two pages',
      () async {
        final cursor = FakeLeaderboardPageCursor('p1');
        fake = FakePages([
          page(
            [e('1', 500), e('2', 400), e('3', 300)],
            hasMore: true,
            cursor: cursor,
          ),
          page([e('4', 200), e('5', 100)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);

        await controller.loadInitial();
        await controller.loadMore();

        final rows = LeaderboardPresentation.rankedRowsOf(controller.entries);
        expect(rows.map((row) => row.rank), [4, 5]);
        expect(rows.map((row) => row.entry.userId), ['4', '5']);
      },
    );

    test(
      'sync completing before initial load schedules one post-sync refresh',
      () async {
        fake = FakePages([
          page([e('a', 100)]),
          page([e('a', 150)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);

        final initialGate = Completer<void>();
        fake.pendingGates[0] = initialGate;

        var syncCalls = 0;
        final initialLoad = controller.loadInitial();
        final sync = controller.startBackgroundSync(
          userId: 'me',
          syncUser: () async {
            syncCalls++;
            return const LeaderboardSyncResult(
              totalSessionsChecked: 1,
              alreadyProcessed: 0,
              newlyProcessed: 1,
              failures: 0,
            );
          },
        );

        await sync;
        expect(syncCalls, 1);

        initialGate.complete();
        await initialLoad;
        await pumpEventQueue();

        expect(fake.calls, 2);
        expect(controller.entries.single.totalXp, 150);
      },
    );

    test(
      'auto refresh at most once even if sync reports awards again',
      () async {
        fake = FakePages([
          page([e('a', 100)]),
          page([e('a', 150)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);

        await controller.loadInitial();

        var syncCalls = 0;
        await controller.startBackgroundSync(
          userId: 'me',
          syncUser: () async {
            syncCalls++;
            return const LeaderboardSyncResult(
              totalSessionsChecked: 1,
              alreadyProcessed: 0,
              newlyProcessed: 1,
              failures: 0,
            );
          },
        );
        await pumpEventQueue();
        expect(fake.calls, 2);

        await controller.startBackgroundSync(
          userId: 'other',
          syncUser: () async {
            syncCalls++;
            return const LeaderboardSyncResult(
              totalSessionsChecked: 1,
              alreadyProcessed: 0,
              newlyProcessed: 1,
              failures: 0,
            );
          },
        );
        await pumpEventQueue();

        expect(syncCalls, 2);
        expect(fake.calls, 2);
      },
    );

    test('sync failure does not set initialError', () async {
      fake = FakePages([
        page([e('a', 100)]),
      ]);
      controller = LeaderboardListController(fetchPage: fake.fetch);

      await controller.startBackgroundSync(
        userId: 'me',
        syncUser: () async => throw Exception('sync failed'),
      );
      await controller.loadInitial();

      expect(controller.initialError, isNull);
      expect(controller.entries.map((entry) => entry.userId), ['a']);
    });

    test('no auto refresh when additional pages already loaded', () async {
      final cursor = FakeLeaderboardPageCursor('p1');
      fake = FakePages([
        page([e('a', 100)], hasMore: true, cursor: cursor),
        page([e('b', 90)]),
        page([e('a', 150)]),
      ]);
      controller = LeaderboardListController(fetchPage: fake.fetch);

      await controller.loadInitial();
      await controller.loadMore();
      expect(fake.calls, 2);

      await controller.startBackgroundSync(
        userId: 'me',
        syncUser: () async => const LeaderboardSyncResult(
          totalSessionsChecked: 1,
          alreadyProcessed: 0,
          newlyProcessed: 1,
          failures: 0,
        ),
      );
      await pumpEventQueue();

      expect(fake.calls, 2);
    });

    test('profile-only sync still triggers one auto refresh', () async {
      fake = FakePages([
        page([e('a', 100)]),
        page([
          LeaderboardEntry(
            userId: 'a',
            displayName: 'a',
            totalXp: 100,
            sessionsCompleted: 1,
            scoreSum: 0,
            averageScore: 0,
            bestScore: 100,
            profilePictureUrl: 'https://example.com/a.jpg',
          ),
        ]),
      ]);
      controller = LeaderboardListController(fetchPage: fake.fetch);

      await controller.loadInitial();

        await controller.startBackgroundSync(
          userId: 'me',
          syncUser: () async => const LeaderboardSyncResult(
            totalSessionsChecked: 1,
            alreadyProcessed: 1,
            newlyProcessed: 0,
            failures: 0,
            publicProfileSynced: true,
          ),
        );
      await pumpEventQueue();

      expect(fake.calls, 2);
    });

    test('refresh resets pagination state but not sync guards', () async {
      fake = FakePages([
        page([e('a', 100)]),
        page([e('b', 90)]),
      ]);
      controller = LeaderboardListController(fetchPage: fake.fetch);

      var syncCalls = 0;
      await controller.startBackgroundSync(
        userId: 'me',
        syncUser: () async {
          syncCalls++;
          return LeaderboardSyncResult.empty;
        },
      );
      await controller.loadInitial();

      await controller.refresh();
      await pumpEventQueue();

      expect(syncCalls, 1);
      expect(controller.entries.map((entry) => entry.userId), ['b']);
      expect(controller.loadMoreError, isNull);
      expect(controller.initialError, isNull);
    });
  });
}
