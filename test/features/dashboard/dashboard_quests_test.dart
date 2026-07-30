import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/dashboard/dashboard_quests.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = 'user-1';

Session _session({
  String movementName = 'Flair',
  int score = 70,
  int durationSeconds = 60,
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: 'beginner',
    score: score,
    durationSeconds: durationSeconds,
  );
}

void main() {
  group('buildDailyDashboardQuests', () {
    test('returns the full quest pool with three daily focus quests', () {
      final quests = buildDailyDashboardQuests(
        sessionsToday: const [],
        streakDays: 0,
        date: DateTime(2026, 7, 30),
      );

      expect(quests, hasLength(7));
      expect(quests.where((quest) => quest.isDailyFocus), hasLength(3));
    });

    test('same date returns the same quest IDs in the same order', () {
      final first = buildDailyDashboardQuests(
        sessionsToday: const [],
        streakDays: 0,
        date: DateTime(2026, 7, 30),
      );
      final second = buildDailyDashboardQuests(
        sessionsToday: const [],
        streakDays: 0,
        date: DateTime(2026, 7, 30),
      );

      expect(first.map((quest) => quest.id), second.map((quest) => quest.id));
    });

    test(
      'different times on the same calendar day return the same quest IDs',
      () {
        final morning = buildDailyDashboardQuests(
          sessionsToday: const [],
          streakDays: 0,
          date: DateTime(2026, 7, 30, 8, 15),
        );
        final evening = buildDailyDashboardQuests(
          sessionsToday: const [],
          streakDays: 0,
          date: DateTime(2026, 7, 30, 22, 45),
        );

        expect(
          morning.map((quest) => quest.id),
          evening.map((quest) => quest.id),
        );
      },
    );

    test('selection never includes both session-count quests', () {
      for (var day = 1; day <= 31; day++) {
        final quests = buildDailyDashboardQuests(
          sessionsToday: const [],
          streakDays: 0,
          date: DateTime(2026, 7, day),
        );
        final ids = quests
            .where((quest) => quest.isDailyFocus)
            .map((quest) => quest.id)
            .toSet();

        expect(
          ids.contains('complete_one_session') &&
              ids.contains('complete_three_sessions'),
          isFalse,
        );
      }
    });

    test('selection never includes both score quests', () {
      for (var day = 1; day <= 31; day++) {
        final quests = buildDailyDashboardQuests(
          sessionsToday: const [],
          streakDays: 0,
          date: DateTime(2026, 7, day),
        );
        final ids = quests
            .where((quest) => quest.isDailyFocus)
            .map((quest) => quest.id)
            .toSet();

        expect(ids.contains('score_80') && ids.contains('score_90'), isFalse);
      }
    });

    test('complete 1 session quest completes when sessions exist', () {
      final quests = _questsForId(
        questId: 'complete_one_session',
        sessionsToday: [_session()],
        streakDays: 0,
      );

      expect(quests.single.completed, isTrue);
    });

    test('complete 3 sessions quest completes at three sessions', () {
      final quests = _questsForId(
        questId: 'complete_three_sessions',
        sessionsToday: [
          _session(),
          _session(movementName: 'Spin'),
          _session(movementName: 'Toss'),
        ],
        streakDays: 0,
      );

      expect(quests.single.completed, isTrue);
    });

    test('score 80 quest completes at 80 or higher', () {
      final quests = _questsForId(
        questId: 'score_80',
        sessionsToday: [_session(score: 80)],
        streakDays: 0,
      );

      expect(quests.single.completed, isTrue);
    });

    test('score 90 quest completes at 90 or higher', () {
      final quests = _questsForId(
        questId: 'score_90',
        sessionsToday: [_session(score: 90)],
        streakDays: 0,
      );

      expect(quests.single.completed, isTrue);
    });

    test('movement quest counts distinct movements case-insensitively', () {
      final sameMovement = _questsForId(
        questId: 'two_movements',
        sessionsToday: [
          _session(movementName: 'Flair'),
          _session(movementName: ' flair '),
        ],
        streakDays: 0,
      );
      final differentMovements = _questsForId(
        questId: 'two_movements',
        sessionsToday: [
          _session(movementName: 'Flair'),
          _session(movementName: ' SPIN '),
        ],
        streakDays: 0,
      );

      expect(sameMovement.single.completed, isFalse);
      expect(differentMovements.single.completed, isTrue);
    });

    test('movement quest ignores empty movement names', () {
      final quests = _questsForId(
        questId: 'two_movements',
        sessionsToday: [
          _session(movementName: 'Flair'),
          _session(movementName: '   '),
        ],
        streakDays: 0,
      );

      expect(quests.single.completed, isFalse);
    });

    test('training duration quest completes at 120 total seconds', () {
      final quests = _questsForId(
        questId: 'train_two_minutes',
        sessionsToday: [
          _session(durationSeconds: 70),
          _session(durationSeconds: 50),
        ],
        streakDays: 0,
      );

      expect(quests.single.completed, isTrue);
    });

    test('negative durations do not reduce the total training time', () {
      final quests = _questsForId(
        questId: 'train_two_minutes',
        sessionsToday: [
          _session(durationSeconds: 120),
          _session(durationSeconds: -30),
        ],
        streakDays: 0,
      );

      expect(quests.single.completed, isTrue);
    });

    test('three-day streak quest completes at three or more streak days', () {
      final quests = _questsForId(
        questId: 'three_day_streak',
        sessionsToday: const [],
        streakDays: 3,
      );

      expect(quests.single.completed, isTrue);
    });

    test('includes every quest from the pool', () {
      final quests = buildDailyDashboardQuests(
        sessionsToday: const [],
        streakDays: 0,
        date: DateTime(2026, 7, 30),
      );

      expect(quests.map((quest) => quest.id).toSet(), {
        'complete_one_session',
        'complete_three_sessions',
        'score_80',
        'score_90',
        'two_movements',
        'train_two_minutes',
        'three_day_streak',
      });
    });

    test('non-daily quests still track completion progress', () {
      final date = _dateExcludingQuest('complete_one_session');
      final quests = buildDailyDashboardQuests(
        sessionsToday: [_session()],
        streakDays: 0,
        date: date,
      );
      final completeOne = quests.singleWhere(
        (quest) => quest.id == 'complete_one_session',
      );

      expect(completeOne.isDailyFocus, isFalse);
      expect(completeOne.completed, isTrue);
    });

    test('completed quests across the full pool are all counted', () {
      final date = _dateExcludingQuest('score_80');
      final quests = buildDailyDashboardQuests(
        sessionsToday: [_session(score: 85)],
        streakDays: 0,
        date: date,
      );
      final score80 = quests.singleWhere((quest) => quest.id == 'score_80');

      expect(score80.isDailyFocus, isFalse);
      expect(score80.completed, isTrue);
      expect(quests.where((quest) => quest.completed).length, greaterThan(1));
    });

    test('progress conditions update when sessions are added', () {
      final date = _dateIncludingQuest('complete_one_session');
      final before = buildDailyDashboardQuests(
        sessionsToday: const [],
        streakDays: 0,
        date: date,
      );
      final after = buildDailyDashboardQuests(
        sessionsToday: [_session(score: 85, movementName: 'Flair')],
        streakDays: 0,
        date: date,
      );

      expect(before.map((quest) => quest.id), after.map((quest) => quest.id));

      final beforeCompleteOne = before.singleWhere(
        (quest) => quest.id == 'complete_one_session' && quest.isDailyFocus,
      );
      final afterCompleteOne = after.singleWhere(
        (quest) => quest.id == 'complete_one_session' && quest.isDailyFocus,
      );

      expect(beforeCompleteOne.completed, isFalse);
      expect(afterCompleteOne.completed, isTrue);

      final beforeScore80 = before.where(
        (quest) => quest.id == 'score_80' && quest.isDailyFocus,
      );
      final afterScore80 = after.where(
        (quest) => quest.id == 'score_80' && quest.isDailyFocus,
      );
      if (beforeScore80.isNotEmpty) {
        expect(beforeScore80.single.completed, isFalse);
        expect(afterScore80.single.completed, isTrue);
      }
    });
  });
}

List<DashboardQuest> _questsForId({
  required String questId,
  required List<Session> sessionsToday,
  required int streakDays,
}) {
  final date = _dateIncludingQuest(questId);
  final quests = buildDailyDashboardQuests(
    sessionsToday: sessionsToday,
    streakDays: streakDays,
    date: date,
  );
  return quests.where((quest) => quest.id == questId).toList();
}

DateTime _dateIncludingQuest(String questId) {
  for (var day = 1; day <= 366; day++) {
    final date = DateTime(2026, 1, 1).add(Duration(days: day - 1));
    final ids = selectDailyQuestIds(date);
    if (ids.contains(questId)) {
      return date;
    }
  }

  fail('No daily selection includes quest id $questId');
}

DateTime _dateExcludingQuest(String questId) {
  for (var day = 1; day <= 366; day++) {
    final date = DateTime(2026, 1, 1).add(Duration(days: day - 1));
    final ids = selectDailyQuestIds(date);
    if (!ids.contains(questId)) {
      return date;
    }
  }

  fail('No daily selection excludes quest id $questId');
}
