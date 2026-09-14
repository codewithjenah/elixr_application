import 'dart:async';

import 'package:elixr_application/core/progression/matrix_test_access.dart';
import 'package:elixr_application/core/progression/progression_access.dart';
import 'package:elixr_application/core/progression/progression_catalog.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
