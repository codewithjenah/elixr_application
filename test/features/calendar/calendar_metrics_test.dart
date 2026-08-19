import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/calendar/models/calendar_day_summary.dart';
import 'package:elixr_application/features/calendar/utils/calendar_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = 'user-1';

/// Distributes a 0..12 total across the four criteria (each 0..3).
RubricAssessment _rubric(int total) {
  final scores = <int>[0, 0, 0, 0];
  var remaining = total.clamp(0, 12);
  for (var i = 0; i < scores.length && remaining > 0; i++) {
    final value = remaining >= 3 ? 3 : remaining;
    scores[i] = value;
    remaining -= value;
  }
  return RubricAssessment(
    technique: scores[0],
    stability: scores[1],
    completion: scores[2],
    propPositioning: scores[3],
  );
}

/// Assessment V2 fixture.
Session _session({
  String? createdAt,
  int rubricTotal = 8,
  int durationSeconds = 60,
  String difficulty = 'Easy',
  String movementName = 'Flair',
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: difficulty,
    rubric: _rubric(rubricTotal),
    assessmentVersion: 2,
    durationSeconds: durationSeconds,
    createdAt: createdAt,
  );
}

/// Legacy Assessment V1 fixture (0..100 percentage).
Session _legacySession({
  String? createdAt,
  int legacyScore = 80,
  int durationSeconds = 60,
  String difficulty = 'Easy',
  String movementName = 'Flair',
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: difficulty,
    legacyScore: legacyScore,
    durationSeconds: durationSeconds,
    createdAt: createdAt,
  );
}

void main() {
  group('parseSessionLocalDate', () {
    test('parses a valid timestamp to local date-only', () {
      final session = _session(createdAt: '2026-08-02T15:30:00.000');
      expect(parseSessionLocalDate(session), DateTime(2026, 8, 2));
    });

    test('returns null for a null timestamp', () {
      expect(parseSessionLocalDate(_session()), isNull);
    });

    test('returns null for an invalid timestamp', () {
      expect(parseSessionLocalDate(_session(createdAt: 'not-a-date')), isNull);
    });

    test('normalizes timestamps with time components to date-only', () {
      final morning = parseSessionLocalDate(
        _session(createdAt: '2026-08-02T01:00:00.000'),
      );
      final evening = parseSessionLocalDate(
        _session(createdAt: '2026-08-02T23:59:59.000'),
      );
      expect(morning, DateTime(2026, 8, 2));
      expect(evening, DateTime(2026, 8, 2));
    });
  });

  group('groupSessionsByDate', () {
    test('groups multiple sessions on the same local date', () {
      final sessions = [
        _session(createdAt: '2026-08-02T09:00:00.000', rubricTotal: 7),
        _session(createdAt: '2026-08-02T18:00:00.000', rubricTotal: 9),
      ];
      final grouped = groupSessionsByDate(sessions);
      expect(grouped.keys, [DateTime(2026, 8, 2)]);
      expect(grouped[DateTime(2026, 8, 2)]!.sessionCount, 2);
    });

    test('groups different dates separately', () {
      final sessions = [
        _session(createdAt: '2026-08-01T12:00:00.000'),
        _session(createdAt: '2026-08-02T12:00:00.000'),
      ];
      final grouped = groupSessionsByDate(sessions);
      expect(grouped.keys.toSet(), {
        DateTime(2026, 8, 1),
        DateTime(2026, 8, 2),
      });
    });

    test('excludes null and invalid timestamps', () {
      final sessions = [
        _session(),
        _session(createdAt: 'bad'),
        _session(createdAt: '2026-08-02T12:00:00.000'),
      ];
      final grouped = groupSessionsByDate(sessions);
      expect(grouped.length, 1);
      expect(grouped[DateTime(2026, 8, 2)]!.sessionCount, 1);
    });
  });

  group('CalendarDaySummary metrics', () {
    test(
      'computes count, rubric average, best, duration, and difficulties',
      () {
        final summary = CalendarDaySummary(
          date: DateTime(2026, 8, 2),
          sessions: [
            _session(
              createdAt: '2026-08-02T09:00:00.000',
              rubricTotal: 6,
              durationSeconds: 40,
              difficulty: 'Easy',
            ),
            _session(
              createdAt: '2026-08-02T18:00:00.000',
              rubricTotal: 10,
              durationSeconds: 80,
              difficulty: 'Hard',
            ),
          ],
        );

        expect(summary.sessionCount, 2);
        expect(summary.rubricSessionCount, 2);
        expect(summary.averageRubricTotal, 8);
        expect(summary.bestRubricTotal, 10);
        expect(summary.hasRubricData, isTrue);
        expect(summary.preferredAverage, 8);
        expect(summary.preferredBest, 10);
        expect(summary.totalDurationSeconds, 120);
        expect(summary.difficulties, {'Easy', 'Hard'});
      },
    );

    test('keeps legacy scores in their own cohort', () {
      final summary = CalendarDaySummary(
        date: DateTime(2026, 8, 2),
        sessions: [
          _legacySession(createdAt: '2026-08-02T09:00:00.000', legacyScore: 70),
          _legacySession(createdAt: '2026-08-02T18:00:00.000', legacyScore: 90),
        ],
      );

      expect(summary.rubricSessionCount, 0);
      expect(summary.averageRubricTotal, isNull);
      expect(summary.bestRubricTotal, isNull);
      expect(summary.legacySessionCount, 2);
      expect(summary.averageLegacyScore, 80);
      expect(summary.bestLegacyScore, 90);
      expect(summary.hasRubricData, isFalse);
      expect(summary.preferredAverage, 80);
    });

    test('mixed days never blend the two scales', () {
      final summary = CalendarDaySummary(
        date: DateTime(2026, 8, 2),
        sessions: [
          _session(createdAt: '2026-08-02T09:00:00.000', rubricTotal: 6),
          _legacySession(
            createdAt: '2026-08-02T18:00:00.000',
            legacyScore: 100,
          ),
        ],
      );

      expect(summary.sessionCount, 2);
      expect(summary.averageRubricTotal, 6);
      expect(summary.averageLegacyScore, 100);
      expect(summary.preferredAverage, 6);
      expect(summary.preferredBest, 6);
    });

    test('returns null averages and best results when empty', () {
      final summary = CalendarDaySummary(
        date: DateTime(2026, 8, 2),
        sessions: const [],
      );
      expect(summary.sessionCount, 0);
      expect(summary.averageRubricTotal, isNull);
      expect(summary.bestRubricTotal, isNull);
      expect(summary.averageLegacyScore, isNull);
      expect(summary.bestLegacyScore, isNull);
      expect(summary.preferredAverage, isNull);
      expect(summary.totalDurationSeconds, 0);
      expect(summary.difficulties, isEmpty);
    });
  });

  group('practicedDates', () {
    test('returns unique local calendar dates', () {
      final dates = practicedDates([
        _session(createdAt: '2026-08-01T10:00:00.000'),
        _session(createdAt: '2026-08-01T22:00:00.000'),
        _session(createdAt: '2026-08-02T10:00:00.000'),
        _session(createdAt: 'bad'),
      ]);
      expect(dates, {DateTime(2026, 8, 1), DateTime(2026, 8, 2)});
    });
  });

  group('currentStreak', () {
    final today = DateTime(2026, 8, 2);

    test('counts a streak ending today', () {
      expect(
        currentStreak({
          DateTime(2026, 7, 31),
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 2),
        }, referenceDate: today),
        3,
      );
    });

    test('keeps a streak active when latest practice was yesterday', () {
      expect(
        currentStreak({
          DateTime(2026, 7, 31),
          DateTime(2026, 8, 1),
        }, referenceDate: today),
        2,
      );
    });

    test('returns zero when latest practice is earlier than yesterday', () {
      expect(currentStreak({DateTime(2026, 7, 30)}, referenceDate: today), 0);
    });

    test('counts duplicate same-day sessions once', () {
      expect(
        currentStreak(
          practicedDates([
            _session(createdAt: '2026-08-01T09:00:00.000'),
            _session(createdAt: '2026-08-01T18:00:00.000'),
            _session(createdAt: '2026-08-02T09:00:00.000'),
            _session(createdAt: '2026-08-02T18:00:00.000'),
          ]),
          referenceDate: today,
        ),
        2,
      );
    });

    test('breaks when a day is missing', () {
      expect(
        currentStreak({
          DateTime(2026, 7, 30),
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 2),
        }, referenceDate: today),
        2,
      );
    });

    test('handles month boundaries', () {
      expect(
        currentStreak({
          DateTime(2026, 7, 31),
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 2),
        }, referenceDate: today),
        3,
      );
    });

    test('handles year boundaries', () {
      expect(
        currentStreak({
          DateTime(2025, 12, 31),
          DateTime(2026, 1, 1),
        }, referenceDate: DateTime(2026, 1, 1)),
        2,
      );
    });

    test('does not extend streak with future practice dates', () {
      expect(
        currentStreak({
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 2),
          DateTime(2026, 8, 3),
        }, referenceDate: today),
        2,
      );
    });

    test('returns zero for an empty set', () {
      expect(currentStreak({}, referenceDate: today), 0);
    });
  });

  group('longestStreak', () {
    test('finds the longest consecutive run', () {
      expect(
        longestStreak({
          DateTime(2026, 8, 1),
          DateTime(2026, 8, 2),
          DateTime(2026, 8, 4),
          DateTime(2026, 8, 5),
          DateTime(2026, 8, 6),
        }),
        3,
      );
    });

    test('returns zero when empty', () {
      expect(longestStreak({}), 0);
    });
  });

  group('monthly counts', () {
    final sessions = [
      _session(createdAt: '2026-07-31T12:00:00.000'),
      _session(createdAt: '2026-08-01T12:00:00.000'),
      _session(createdAt: '2026-08-01T18:00:00.000'),
      _session(createdAt: '2026-08-02T12:00:00.000'),
      _session(createdAt: '2026-09-01T12:00:00.000'),
    ];

    test('counts monthly sessions', () {
      expect(monthlySessionCount(sessions, year: 2026, month: 8), 3);
    });

    test('counts monthly active days', () {
      expect(monthlyActiveDayCount(sessions, year: 2026, month: 8), 2);
    });
  });

  group('bestTrainingDay', () {
    test('prefers highest average rubric total', () {
      final grouped = groupSessionsByDate([
        _session(createdAt: '2026-08-01T12:00:00.000', rubricTotal: 11),
        _session(createdAt: '2026-08-02T12:00:00.000', rubricTotal: 8),
        _session(createdAt: '2026-08-02T13:00:00.000', rubricTotal: 8),
      ]);
      final best = bestTrainingDay(grouped, year: 2026, month: 8);
      expect(best?.date, DateTime(2026, 8, 1));
    });

    test('breaks average ties with highest individual total', () {
      final grouped = groupSessionsByDate([
        _session(createdAt: '2026-08-01T12:00:00.000', rubricTotal: 7),
        _session(createdAt: '2026-08-01T13:00:00.000', rubricTotal: 9),
        _session(createdAt: '2026-08-02T12:00:00.000', rubricTotal: 8),
        _session(createdAt: '2026-08-02T13:00:00.000', rubricTotal: 8),
      ]);
      final best = bestTrainingDay(grouped, year: 2026, month: 8);
      expect(best?.date, DateTime(2026, 8, 1));
      expect(best?.bestRubricTotal, 9);
    });

    test('breaks result ties with session count', () {
      final grouped = groupSessionsByDate([
        _session(createdAt: '2026-08-01T12:00:00.000', rubricTotal: 8),
        _session(createdAt: '2026-08-02T12:00:00.000', rubricTotal: 8),
        _session(createdAt: '2026-08-02T13:00:00.000', rubricTotal: 8),
      ]);
      final best = bestTrainingDay(grouped, year: 2026, month: 8);
      expect(best?.date, DateTime(2026, 8, 2));
      expect(best?.sessionCount, 2);
    });

    test('breaks remaining ties with most recent date', () {
      final grouped = groupSessionsByDate([
        _session(createdAt: '2026-08-01T12:00:00.000', rubricTotal: 8),
        _session(createdAt: '2026-08-03T12:00:00.000', rubricTotal: 8),
      ]);
      final best = bestTrainingDay(grouped, year: 2026, month: 8);
      expect(best?.date, DateTime(2026, 8, 3));
    });

    test('rubric days rank ahead of legacy-only days', () {
      final grouped = groupSessionsByDate([
        // A perfect legacy percentage must not outrank a modest rubric total.
        _legacySession(createdAt: '2026-08-01T12:00:00.000', legacyScore: 100),
        _session(createdAt: '2026-08-02T12:00:00.000', rubricTotal: 4),
      ]);
      final best = bestTrainingDay(grouped, year: 2026, month: 8);
      expect(best?.date, DateTime(2026, 8, 2));
      expect(best?.hasRubricData, isTrue);
    });

    test('falls back to legacy days when no rubric day exists', () {
      final grouped = groupSessionsByDate([
        _legacySession(createdAt: '2026-08-01T12:00:00.000', legacyScore: 60),
        _legacySession(createdAt: '2026-08-02T12:00:00.000', legacyScore: 90),
      ]);
      final best = bestTrainingDay(grouped, year: 2026, month: 8);
      expect(best?.date, DateTime(2026, 8, 2));
      expect(best?.hasRubricData, isFalse);
    });

    test('returns null when the month has no activity', () {
      expect(bestTrainingDay({}, year: 2026, month: 8), isNull);
    });
  });

  group('monthGridDates', () {
    test('returns Monday-first dates including adjacent months', () {
      // August 2026 starts on Saturday.
      final dates = monthGridDates(2026, 8);
      expect(dates.first, DateTime(2026, 7, 27)); // Monday
      expect(dates.first.weekday, DateTime.monday);
      expect(dates.length % 7, 0);
      expect(dates.contains(DateTime(2026, 8, 1)), isTrue);
      expect(dates.contains(DateTime(2026, 8, 31)), isTrue);
      expect(dates.last.weekday, DateTime.sunday);
    });
  });

  group('parseCalendarQueryDate', () {
    test('parses a valid YYYY-MM-DD value', () {
      expect(parseCalendarQueryDate('2026-08-02'), DateTime(2026, 8, 2));
    });

    test('returns null for invalid values', () {
      expect(parseCalendarQueryDate(null), isNull);
      expect(parseCalendarQueryDate(''), isNull);
      expect(parseCalendarQueryDate('08-02-2026'), isNull);
      expect(parseCalendarQueryDate('2026-13-01'), isNull);
      expect(parseCalendarQueryDate('not-a-date'), isNull);
    });

    test('round-trips a civil date through formatCalendarQueryDate', () {
      expect(formatCalendarQueryDate(DateTime(2026, 8, 19)), '2026-08-19');
      expect(formatCalendarQueryDate(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('formatCalendarDuration', () {
    test('formats readable durations', () {
      expect(formatCalendarDuration(42), '42 sec');
      expect(formatCalendarDuration(80), '1 min 20 sec');
      expect(formatCalendarDuration(485), '8 min 05 sec');
      expect(formatCalendarDuration(3840), '1 hr 04 min');
    });
  });

  group('clampSelectedDay', () {
    test('preserves day number within the target month', () {
      expect(
        clampSelectedDay(DateTime(2026, 1, 15), year: 2026, month: 2),
        DateTime(2026, 2, 15),
      );
    });

    test('clamps January 31 into February', () {
      expect(
        clampSelectedDay(DateTime(2026, 1, 31), year: 2026, month: 2),
        DateTime(2026, 2, 28),
      );
    });
  });
}
