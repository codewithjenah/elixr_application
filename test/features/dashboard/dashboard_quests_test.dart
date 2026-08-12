import 'package:elixr_application/data/models/daily_quest_board.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/dashboard/dashboard_quests.dart';
import 'package:flutter_test/flutter_test.dart';

final _dayStart = DateTime.utc(2026, 8, 3, 16, 0, 0); // Manila 2026-08-04 00:00
const _insideWindow = '2026-08-04T03:00:00.000Z';
const _outsideWindow = '2026-08-02T03:00:00.000Z';

// 2 easy + 2 medium + 1 hard, ordered so the first 3 are one of each tier
// (mirrors what generateDailyQuestIds always produces).
final _board = DailyQuestBoard(
  userId: 'u1',
  dayKey: '20260804',
  dayStart: _dayStart,
  questIds: const [
    'two_movements', // easy (active)
    'distinct_props_2', // medium (active)
    'practice_hard_movement', // hard (active)
    'use_shaker', // easy (reserve)
    'three_movements', // medium (reserve)
  ],
);

Session _session({
  String movementName = 'Flair',
  int score = 70,
  String createdAt = _insideWindow,
}) {
  return Session(
    userId: 'u1',
    movementName: movementName,
    difficulty: 'Easy',
    legacyScore: score,
    durationSeconds: 60,
    createdAt: createdAt,
  );
}

void main() {
  group('buildActiveDashboardQuests', () {
    test('returns at most 3 active quests, in board order', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: const [],
      );

      expect(quests.map((q) => q.id), [
        'two_movements',
        'distinct_props_2',
        'practice_hard_movement',
      ]);
    });

    test(
      'claiming an active quest removes it and promotes the next reserve quest',
      () {
        final quests = buildActiveDashboardQuests(
          board: _board,
          claimedQuestIds: const {'two_movements'},
          sessions: const [],
        );

        expect(quests.map((q) => q.id), [
          'distinct_props_2',
          'practice_hard_movement',
          'use_shaker',
        ]);
      },
    );

    test('claiming multiple quests keeps promoting in board order', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {'two_movements', 'distinct_props_2'},
        sessions: const [],
      );

      expect(quests.map((q) => q.id), [
        'practice_hard_movement',
        'use_shaker',
        'three_movements',
      ]);
    });

    test('returns no quests once every board quest is claimed', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: _board.questIds.toSet(),
        sessions: const [],
      );

      expect(quests, isEmpty);
    });

    test('progress reflects current/target and completion', () {
      final incomplete = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: [_session(movementName: 'Flair')],
      );
      final twoMovements = incomplete.firstWhere(
        (q) => q.id == 'two_movements',
      );
      expect(twoMovements.current, 1);
      expect(twoMovements.target, 2);
      expect(twoMovements.completed, isFalse);

      final complete = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: [
          _session(movementName: 'Flair'),
          _session(movementName: 'Spin'),
        ],
      );
      final twoMovementsDone = complete.firstWhere(
        (q) => q.id == 'two_movements',
      );
      expect(twoMovementsDone.current, 2);
      expect(twoMovementsDone.completed, isTrue);
    });

    test('sessions outside the board Manila window are ignored', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: [
          _session(movementName: 'Flair', createdAt: _outsideWindow),
          _session(movementName: 'Spin', createdAt: _outsideWindow),
        ],
      );

      final twoMovements = quests.firstWhere((q) => q.id == 'two_movements');
      expect(twoMovements.current, 0);
      expect(twoMovements.completed, isFalse);
    });

    test('xp comes from the tier, not a caller-supplied value', () {
      final quests = buildActiveDashboardQuests(
        board: _board,
        claimedQuestIds: const {},
        sessions: const [],
      );

      final easy = quests.firstWhere((q) => q.id == 'two_movements');
      final medium = quests.firstWhere((q) => q.id == 'distinct_props_2');
      final hard = quests.firstWhere((q) => q.id == 'practice_hard_movement');
      expect(easy.xp, 10);
      expect(medium.xp, 15);
      expect(hard.xp, 20);
    });
  });

  group('isDailyBoardComplete', () {
    test('is false until every quest id is claimed', () {
      expect(
        isDailyBoardComplete(board: _board, claimedQuestIds: {'two_movements'}),
        isFalse,
      );
    });

    test('is true once all 5 quest ids are claimed', () {
      expect(
        isDailyBoardComplete(
          board: _board,
          claimedQuestIds: _board.questIds.toSet(),
        ),
        isTrue,
      );
    });
  });
}
