import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

Session _session({
  String movement = 'Hand Stall',
  String difficulty = 'Easy',
  int score = 70,
  String? createdAt,
  TrainingProp prop = TrainingProp.bottle,
}) {
  return Session(
    userId: 'u1',
    movementName: movement,
    difficulty: difficulty,
    score: score,
    durationSeconds: 60,
    createdAt: createdAt,
    propType: prop,
  );
}

LeaderboardEntry _entry({int sessions = 0, int best = 0}) {
  return LeaderboardEntry(
    userId: 'u1',
    displayName: 'Ada',
    totalXp: sessions * 25,
    sessionsCompleted: sessions,
    scoreSum: best.toDouble(),
    averageScore: best.toDouble(),
    bestScore: best,
  );
}

void main() {
  group('achievement catalog', () {
    test('contains exactly ten unique fixed ids', () {
      expect(achievementCatalog, hasLength(10));
      final ids = achievementCatalog.map((a) => a.id).toSet();
      expect(ids, hasLength(10));
    });

    test('every achievement reward maps to a known border', () {
      for (final achievement in achievementCatalog) {
        expect(achievement.rewardBorderId, isNotEmpty, reason: achievement.id);
      }
    });
  });

  group('AchievementProgress', () {
    test('normalizedProgress clamps to 0..1', () {
      expect(
        const AchievementProgress(
          current: -1,
          target: 10,
          completed: false,
        ).normalizedProgress,
        0.0,
      );
      expect(
        const AchievementProgress(
          current: 5,
          target: 10,
          completed: false,
        ).normalizedProgress,
        0.5,
      );
      expect(
        const AchievementProgress(
          current: 20,
          target: 10,
          completed: true,
        ).normalizedProgress,
        1.0,
      );
    });
  });

  group('evaluators', () {
    test(
      'session milestones use the larger of history and leaderboard counts',
      () {
        final first = achievementById('first_steps')!;
        expect(first.evaluator(const [], null).completed, isFalse);
        expect(first.evaluator([_session()], null).completed, isTrue);
        expect(
          first.evaluator(const [], _entry(sessions: 1)).completed,
          isTrue,
        );

        final ten = achievementById('getting_started')!;
        expect(
          ten
              .evaluator(
                List.generate(3, (_) => _session()),
                _entry(sessions: 10),
              )
              .current,
          10,
        );
        expect(
          ten
              .evaluator(
                List.generate(12, (_) => _session()),
                _entry(sessions: 10),
              )
              .current,
          10,
        );
      },
    );

    test('sharp_pour requires best score >= 90', () {
      final def = achievementById('sharp_pour')!;
      expect(def.evaluator([_session(score: 89)], null).completed, isFalse);
      expect(def.evaluator([_session(score: 90)], null).completed, isTrue);
      expect(def.evaluator(const [], _entry(best: 95)).completed, isTrue);
    });

    test('perfect_serve requires score of 100', () {
      final def = achievementById('perfect_serve')!;
      expect(def.evaluator([_session(score: 99)], null).completed, isFalse);
      expect(def.evaluator([_session(score: 100)], null).completed, isTrue);
    });

    test('movement_explorer counts distinct normalized movement names', () {
      final def = achievementById('movement_explorer')!;
      final sessions = [
        _session(movement: 'Hand Stall'),
        _session(movement: ' hand stall '),
        _session(movement: 'Around the World'),
        _session(movement: 'Tin Spin'),
        _session(movement: 'Palm Spin'),
      ];
      expect(def.evaluator(sessions, null).current, 4);
      expect(def.evaluator(sessions, null).completed, isFalse);

      final five = [...sessions, _session(movement: 'Behind the Back')];
      expect(def.evaluator(five, null).completed, isTrue);
    });

    test('versatility_master requires Easy, Medium, and Hard', () {
      final def = achievementById('versatility_master')!;
      expect(
        def.evaluator([
          _session(difficulty: 'Easy'),
          _session(difficulty: 'Medium'),
        ], null).completed,
        isFalse,
      );
      expect(
        def.evaluator([
          _session(difficulty: ' easy '),
          _session(difficulty: 'MEDIUM'),
          _session(difficulty: 'Hard'),
        ], null).completed,
        isTrue,
      );
    });

    test('week_warrior requires seven consecutive calendar days', () {
      final def = achievementById('week_warrior')!;
      final days = List.generate(
        7,
        (i) =>
            _session(createdAt: DateTime.utc(2026, 3, 1 + i).toIso8601String()),
      );
      expect(def.evaluator(days, null).completed, isTrue);

      final gap = [
        _session(createdAt: '2026-03-01T10:00:00.000Z'),
        _session(createdAt: '2026-03-02T10:00:00.000Z'),
        _session(createdAt: '2026-03-04T10:00:00.000Z'),
      ];
      expect(def.evaluator(gap, null).completed, isFalse);
      expect(def.evaluator(gap, null).current, lessThan(7));
    });

    test(
      'bottle_in_tin_specialist requires movement + bottleAndShaker prop',
      () {
        final def = achievementById('bottle_in_tin_specialist')!;
        final wrongProp = List.generate(
          5,
          (_) =>
              _session(movement: 'Bottle in a Tin', prop: TrainingProp.bottle),
        );
        expect(def.evaluator(wrongProp, null).completed, isFalse);

        final matching = List.generate(
          5,
          (_) => _session(
            movement: ' bottle in a tin ',
            prop: TrainingProp.bottleAndShaker,
          ),
        );
        expect(def.evaluator(matching, null).completed, isTrue);
      },
    );
  });

  group('state resolution', () {
    test('claimed overrides temporarily missing progress', () {
      final view = buildAchievementViewData(
        definition: achievementById('first_steps')!,
        sessions: const [],
        leaderboardEntry: null,
        claimedAchievementIds: {'first_steps'},
      );
      expect(view.state, AchievementState.claimed);
      expect(view.progress.completed, isFalse);
    });

    test('incomplete achievement is not claimable', () {
      final view = buildAchievementViewData(
        definition: achievementById('getting_started')!,
        sessions: [_session()],
        leaderboardEntry: null,
        claimedAchievementIds: const {},
      );
      expect(view.state, AchievementState.inProgress);
      expect(view.state, isNot(AchievementState.claimable));
    });

    test('complete and unclaimed is claimable', () {
      final view = buildAchievementViewData(
        definition: achievementById('first_steps')!,
        sessions: [_session()],
        leaderboardEntry: null,
        claimedAchievementIds: const {},
      );
      expect(view.state, AchievementState.claimable);
    });

    test('zero progress is locked', () {
      final view = buildAchievementViewData(
        definition: achievementById('century_club')!,
        sessions: const [],
        leaderboardEntry: null,
        claimedAchievementIds: const {},
      );
      expect(view.state, AchievementState.locked);
    });
  });

  group('achievement progression', () {
    test('every achievement has a unique positive progressionOrder', () {
      final orders = achievementCatalog.map((a) => a.progressionOrder).toList();
      expect(orders.every((o) => o > 0), isTrue);
      expect(orders.toSet(), hasLength(achievementCatalog.length));
    });

    test('progressionOrder matches agreed easy-to-hard sequence', () {
      final byOrder = [...achievementCatalog]
        ..sort(compareAchievementsByProgression);
      expect(byOrder.map((a) => a.id).toList(), [
        'first_steps',
        'getting_started',
        'movement_explorer',
        'sharp_pour',
        'week_warrior',
        'flair_regular',
        'versatility_master',
        'bottle_in_tin_specialist',
        'perfect_serve',
        'century_club',
      ]);
    });

    test('filtered subsets preserve progression order', () {
      final views = buildAllAchievementViewData(
        sessions: const [],
        leaderboardEntry: null,
        claimedAchievementIds: {'first_steps', 'century_club'},
      );
      final claimed =
          views.where((v) => v.state == AchievementState.claimed).toList()
            ..sort(
              (a, b) =>
                  compareAchievementsByProgression(a.definition, b.definition),
            );
      expect(claimed.map((v) => v.definition.id).toList(), [
        'first_steps',
        'century_club',
      ]);
    });
  });
}
