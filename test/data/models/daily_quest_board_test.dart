import 'package:elixr_application/data/models/daily_quest.dart';
import 'package:elixr_application/data/models/daily_quest_board.dart';
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
  for (final id in ids) {
    expect(questById(id)!.minimumLevel, lessThanOrEqualTo(effective));
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

    test('clamps below Level 1 to Level 1 and Level 17+ to the full pool', () {
      expect(effectiveQuestGenerationLevel(0), 1);
      expect(effectiveQuestGenerationLevel(-4), 1);
      expect(effectiveQuestGenerationLevel(16), 16);
      expect(effectiveQuestGenerationLevel(17), 16);
      expect(effectiveQuestGenerationLevel(99), 16);

      final atOne = _ids(dayKey: '20260804', currentLevel: 1);
      expect(_ids(dayKey: '20260804', currentLevel: 0), atOne);
      expect(
        _ids(dayKey: '20260804', currentLevel: 17),
        _ids(dayKey: '20260804', currentLevel: 16),
      );
    });

    test(
      'representative levels keep a valid 2 Easy + 2 Medium + 1 Hard board',
      () {
        const levels = [1, 2, 3, 5, 6, 13, 16, 17];
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

    test('Level 1 never generates progression-gated quests', () {
      const forbidden = {
        'two_movements',
        'three_movements',
        'use_shaker',
        'practice_medium_movement',
        'distinct_props_2',
        'practice_hard_movement',
        'use_bottle_and_shaker_combo',
      };
      for (final ids in _sampleBoards(currentLevel: 1)) {
        expect(ids.toSet().intersection(forbidden), isEmpty);
      }
    });

    test(
      'Level 2 may generate two_movements but not Level 3+ gated quests',
      () {
        const stillForbidden = {
          'three_movements',
          'use_shaker',
          'practice_medium_movement',
          'distinct_props_2',
          'practice_hard_movement',
          'use_bottle_and_shaker_combo',
        };
        var sawTwoMovements = false;
        for (final ids in _sampleBoards(currentLevel: 2)) {
          expect(ids.toSet().intersection(stillForbidden), isEmpty);
          if (ids.contains('two_movements')) sawTwoMovements = true;
        }
        expect(sawTwoMovements, isTrue);
      },
    );

    test('Level 3 may generate three_movements', () {
      expect(
        _sampleBoards(
          currentLevel: 3,
        ).any((ids) => ids.contains('three_movements')),
        isTrue,
      );
    });

    test('Level 5 may generate practice_medium_movement', () {
      expect(
        _sampleBoards(
          currentLevel: 5,
        ).any((ids) => ids.contains('practice_medium_movement')),
        isTrue,
      );
    });

    test('Level 6 may generate use_shaker and distinct_props_2', () {
      var sawShaker = false;
      var sawDistinctProps = false;
      for (final ids in _sampleBoards(currentLevel: 6)) {
        if (ids.contains('use_shaker')) sawShaker = true;
        if (ids.contains('distinct_props_2')) sawDistinctProps = true;
      }
      expect(sawShaker, isTrue);
      expect(sawDistinctProps, isTrue);
    });

    test('Level 13 may generate practice_hard_movement', () {
      expect(
        _sampleBoards(
          currentLevel: 13,
        ).any((ids) => ids.contains('practice_hard_movement')),
        isTrue,
      );
    });

    test(
      'Level 16 may generate the full catalog including the combo quest',
      () {
        final catalogIds = questCatalog.map((q) => q.id).toSet();
        final seen = <String>{};
        for (final ids in _sampleBoards(
          currentLevel: 16,
          users: 80,
          days: 28,
        )) {
          seen.addAll(ids);
        }
        expect(seen, catalogIds);
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
    test('score_70 completes at a rubric total of 7 (Good)', () {
      final quest = questById('score_70')!;
      expect(quest.title, 'Reach Good in a Session');
      expect(quest.evaluate([_session(rubricTotal: 6)]).target, 7);
      expect(quest.evaluate([_session(rubricTotal: 6)]).completed, isFalse);
      expect(quest.evaluate([_session(rubricTotal: 7)]).completed, isTrue);
    });

    test('score_85 completes at a rubric total of 10 (Great)', () {
      final quest = questById('score_85')!;
      expect(quest.title, 'Reach Great in a Session');
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

    test('sessions_above_70_x2 counts Good sessions only', () {
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
