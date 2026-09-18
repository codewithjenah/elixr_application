import 'dart:async';

import 'package:elixr_application/core/progression/matrix_test_access.dart';
import 'package:elixr_application/core/progression/progression_access.dart';
import 'package:elixr_application/core/progression/progression_catalog.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:elixr_application/services/trainee_progression_snapshot_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

class _WatchRepository extends LeaderboardRepository {
  final controllers = <String, StreamController<LeaderboardEntry?>>{};

  @override
  Stream<LeaderboardEntry?> watchPlayer(String userId) {
    return controllers
        .putIfAbsent(userId, StreamController<LeaderboardEntry?>.broadcast)
        .stream;
  }

  Future<void> close() async {
    for (final controller in controllers.values) {
      await controller.close();
    }
  }
}

LeaderboardEntry _entry(String userId, int totalXp) => LeaderboardEntry(
  userId: userId,
  displayName: userId,
  totalXp: totalXp,
  sessionsCompleted: 0,
  scoreSum: 0,
  averageScore: 0,
  bestScore: 0,
);

Future<TraineeProgressionSnapshotStore> _store() async {
  final directory = await Directory.systemTemp.createTemp('elixr_service_xp_');
  addTearDown(() => directory.delete(recursive: true));
  return TraineeProgressionSnapshotStore(directory: directory);
}

void main() {
  test(
    'account switch cancels and ignores the previous progression listener',
    () async {
      final repository = _WatchRepository();
      final service = TraineeProgressionService(
        leaderboardRepository: repository,
      );
      addTearDown(service.dispose);
      addTearDown(repository.close);

      await service.setUser('trainee-a');
      repository.controllers['trainee-a']!.add(_entry('trainee-a', 100));
      await pumpEventQueue();
      expect(service.totalXp, 100);

      await service.setUser('trainee-b');
      expect(repository.controllers['trainee-a']!.hasListener, isFalse);
      repository.controllers['trainee-a']!.add(_entry('trainee-a', 999));
      repository.controllers['trainee-b']!.add(_entry('trainee-b', 200));
      await pumpEventQueue();

      expect(service.totalXp, 200);
    },
  );

  test('null auth state leaves no protected progression listener', () async {
    final repository = _WatchRepository();
    final service = TraineeProgressionService(
      leaderboardRepository: repository,
    );
    addTearDown(service.dispose);
    addTearDown(repository.close);

    await service.setUser('trainee-a');
    await service.setUser(null);

    expect(repository.controllers['trainee-a']!.hasListener, isFalse);
    expect(service.isReady, isTrue);
    expect(service.totalXp, 0);
  });

  test(
    'matrix account gets Level 20 access without changing real XP',
    () async {
      final repository = _WatchRepository();
      final service = TraineeProgressionService(
        leaderboardRepository: repository,
        matrixTestAccessPolicy: const MatrixTestAccessPolicy(
          configuredUid: 'matrix-uid',
        ),
      );
      addTearDown(service.dispose);
      addTearDown(repository.close);

      await service.setUser(' matrix-uid ');
      repository.controllers['matrix-uid']!.add(_entry('matrix-uid', 125));
      await pumpEventQueue();

      expect(service.totalXp, 125);
      expect(service.level, 1);
      expect(service.currentLevelOrNull, 20);
      for (final milestone in progressionMilestones) {
        expect(
          evaluatePersonal(
            variant: milestone.variant,
            currentLevel: service.currentLevelOrNull,
            tutorialCompleted: true,
          ),
          ProgressionAccessResult.personalReady,
          reason: milestone.variant.persistenceKey,
        );
      }
    },
  );

  test('ordinary account keeps its actual progression level', () async {
    final repository = _WatchRepository();
    final service = TraineeProgressionService(
      leaderboardRepository: repository,
      matrixTestAccessPolicy: const MatrixTestAccessPolicy(
        configuredUid: 'matrix-uid',
      ),
    );
    addTearDown(service.dispose);
    addTearDown(repository.close);

    await service.setUser('ordinary-uid');
    repository.controllers['ordinary-uid']!.add(_entry('ordinary-uid', 125));
    await pumpEventQueue();

    expect(service.totalXp, 125);
    expect(service.level, 1);
    expect(service.currentLevelOrNull, 1);
    expect(
      evaluatePersonal(
        variant: progressionMilestones.last.variant,
        currentLevel: service.currentLevelOrNull,
        tutorialCompleted: true,
      ),
      ProgressionAccessResult.personalLocked,
    );
  });

  test(
    'authoritative entry is persisted and restores on an offline cold start',
    () async {
      final repository = _WatchRepository();
      final store = await _store();
      final online = TraineeProgressionService(
        leaderboardRepository: repository,
        progressionSnapshotStore: store,
      );
      addTearDown(online.dispose);
      addTearDown(repository.close);

      await online.setUser('trainee-a');
      repository.controllers['trainee-a']!.add(_entry('trainee-a', 1500));
      await pumpEventQueue();
      await pumpEventQueue();
      expect((await store.load('trainee-a'))?.totalXp, 1500);

      final coldStart = TraineeProgressionService(
        leaderboardRepository: _WatchRepository(),
        progressionSnapshotStore: store,
      );
      addTearDown(coldStart.dispose);
      await coldStart.setUser('trainee-a');

      expect(coldStart.isReady, isTrue);
      expect(coldStart.totalXp, 1500);
      expect(coldStart.level, 7);
    },
  );

  test('a later authoritative value replaces the cached value', () async {
    final repository = _WatchRepository();
    final store = await _store();
    await store.save(
      const TraineeProgressionSnapshot(userId: 'trainee-a', totalXp: 250),
    );
    final service = TraineeProgressionService(
      leaderboardRepository: repository,
      progressionSnapshotStore: store,
    );
    addTearDown(service.dispose);
    addTearDown(repository.close);

    await service.setUser('trainee-a');
    expect(service.totalXp, 250);
    repository.controllers['trainee-a']!.add(_entry('trainee-a', 1000));
    await pumpEventQueue();
    await pumpEventQueue();

    expect(service.totalXp, 1000);
    expect((await store.load('trainee-a'))?.totalXp, 1000);
  });

  test(
    'stream failure retains cached progression but no cache remains fail-closed',
    () async {
      final repository = _WatchRepository();
      final store = await _store();
      await store.save(
        const TraineeProgressionSnapshot(userId: 'cached', totalXp: 500),
      );
      final cached = TraineeProgressionService(
        leaderboardRepository: repository,
        progressionSnapshotStore: store,
      );
      addTearDown(cached.dispose);
      addTearDown(repository.close);

      await cached.setUser('cached');
      repository.controllers['cached']!.addError(StateError('offline'));
      await pumpEventQueue();
      expect(cached.isReady, isTrue);
      expect(cached.totalXp, 500);

      final uncachedRepository = _WatchRepository();
      final uncached = TraineeProgressionService(
        leaderboardRepository: uncachedRepository,
        progressionSnapshotStore: store,
      );
      addTearDown(uncached.dispose);
      addTearDown(uncachedRepository.close);
      await uncached.setUser('uncached');
      uncachedRepository.controllers['uncached']!.addError(
        StateError('offline'),
      );
      await pumpEventQueue();
      expect(uncached.isReady, isFalse);
      expect(uncached.currentLevelOrNull, isNull);
    },
  );

  test(
    'switching users clears prior progression and purged cache cannot restore',
    () async {
      final repository = _WatchRepository();
      final store = await _store();
      await store.save(
        const TraineeProgressionSnapshot(userId: 'trainee-a', totalXp: 750),
      );
      final service = TraineeProgressionService(
        leaderboardRepository: repository,
        progressionSnapshotStore: store,
      );
      addTearDown(service.dispose);
      addTearDown(repository.close);

      await service.setUser('trainee-a');
      expect(service.totalXp, 750);
      final switchFuture = service.setUser('trainee-b');
      expect(service.totalXp, 0);
      expect(service.isReady, isFalse);
      await switchFuture;
      await store.purge('trainee-a');

      final restored = TraineeProgressionService(
        leaderboardRepository: _WatchRepository(),
        progressionSnapshotStore: store,
      );
      addTearDown(restored.dispose);
      await restored.setUser('trainee-a');
      expect(restored.isReady, isFalse);
      expect(restored.currentLevelOrNull, isNull);
    },
  );

  test(
    'matrix override is applied on restored real XP without mutating it',
    () async {
      final store = await _store();
      await store.save(
        const TraineeProgressionSnapshot(userId: 'matrix', totalXp: 125),
      );
      final service = TraineeProgressionService(
        leaderboardRepository: _WatchRepository(),
        progressionSnapshotStore: store,
        matrixTestAccessPolicy: const MatrixTestAccessPolicy(
          configuredUid: 'matrix',
        ),
      );
      addTearDown(service.dispose);

      await service.setUser('matrix');
      expect(service.totalXp, 125);
      expect(service.level, 1);
      expect(service.currentLevelOrNull, 20);
    },
  );
}
