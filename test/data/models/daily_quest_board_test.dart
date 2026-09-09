import 'package:elixr_application/data/models/daily_quest.dart';
import 'package:elixr_application/data/models/daily_quest_board.dart';
import 'package:elixr_application/data/models/daily_quest_eligibility.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

QuestTier _tierOf(String id) => questById(id)!.tier;
QuestCategory _categoryOf(String id) => questById(id)!.category;

List<String> _ids({
  String userId = 'user-1',
  required String dayKey,
  int currentLevel = 16,
}) => generateDailyQuestIds(
  userId: userId,
  dayKey: dayKey,
  currentLevel: currentLevel,
);

void _assertBoardShape(List<String> ids, {required int currentLevel}) {
  final effective = effectiveQuestGenerationLevel(currentLevel);
  expect(ids, hasLength(5));
  expect(ids.toSet(), hasLength(5));
  expect(ids.map(_tierOf).where((t) => t == QuestTier.easy), hasLength(2));
  expect(ids.map(_tierOf).where((t) => t == QuestTier.medium), hasLength(2));
  expect(ids.map(_tierOf).where((t) => t == QuestTier.hard), hasLength(1));
  expect(ids.take(3).map(_tierOf).toList(), [
    QuestTier.easy,
    QuestTier.medium,
    QuestTier.hard,
  ]);
  final pool = DailyQuestUnlockPool.fromPersonalLevel(effective);
  for (final id in ids) {
    final quest = questById(id)!;
    expect(quest.minimumLevel, lessThanOrEqualTo(effective));
    expect(isEligibleForDailyQuestGeneration(quest, pool), isTrue, reason: id);
  }
  final categories = ids.map(_categoryOf).toList();
  expect(
    categories.where((c) => c == QuestCategory.sessionCount).length,
    lessThanOrEqualTo(1),
  );
  expect(
    categories.where((c) => c == QuestCategory.duration).length,
    lessThanOrEqualTo(1),
  );
  expect(
    categories.where((c) => c == QuestCategory.scoreThreshold).length,
    lessThanOrEqualTo(1),
  );
}

Iterable<List<String>> _sampleBoards({
  required int currentLevel,
  int users = 40,
  int days = 14,
}) sync* {
  for (var u = 0; u < users; u++) {
    for (var day = 1; day <= days; day++) {
      yield _ids(
        userId: 'user-$u',
        dayKey: '202607${day.toString().padLeft(2, '0')}',
        currentLevel: currentLevel,
      );
    }
  }
}

/// Spreads [total] (0..12) across the four criteria so the rubric derives
/// exactly that total.
RubricAssessment _rubric(int total) {
  assert(total >= 0 && total <= 12);
  final base = total ~/ 4;
  final remainder = total % 4;
  return RubricAssessment(
    technique: base + (remainder > 0 ? 1 : 0),
    stability: base + (remainder > 1 ? 1 : 0),
    completion: base + (remainder > 2 ? 1 : 0),
    propPositioning: base,
  );
}

Session _session({
  String userId = 'u1',
  String movementName = 'Flair',
  String difficulty = 'Easy',
  int rubricTotal = 7,
  int durationSeconds = 60,
  String? createdAt,
}) {
  return Session(
    userId: userId,
    movementName: movementName,
    difficulty: difficulty,
    rubric: _rubric(rubricTotal),
    assessmentVersion: 2,
    durationSeconds: durationSeconds,
    createdAt: createdAt,
  );
}

Session _legacySession({int score = 100}) {
  return Session(
    userId: 'u1',
    movementName: 'Flair',
    difficulty: 'Easy',
    legacyScore: score,
    durationSeconds: 60,
  );
}

void main() {
  group('generateDailyQuestIds', () {
    test('always returns exactly 5 unique ids', () {
      for (var day = 1; day <= 28; day++) {
        final ids = _ids(dayKey: '202607${day.toString().padLeft(2, '0')}');
        expect(ids, hasLength(5));
        expect(ids.toSet(), hasLength(5));
      }
    });

    test('every board has exactly 2 easy, 2 medium, 1 hard quest', () {
      for (var day = 1; day <= 28; day++) {
        final ids = _ids(dayKey: '202607${day.toString().padLeft(2, '0')}');
        final tiers = ids.map(_tierOf).toList();
        expect(tiers.where((t) => t == QuestTier.easy), hasLength(2));
        expect(tiers.where((t) => t == QuestTier.medium), hasLength(2));
        expect(tiers.where((t) => t == QuestTier.hard), hasLength(1));
      }
    });

    test('never assigns more than one quest from a conflicting category', () {
      for (var day = 1; day <= 28; day++) {
        final ids = _ids(dayKey: '202607${day.toString().padLeft(2, '0')}');
        final categories = ids.map(_categoryOf).toList();
        expect(
          categories.where((c) => c == QuestCategory.sessionCount).length,
          lessThanOrEqualTo(1),
        );
        expect(
          categories.where((c) => c == QuestCategory.duration).length,
          lessThanOrEqualTo(1),
        );
        expect(
          categories.where((c) => c == QuestCategory.scoreThreshold).length,
          lessThanOrEqualTo(1),
        );
      }
    });

    test('the first 3 ids are always Easy then Medium then Hard', () {
      for (var day = 1; day <= 28; day++) {
        final ids = _ids(dayKey: '202607${day.toString().padLeft(2, '0')}');
        expect(ids.take(3).map(_tierOf).toList(), [
          QuestTier.easy,
          QuestTier.medium,
          QuestTier.hard,
        ]);
      }
    });

    test('same user, day, and level always produce the same board', () {
      final first = _ids(dayKey: '20260804', currentLevel: 5);
      final second = _ids(dayKey: '20260804', currentLevel: 5);
      expect(first, second);
    });

    test('different users can receive different boards on the same day', () {
      var foundDifference = false;
      for (var i = 0; i < 50; i++) {
        final a = _ids(userId: 'user-$i', dayKey: '20260804');
        final b = _ids(userId: 'other-$i', dayKey: '20260804');
        if (!_sameOrder(a, b)) {
          foundDifference = true;
          break;
        }
      }
      expect(foundDifference, isTrue);
    });

    test('the same user gets different boards on different days (usually)', () {
      var foundDifference = false;
      for (var day = 1; day <= 28; day++) {
        final ids = _ids(dayKey: '202607${day.toString().padLeft(2, '0')}');
        if (day > 1) {
          final prev = _ids(
            dayKey: '202607${(day - 1).toString().padLeft(2, '0')}',
          );
          if (!_sameOrder(ids, prev)) {
            foundDifference = true;
            break;
          }
        }
      }
      expect(foundDifference, isTrue);
    });

    test('clamps below Level 1 to Level 1 and Level 21+ to the full pool', () {
      expect(effectiveQuestGenerationLevel(0), 1);
      expect(effectiveQuestGenerationLevel(-4), 1);
      expect(effectiveQuestGenerationLevel(20), 20);
      expect(effectiveQuestGenerationLevel(21), 20);
      expect(effectiveQuestGenerationLevel(99), 20);

      final atOne = _ids(dayKey: '20260804', currentLevel: 1);
      expect(_ids(dayKey: '20260804', currentLevel: 0), atOne);
      expect(
        _ids(dayKey: '20260804', currentLevel: 21),
        _ids(dayKey: '20260804', currentLevel: 20),
      );
    });

    test(
      'representative levels keep a valid 2 Easy + 2 Medium + 1 Hard board',
      () {
        const levels = [1, 2, 3, 5, 6, 7, 9, 16, 17, 19, 20, 21];
        for (final level in levels) {
          for (final ids in _sampleBoards(
            currentLevel: level,
            users: 8,
            days: 7,
          )) {
            _assertBoardShape(ids, currentLevel: level);
          }
        }
      },
    );

    test(
      'Level 1 never generates content that is still locked or singleton-gated',
      () {
        const forbidden = {
          'two_movements',
          'three_movements',
          'use_shaker',
          'practice_medium_movement',
          'distinct_props_2',
          'practice_hard_movement',
          'use_bottle_and_shaker_combo',
        };
        var sawGenericHard = false;
        for (final ids in _sampleBoards(currentLevel: 1)) {
          expect(ids.toSet().intersection(forbidden), isEmpty);
          expect(
            ids.any((id) => questById(id)!.tier == QuestTier.hard),
            isTrue,
          );
          if (ids.contains('session_count_5') ||
              ids.contains('duration_30min') ||
              ids.contains('score_95')) {
            sawGenericHard = true;
          }
        }
        expect(sawGenericHard, isTrue);
      },
    );

    test('every level from 1 to 20 still generates a valid board', () {
      for (var level = 1; level <= 20; level++) {
        for (final ids in _sampleBoards(
          currentLevel: level,
          users: 4,
          days: 3,
        )) {
          _assertBoardShape(ids, currentLevel: level);
        }
      }
    });

    test(
      'Level 2 does not generate two_movements with only two unlocked identities',
      () {
        for (final ids in _sampleBoards(currentLevel: 2)) {
          expect(ids, isNot(contains('two_movements')));
          expect(ids, isNot(contains('three_movements')));
        }
      },
    );

    test(
      'two_movements becomes eligible once 3 movement identities are unlocked',
      () {
        expect(
          _sampleBoards(
            currentLevel: 3,
          ).any((ids) => ids.contains('two_movements')),
          isTrue,
        );
        for (final ids in _sampleBoards(currentLevel: 3)) {
          expect(ids, isNot(contains('three_movements')));
        }
      },
    );

    test(
      'three_movements is absent until 5 movement identities are unlocked',
      () {
        for (final ids in _sampleBoards(currentLevel: 4)) {
          expect(ids, isNot(contains('three_movements')));
        }
        expect(
          _sampleBoards(
            currentLevel: 5,
          ).any((ids) => ids.contains('three_movements')),
          isTrue,
        );
      },
    );

    test('practice_medium_movement is absent with only one Medium option', () {
      for (final ids in _sampleBoards(currentLevel: 6)) {
        expect(ids, isNot(contains('practice_medium_movement')));
      }
    });

    test(
      'practice_medium_movement becomes eligible with two Medium options',
      () {
        expect(
          _sampleBoards(
            currentLevel: 7,
          ).any((ids) => ids.contains('practice_medium_movement')),
          isTrue,
        );
      },
    );

    test(
      'Shaker and 2-prop quests stay absent with only one Shaker variant',
      () {
        for (final ids in _sampleBoards(currentLevel: 7)) {
          expect(ids, isNot(contains('use_shaker')));
          expect(ids, isNot(contains('distinct_props_2')));
        }
        for (final ids in _sampleBoards(currentLevel: 8)) {
          expect(ids, isNot(contains('use_shaker')));
          expect(ids, isNot(contains('distinct_props_2')));
        }
      },
    );

    test(
      'Shaker and 2-prop quests become eligible with two Shaker variants',
      () {
        var sawShaker = false;
        var sawDistinctProps = false;
        for (final ids in _sampleBoards(currentLevel: 9)) {
          if (ids.contains('use_shaker')) sawShaker = true;
          if (ids.contains('distinct_props_2')) sawDistinctProps = true;
        }
        expect(sawShaker, isTrue);
        expect(sawDistinctProps, isTrue);
      },
    );

    test('practice_hard_movement is absent with only one Hard option', () {
      for (final ids in _sampleBoards(currentLevel: 16)) {
        expect(ids, isNot(contains('practice_hard_movement')));
      }
    });

    test('practice_hard_movement becomes eligible with two Hard options', () {
      expect(
        _sampleBoards(
          currentLevel: 17,
        ).any((ids) => ids.contains('practice_hard_movement')),
        isTrue,
      );
    });

    test('new generation never selects the legacy combo quest', () {
      for (final level in [19, 20, 21]) {
        for (final ids in _sampleBoards(
          currentLevel: level,
          users: 80,
          days: 28,
        )) {
          expect(ids, isNot(contains('use_bottle_and_shaker_combo')));
        }
      }
    });

    test(
      'Level 20 may generate every currently eligible catalog quest except the combo',
      () {
        final pool = DailyQuestUnlockPool.fromPersonalLevel(20);
        final eligibleIds = questCatalog
            .where(
              (quest) =>
                  quest.minimumLevel <= 20 &&
                  isEligibleForDailyQuestGeneration(quest, pool),
            )
            .map((quest) => quest.id)
            .toSet();
        expect(eligibleIds, isNot(contains('use_bottle_and_shaker_combo')));
        expect(questById('use_bottle_and_shaker_combo'), isNotNull);

        final seen = <String>{};
        for (final ids in _sampleBoards(
          currentLevel: 20,
          users: 80,
          days: 28,
        )) {
          seen.addAll(ids);
        }
        expect(seen, eligibleIds);
      },
    );

    test(
      'the same user and day can receive a different board at a later level',
      () {
        var foundDifference = false;
        for (var i = 0; i < 40; i++) {
          final level1 = _ids(
            userId: 'user-$i',
            dayKey: '20260804',
            currentLevel: 1,
          );
          final level16 = _ids(
            userId: 'user-$i',
            dayKey: '20260804',
            currentLevel: 16,
          );
          if (!_sameOrder(level1, level16)) {
            foundDifference = true;
            break;
          }
        }
        expect(foundDifference, isTrue);
      },
    );
  });

  group('stableHash32', () {
    test('is deterministic and 32-bit masked', () {
      final first = stableHash32('user|20260804');
      final second = stableHash32('user|20260804');
      expect(first, second);
      expect(first, greaterThanOrEqualTo(0));
      expect(first, lessThanOrEqualTo(0xFFFFFFFF));
    });
  });

  group('sessionsWithinBoardWindow', () {
    final board = DailyQuestBoard(
      userId: 'u1',
      dayKey: '20260804',
      dayStart: DateTime.utc(2026, 8, 3, 16, 0, 0),
      questIds: const ['session_count_1'],
    );

    test('a session exactly at day_start counts', () {
      final session = _session(
        createdAt: DateTime.utc(2026, 8, 3, 16, 0, 0).toIso8601String(),
      );
      final windowed = sessionsWithinBoardWindow(board, [session]);
      expect(windowed, hasLength(1));
    });

    test('a session at day_start + 24h does not count', () {
      final session = _session(
        createdAt: DateTime.utc(2026, 8, 4, 16, 0, 0).toIso8601String(),
      );
      final windowed = sessionsWithinBoardWindow(board, [session]);
      expect(windowed, isEmpty);
    });

    test('a session before day_start does not count', () {
      final session = _session(
        createdAt: DateTime.utc(2026, 8, 3, 15, 59, 59).toIso8601String(),
      );
      final windowed = sessionsWithinBoardWindow(board, [session]);
      expect(windowed, isEmpty);
    });

    test('a session inside the window counts', () {
      final session = _session(
        createdAt: DateTime.utc(2026, 8, 4, 3, 0, 0).toIso8601String(),
      );
      final windowed = sessionsWithinBoardWindow(board, [session]);
      expect(windowed, hasLength(1));
    });

    test('a session with a missing createdAt never counts', () {
      final session = _session();
      final windowed = sessionsWithinBoardWindow(board, [session]);
      expect(windowed, isEmpty);
    });

    test('a session with an invalid createdAt never counts', () {
      final session = _session(createdAt: 'not-a-date');
      final windowed = sessionsWithinBoardWindow(board, [session]);
      expect(windowed, isEmpty);
    });
  });

  group('rubric quest evaluators', () {
    test('score_70 completes at a rubric total of 7 (Competent)', () {
      final quest = questById('score_70')!;
      expect(quest.evaluate([_session(rubricTotal: 6)]).target, 7);
      expect(quest.evaluate([_session(rubricTotal: 6)]).completed, isFalse);
      expect(quest.evaluate([_session(rubricTotal: 7)]).completed, isTrue);
    });

    test('score_85 completes at a rubric total of 10 (Proficient)', () {
      final quest = questById('score_85')!;
      expect(quest.evaluate([_session(rubricTotal: 9)]).target, 10);
      expect(quest.evaluate([_session(rubricTotal: 9)]).completed, isFalse);
      expect(quest.evaluate([_session(rubricTotal: 10)]).completed, isTrue);
    });

    test('score_95 completes only at a perfect rubric total of 12', () {
      final quest = questById('score_95')!;
      expect(quest.evaluate([_session(rubricTotal: 11)]).target, 12);
      expect(quest.evaluate([_session(rubricTotal: 11)]).completed, isFalse);
      expect(quest.evaluate([_session(rubricTotal: 12)]).completed, isTrue);
    });

    test('score quests report the best rubric total across sessions', () {
      final quest = questById('score_85')!;
      final progress = quest.evaluate([
        _session(rubricTotal: 4),
        _session(rubricTotal: 9),
        _session(rubricTotal: 6),
      ]);
      expect(progress.current, 9);
      expect(progress.completed, isFalse);
    });

    test('sessions_above_70_x2 counts Competent sessions only', () {
      final quest = questById('sessions_above_70_x2')!;
      final oneQualifies = quest.evaluate([
        _session(rubricTotal: 7),
        _session(rubricTotal: 6),
      ]);
      expect(oneQualifies.current, 1);
      expect(oneQualifies.target, 2);
      expect(oneQualifies.completed, isFalse);

      final twoQualify = quest.evaluate([
        _session(rubricTotal: 7),
        _session(rubricTotal: 12),
      ]);
      expect(twoQualify.completed, isTrue);
    });

    test('legacy percentage sessions never advance rubric quests', () {
      final legacy = [_legacySession(score: 100), _legacySession(score: 95)];
      for (final id in [
        'score_70',
        'score_85',
        'score_95',
        'sessions_above_70_x2',
      ]) {
        final progress = questById(id)!.evaluate(legacy);
        expect(progress.current, 0, reason: id);
        expect(progress.completed, isFalse, reason: id);
      }
    });
  });
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
