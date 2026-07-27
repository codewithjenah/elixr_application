import 'dart:async';

import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(LeaderboardRepository.clearSyncInFlightForTest);

  test('concurrent synchronization for one user is prevented', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var runs = 0;

    Future<LeaderboardSyncResult> action() async {
      runs++;
      started.complete();
      await release.future;
      return const LeaderboardSyncResult(
        totalSessionsChecked: 1,
        alreadyProcessed: 0,
        newlyProcessed: 1,
        failures: 0,
      );
    }

    final first = LeaderboardRepository.runWithSyncGuard('u1', action);
    final second = LeaderboardRepository.runWithSyncGuard('u1', action);

    await started.future;
    expect(identical(first, second), isTrue);
    expect(runs, 1);

    release.complete();
    final results = await Future.wait([first, second]);
    expect(results[0].newlyProcessed, 1);
    expect(results[1].newlyProcessed, 1);
    expect(runs, 1);
  });

  test('repeated synchronization planner is idempotent when all processed', () {
    final sessions = const [
      SessionRef(id: 'a', userId: 'u1', createdAtMs: 1),
      SessionRef(id: 'b', userId: 'u1', createdAtMs: 2),
    ];
    final processed = {'a', 'b'};
    expect(
      LeaderboardSyncPlanner.sessionsMissingAwards(
        sessions: sessions,
        processedSessionIds: processed,
      ),
      isEmpty,
    );
    expect(
      LeaderboardSyncPlanner.sessionsMissingAwards(
        sessions: sessions,
        processedSessionIds: processed,
      ),
      isEmpty,
    );
  });
}
