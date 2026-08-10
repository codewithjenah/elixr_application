import 'dart:async';

import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/leaderboard_period.dart';
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
  int? expireCursorOnCall;
  final pendingGates = <int, Completer<void>>{};

  Future<LeaderboardPage> fetch({LeaderboardPageCursor? startAfter}) async {
    final call = calls++;
    if (failOnCall == call) throw Exception('network');
    if (expireCursorOnCall == call) {
      throw const LeaderboardPageCursorExpiredException(
        cursorPeriod: LeaderboardPeriod.today,
        cursorPeriodKey: '20260810',
        requestedPeriod: LeaderboardPeriod.today,
        requestedPeriodKey: '20260811',
      );
    }
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

class FakePeriodPages {
  FakePeriodPages(this.pages);

  final List<LeaderboardPage> pages;
  final calls =
      <({LeaderboardPeriod period, LeaderboardPageCursor? startAfter})>[];
  final pendingGates = <int, Completer<void>>{};

  Future<LeaderboardPage> fetch({
    required LeaderboardPeriod period,
    LeaderboardPageCursor? startAfter,
  }) async {
    final call = calls.length;
    calls.add((period: period, startAfter: startAfter));
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

    test('expired loadMore cursor resets rows and reloads page 1', () async {
      final cursor = FakeLeaderboardPageCursor(
        'today-page-1',
        period: LeaderboardPeriod.today,
        periodKey: '20260810',
      );
      fake = FakePages([
        page([e('old-period', 100)], hasMore: true, cursor: cursor),
        page([e('unused', 90)]),
        page([e('fresh-period', 80)]),
      ])..expireCursorOnCall = 1;
      controller = LeaderboardListController(
        fetchPage: fake.fetch,
        initialPeriod: LeaderboardPeriod.today,
      );

      await controller.loadInitial();
      await controller.loadMore();

      expect(fake.calls, 3);
      expect(controller.entries.map((entry) => entry.userId), ['fresh-period']);
      expect(controller.hasMore, isFalse);
      expect(controller.isInitialLoading, isFalse);
      expect(controller.isLoadingMore, isFalse);
      expect(controller.initialError, isNull);
      expect(controller.loadMoreError, isNull);
    });

    test(
      'refresh keeps existing entries visible; stale loadMore result ignored',
      () async {
        final cursor = FakeLeaderboardPageCursor('p1');
        fake = FakePages([
          page([e('a', 100)], hasMore: true, cursor: cursor),
          page([e('stale', 1)]),
          page(
            [e('fresh', 200)],
            hasMore: true,
            cursor: FakeLeaderboardPageCursor('fresh-page-1'),
          ),
          page([e('next', 150)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);
        await controller.loadInitial();

        final gate = Completer<void>();
        fake.pendingGates[1] = gate;
        final loadMoreFuture = controller.loadMore();

        final refreshGate = Completer<void>();
        fake.pendingGates[2] = refreshGate;
        final refreshFuture = controller.refresh();
        expect(controller.entries.map((entry) => entry.userId), ['a']);
        expect(controller.isInitialLoading, isFalse);
        expect(controller.isLoadingMore, isFalse);

        gate.complete();
        await loadMoreFuture;
        refreshGate.complete();
        await refreshFuture;

        await pumpEventQueue();

        expect(controller.entries.map((entry) => entry.userId), ['fresh']);
        expect(controller.isInitialLoading, isFalse);
        expect(fake.calls, 3);

        await controller.loadMore();
        expect(controller.entries.map((entry) => entry.userId), [
          'fresh',
          'next',
        ]);
        expect(fake.calls, 4);
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

    test(
      'manual refresh rearms one post-sync reload for a forced sync',
      () async {
        fake = FakePages([
          page([e('a', 100)]),
          page([e('a', 150)]),
          page([e('a', 150)]),
          page([e('a', 200)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);

        await controller.loadInitial();
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
        expect(controller.entries.single.totalXp, 150);

        await controller.refresh();
        expect(fake.calls, 3);

        await controller.startBackgroundSync(
          userId: 'me',
          force: true,
          syncUser: () async => const LeaderboardSyncResult(
            totalSessionsChecked: 2,
            alreadyProcessed: 1,
            newlyProcessed: 1,
            failures: 0,
          ),
        );
        await pumpEventQueue();

        expect(fake.calls, 4);
        expect(controller.entries.single.totalXp, 200);
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

      final refreshGate = Completer<void>();
      fake.pendingGates[1] = refreshGate;

      final sync = controller.startBackgroundSync(
        userId: 'me',
        syncUser: () async => const LeaderboardSyncResult(
          totalSessionsChecked: 1,
          alreadyProcessed: 1,
          newlyProcessed: 0,
          failures: 0,
          publicProfileSynced: true,
        ),
      );
      await sync;
      await pumpEventQueue();

      expect(fake.calls, 2);
      expect(controller.entries, isNotEmpty);
      expect(controller.isInitialLoading, isFalse);

      refreshGate.complete();
      await pumpEventQueue();

      expect(
        controller.entries.single.profilePictureUrl,
        'https://example.com/a.jpg',
      );
      expect(fake.calls, 2);
    });

    test(
      'unchanged public profile sync does not trigger a second fetch',
      () async {
        fake = FakePages([
          page([e('a', 100)]),
          page([e('a', 100)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);

        await controller.loadInitial();
        expect(fake.calls, 1);

        await controller.startBackgroundSync(
          userId: 'me',
          syncUser: () async => const LeaderboardSyncResult(
            totalSessionsChecked: 1,
            alreadyProcessed: 1,
            newlyProcessed: 0,
            failures: 0,
            publicProfileSynced: false,
          ),
        );
        await pumpEventQueue();

        expect(fake.calls, 1);
        expect(controller.entries.map((entry) => entry.userId), ['a']);
      },
    );

    test(
      'newly processed sync refreshes without blanking visible entries',
      () async {
        fake = FakePages([
          page([e('a', 100)]),
          page([e('a', 150)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);

        await controller.loadInitial();

        final refreshGate = Completer<void>();
        fake.pendingGates[1] = refreshGate;

        final sync = controller.startBackgroundSync(
          userId: 'me',
          syncUser: () async => const LeaderboardSyncResult(
            totalSessionsChecked: 1,
            alreadyProcessed: 0,
            newlyProcessed: 1,
            failures: 0,
          ),
        );
        await sync;
        await pumpEventQueue();

        expect(fake.calls, 2);
        expect(controller.entries.map((entry) => entry.userId), ['a']);
        expect(controller.entries.single.totalXp, 100);
        expect(controller.isInitialLoading, isFalse);

        refreshGate.complete();
        await pumpEventQueue();

        expect(controller.entries.single.totalXp, 150);
        expect(controller.isInitialLoading, isFalse);
      },
    );

    test(
      'manual refresh with existing data never blanks the leaderboard',
      () async {
        fake = FakePages([
          page([e('a', 100), e('b', 90)]),
          page([e('a', 120), e('b', 90)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);

        await controller.loadInitial();

        final refreshGate = Completer<void>();
        fake.pendingGates[1] = refreshGate;

        final refresh = controller.refresh();
        expect(controller.entries.map((entry) => entry.userId), ['a', 'b']);
        expect(controller.isInitialLoading, isFalse);

        refreshGate.complete();
        await refresh;

        expect(controller.entries.first.totalXp, 120);
        expect(controller.isInitialLoading, isFalse);
      },
    );

    test(
      'post-sync first-page reload preserves pagination cursor for loadMore',
      () async {
        final cursor = FakeLeaderboardPageCursor('p1');
        final refreshedCursor = FakeLeaderboardPageCursor('p1-refreshed');
        fake = FakePages([
          page([e('a', 100)], hasMore: true, cursor: cursor),
          page([e('a', 150)], hasMore: true, cursor: refreshedCursor),
          page([e('b', 90)]),
        ]);
        controller = LeaderboardListController(fetchPage: fake.fetch);

        await controller.loadInitial();
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

        expect(controller.entries.map((entry) => entry.userId), ['a']);
        expect(controller.hasMore, isTrue);

        await controller.loadMore();
        expect(controller.entries.map((entry) => entry.userId), ['a', 'b']);
        expect(fake.calls, 3);
      },
    );

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

    test(
      'defaults to all time and switches the persistent controller',
      () async {
        final periodFake = FakePeriodPages([
          page([e('all-time', 300)]),
          page([e('today', 25)]),
        ]);
        controller = LeaderboardListController(
          fetchPageForPeriod: periodFake.fetch,
        );

        expect(controller.period, LeaderboardPeriod.allTime);
        await controller.loadInitial();
        expect(controller.entries.single.userId, 'all-time');

        final switching = controller.setPeriod(LeaderboardPeriod.today);
        expect(controller.period, LeaderboardPeriod.today);
        expect(controller.entries, isEmpty);
        expect(controller.isInitialLoading, isTrue);
        await switching;

        expect(controller.entries.single.userId, 'today');
        expect(periodFake.calls.map((call) => call.period), [
          LeaderboardPeriod.allTime,
          LeaderboardPeriod.today,
        ]);
      },
    );

    test(
      'stale page from previous period cannot overwrite current rows',
      () async {
        final periodFake = FakePeriodPages([
          page([e('stale-all-time', 999)]),
          page([e('fresh-month', 50)]),
        ]);
        final staleGate = Completer<void>();
        periodFake.pendingGates[0] = staleGate;
        controller = LeaderboardListController(
          fetchPageForPeriod: periodFake.fetch,
        );

        final staleLoad = controller.loadInitial();
        await pumpEventQueue();
        await controller.setPeriod(LeaderboardPeriod.thisMonth);

        expect(controller.period, LeaderboardPeriod.thisMonth);
        expect(controller.entries.single.userId, 'fresh-month');
        staleGate.complete();
        await staleLoad;

        expect(controller.entries.single.userId, 'fresh-month');
        expect(controller.initialError, isNull);
        expect(controller.isInitialLoading, isFalse);
      },
    );

    test(
      'period switch resets pagination and uses only the new cursor',
      () async {
        final allTimeCursor = FakeLeaderboardPageCursor('all-time-page-1');
        final todayCursor = FakeLeaderboardPageCursor('today-page-1');
        final periodFake = FakePeriodPages([
          page([e('all-time', 300)], hasMore: true, cursor: allTimeCursor),
          page([e('today-1', 50)], hasMore: true, cursor: todayCursor),
          page([e('today-2', 25)]),
        ]);
        controller = LeaderboardListController(
          fetchPageForPeriod: periodFake.fetch,
        );

        await controller.loadInitial();
        await controller.setPeriod(LeaderboardPeriod.today);
        await controller.loadMore();

        expect(periodFake.calls[1].period, LeaderboardPeriod.today);
        expect(periodFake.calls[1].startAfter, isNull);
        expect(periodFake.calls[2].period, LeaderboardPeriod.today);
        expect(periodFake.calls[2].startAfter, same(todayCursor));
        expect(periodFake.calls[2].startAfter, isNot(same(allTimeCursor)));
        expect(controller.entries.map((entry) => entry.userId), [
          'today-1',
          'today-2',
        ]);
      },
    );

    test('selecting the active period is a no-op', () async {
      final periodFake = FakePeriodPages([
        page([e('all-time', 300)]),
      ]);
      controller = LeaderboardListController(
        fetchPageForPeriod: periodFake.fetch,
      );

      await controller.loadInitial();
      await controller.setPeriod(LeaderboardPeriod.allTime);

      expect(periodFake.calls, hasLength(1));
      expect(controller.entries.single.userId, 'all-time');
    });
  });
}
