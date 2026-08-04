import 'package:elixr_application/data/models/daily_quest.dart';
import 'package:elixr_application/data/models/daily_quest_board.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

QuestTier _tierOf(String id) => questById(id)!.tier;
QuestCategory _categoryOf(String id) => questById(id)!.category;

Session _session({
  String userId = 'u1',
  String movementName = 'Flair',
  String difficulty = 'Easy',
  int score = 70,
  int durationSeconds = 60,
  String? createdAt,
}) {
  return Session(
    userId: userId,
    movementName: movementName,
    difficulty: difficulty,
    score: score,
    durationSeconds: durationSeconds,
    createdAt: createdAt,
  );
}

void main() {
  group('generateDailyQuestIds', () {
    test('always returns exactly 5 unique ids', () {
      for (var day = 1; day <= 28; day++) {
        final ids = generateDailyQuestIds(
          userId: 'user-1',
          dayKey: '202607${day.toString().padLeft(2, '0')}',
        );
        expect(ids, hasLength(5));
        expect(ids.toSet(), hasLength(5));
      }
    });

    test('every board has exactly 2 easy, 2 medium, 1 hard quest', () {
      for (var day = 1; day <= 28; day++) {
        final ids = generateDailyQuestIds(
          userId: 'user-1',
          dayKey: '202607${day.toString().padLeft(2, '0')}',
        );
        final tiers = ids.map(_tierOf).toList();
        expect(tiers.where((t) => t == QuestTier.easy), hasLength(2));
        expect(tiers.where((t) => t == QuestTier.medium), hasLength(2));
        expect(tiers.where((t) => t == QuestTier.hard), hasLength(1));
      }
    });

    test('never assigns more than one quest from a conflicting category', () {
      for (var day = 1; day <= 28; day++) {
        final ids = generateDailyQuestIds(
          userId: 'user-1',
          dayKey: '202607${day.toString().padLeft(2, '0')}',
        );
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

    test(
      'the first 3 ids are always exactly one easy, one medium, one hard',
      () {
        for (var day = 1; day <= 28; day++) {
          final ids = generateDailyQuestIds(
            userId: 'user-1',
            dayKey: '202607${day.toString().padLeft(2, '0')}',
          );
          final activeTiers = ids.take(3).map(_tierOf).toSet();
          expect(activeTiers, {
            QuestTier.easy,
            QuestTier.medium,
            QuestTier.hard,
          });
        }
      },
    );

    test('same user and day always produce the same board', () {
      final first = generateDailyQuestIds(userId: 'user-1', dayKey: '20260804');
      final second = generateDailyQuestIds(
        userId: 'user-1',
        dayKey: '20260804',
      );
      expect(first, second);
    });

    test('different users can receive different boards on the same day', () {
      var foundDifference = false;
      for (var i = 0; i < 50; i++) {
        final a = generateDailyQuestIds(userId: 'user-$i', dayKey: '20260804');
        final b = generateDailyQuestIds(userId: 'other-$i', dayKey: '20260804');
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
        final ids = generateDailyQuestIds(
          userId: 'user-1',
          dayKey: '202607${day.toString().padLeft(2, '0')}',
        );
        if (day > 1) {
          final prev = generateDailyQuestIds(
            userId: 'user-1',
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
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
