import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_plan.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/calendar/models/training_day_status.dart';
import 'package:elixr_application/features/calendar/utils/training_plan_progress.dart';
import 'package:elixr_core/utils/manila_day.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = 'user-1';
const _today = '20260819';

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

Session _session({
  required String createdAt,
  String movementName = 'Hand Stall',
  String difficulty = 'Medium',
  TrainingProp propType = TrainingProp.bottle,
  int durationSeconds = 300,
  int rubricTotal = 8,
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: difficulty,
    rubric: _rubric(rubricTotal),
    assessmentVersion: 2,
    durationSeconds: durationSeconds,
    createdAt: createdAt,
    propType: propType,
  );
}

TrainingPlan _training({
  required String dayKey,
  String movementName = 'Hand Stall',
  String difficulty = 'Medium',
  TrainingProp propType = TrainingProp.bottle,
  int minutes = 10,
}) {
  return TrainingPlan.training(
    userId: _userId,
    dayKey: dayKey,
    movementName: movementName,
    difficulty: difficulty,
    propType: propType,
    targetDurationMinutes: minutes,
  );
}

void main() {
  group('parseSessionManilaDayKey', () {
    test('maps an instant just before Manila midnight to the previous day', () {
      // 2026-08-18 15:30Z = 23:30 Manila on the 18th.
      final session = _session(createdAt: '2026-08-18T15:30:00.000Z');
      expect(parseSessionManilaDayKey(session), '20260818');
    });

    test('maps an instant after Manila midnight onto the next civil day', () {
      // 2026-08-18 16:30Z = 00:30 Manila on the 19th.
      final session = _session(createdAt: '2026-08-18T16:30:00.000Z');
      expect(parseSessionManilaDayKey(session), '20260819');
    });
  });

  group('deriveTrainingDayStatus', () {
    test('future plan is Planned', () {
      expect(
        deriveTrainingDayStatus(
          plan: _training(dayKey: '20260820'),
          matchedDurationSeconds: 0,
          todayKey: _today,
        ),
        TrainingDayStatus.planned,
      );
    });

    test('today untouched is Planned', () {
      expect(
        deriveTrainingDayStatus(
          plan: _training(dayKey: _today),
          matchedDurationSeconds: 0,
          todayKey: _today,
        ),
        TrainingDayStatus.planned,
      );
    });

    test('today partially practiced is In Progress', () {
      expect(
        deriveTrainingDayStatus(
          plan: _training(dayKey: _today),
          matchedDurationSeconds: 7 * 60,
          todayKey: _today,
        ),
        TrainingDayStatus.inProgress,
      );
    });

    test('target reached is Completed', () {
      expect(
        deriveTrainingDayStatus(
          plan: _training(dayKey: _today),
          matchedDurationSeconds: 10 * 60,
          todayKey: _today,
        ),
        TrainingDayStatus.completed,
      );
    });

    test('target exceeded is Completed', () {
      expect(
        deriveTrainingDayStatus(
          plan: _training(dayKey: _today),
          matchedDurationSeconds: 12 * 60,
          todayKey: _today,
        ),
        TrainingDayStatus.completed,
      );
    });

    test('past unfinished is Missed', () {
      expect(
        deriveTrainingDayStatus(
          plan: _training(dayKey: '20260818'),
          matchedDurationSeconds: 4 * 60,
          todayKey: _today,
        ),
        TrainingDayStatus.missed,
      );
    });

    test('explicit rest day is Rest', () {
      expect(
        deriveTrainingDayStatus(
          plan: TrainingPlan.rest(userId: _userId, dayKey: _today),
          matchedDurationSeconds: 0,
          todayKey: _today,
        ),
        TrainingDayStatus.rest,
      );
    });

    test('no plan is Unplanned', () {
      expect(
        deriveTrainingDayStatus(
          plan: null,
          matchedDurationSeconds: 0,
          todayKey: _today,
        ),
        TrainingDayStatus.unplanned,
      );
    });
  });

  group('session matching', () {
    final plan = _training(dayKey: _today);

    test('aggregates matching sessions on the same Manila day', () {
      final seconds = matchedPlanDurationSeconds(
        plan: plan,
        sessionsForDay: [
          _session(createdAt: '2026-08-19T04:00:00.000Z', durationSeconds: 360),
          _session(createdAt: '2026-08-19T05:00:00.000Z', durationSeconds: 300),
        ],
      );
      expect(seconds, 660);
      expect(
        deriveTrainingDayStatus(
          plan: plan,
          matchedDurationSeconds: seconds,
          todayKey: _today,
        ),
        TrainingDayStatus.completed,
      );
    });

    test('unrelated movement does not complete the plan', () {
      final seconds = matchedPlanDurationSeconds(
        plan: plan,
        sessionsForDay: [
          _session(
            createdAt: '2026-08-19T04:00:00.000Z',
            movementName: 'Flair',
            durationSeconds: 1200,
          ),
        ],
      );
      expect(seconds, 0);
    });

    test('wrong prop does not complete the plan', () {
      final seconds = matchedPlanDurationSeconds(
        plan: plan,
        sessionsForDay: [
          _session(
            createdAt: '2026-08-19T04:00:00.000Z',
            propType: TrainingProp.shaker,
            durationSeconds: 1200,
          ),
        ],
      );
      expect(seconds, 0);
    });

    test('wrong difficulty does not complete the plan', () {
      final seconds = matchedPlanDurationSeconds(
        plan: plan,
        sessionsForDay: [
          _session(
            createdAt: '2026-08-19T04:00:00.000Z',
            difficulty: 'Easy',
            durationSeconds: 1200,
          ),
        ],
      );
      expect(seconds, 0);
    });
  });

  group('adherence metrics', () {
    test('counts planned days and completed days, excluding rest', () {
      final metrics = computeTrainingAdherenceMetrics(
        plans: [
          _training(dayKey: '20260801'),
          _training(dayKey: '20260802'),
          TrainingPlan.rest(userId: _userId, dayKey: '20260803'),
          _training(dayKey: '20260825'),
        ],
        sessions: [
          _session(createdAt: '2026-08-01T04:00:00.000Z', durationSeconds: 600),
        ],
        todayKey: _today,
        monthKey: '202608',
      );

      expect(metrics.plannedDays, 3);
      expect(metrics.completedDays, 1);
      expect(metrics.eligiblePlannedDays, 2);
      expect(metrics.adherencePercent, 50);
    });

    test('excludes future plans from the adherence denominator', () {
      final metrics = computeTrainingAdherenceMetrics(
        plans: [
          _training(dayKey: '20260818'),
          _training(dayKey: '20260825'),
        ],
        sessions: const [],
        todayKey: _today,
        monthKey: '202608',
      );
      expect(metrics.plannedDays, 2);
      expect(metrics.eligiblePlannedDays, 1);
      expect(metrics.adherencePercent, 0);
    });

    test('rest days do not reduce adherence', () {
      final metrics = computeTrainingAdherenceMetrics(
        plans: [
          _training(dayKey: '20260818'),
          TrainingPlan.rest(userId: _userId, dayKey: '20260817'),
        ],
        sessions: [
          _session(createdAt: '2026-08-18T04:00:00.000Z', durationSeconds: 600),
        ],
        todayKey: _today,
        monthKey: '202608',
      );
      expect(metrics.plannedDays, 1);
      expect(metrics.adherencePercent, 100);
    });
  });

  group('plan streak', () {
    test('skips rest days and ignores an unfinished today', () {
      final streak = computePlanStreak(
        plans: [
          _training(dayKey: '20260817'),
          TrainingPlan.rest(userId: _userId, dayKey: '20260818'),
          _training(dayKey: _today),
        ],
        sessions: [
          _session(createdAt: '2026-08-17T04:00:00.000Z', durationSeconds: 600),
        ],
        todayKey: _today,
      );
      expect(streak, 1);
    });
  });

  group('practice location', () {
    test('encodes movement, difficulty, and prop for the practice route', () {
      expect(
        trainingPracticeLocation(
          movement: "Bartender's Grip",
          difficulty: 'Easy',
          propProtocolValue: 'bottle',
        ),
        "/practice?movement=Bartender%27s+Grip&difficulty=Easy&prop=bottle",
      );
    });
  });

  group('Manila grouping', () {
    test('groups sessions onto the Manila day that contains the timestamp', () {
      final grouped = groupSessionsByManilaDayKey([
        _session(createdAt: '2026-08-18T15:59:00.000Z'),
        _session(createdAt: '2026-08-18T16:01:00.000Z'),
      ]);
      expect(grouped.keys.toSet(), {'20260818', '20260819'});
      expect(
        ManilaDay.dayKeyFromCivil(year: 2026, month: 8, day: 19),
        '20260819',
      );
    });
  });
}
