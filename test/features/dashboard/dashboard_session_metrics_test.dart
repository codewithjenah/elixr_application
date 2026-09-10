import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/calendar/utils/calendar_metrics.dart';
import 'package:elixr_application/features/dashboard/dashboard_session_metrics.dart';
import 'package:elixr_core/utils/comparable_rubric_progress.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = 'metrics-user';

/// Thursday 2026-09-10 12:00 Manila (04:00 UTC).
final _nowUtc = DateTime.utc(2026, 9, 10, 4);

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

Session _v2({
  required String createdAt,
  int rubricTotal = 8,
  String movementName = 'Normal Grip',
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: 'Easy',
    rubric: _rubric(rubricTotal),
    assessmentVersion: 2,
    durationSeconds: 60,
    createdAt: createdAt,
  );
}

Session _v1({
  required String createdAt,
  int legacyScore = 90,
  String movementName = 'Normal Grip',
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: 'Easy',
    legacyScore: legacyScore,
    assessmentVersion: 1,
    durationSeconds: 60,
    createdAt: createdAt,
  );
}

void main() {
  group('DashboardSessionMetrics', () {
    test(
      'counts sessions from Manila Monday through the current local day',
      () {
        final sessions = [
          _v2(createdAt: '2026-09-06T15:59:59.000Z'), // Sunday Manila
          _v2(createdAt: '2026-09-06T16:00:00.000Z'), // Monday Manila
          _v2(createdAt: '2026-09-10T03:00:00.000Z'), // Thursday Manila
          _v2(createdAt: '2026-09-10T04:00:00.000Z'),
        ];

        final metrics = DashboardSessionMetrics.fromSessions(
          sessions,
          nowUtc: _nowUtc,
        );

        expect(metrics.sessionsThisWeek, 3);
        expect(metrics.practicedDays, {
          DateTime(2026, 9, 6),
          DateTime(2026, 9, 7),
          DateTime(2026, 9, 10),
        });
      },
    );

    test('keeps a streak that is longer than 14 Manila days', () {
      final sessions = [
        for (var day = 20; day >= 0; day--)
          _v2(
            createdAt: DateTime.utc(
              2026,
              9,
              10,
              4,
            ).subtract(Duration(days: day)).toIso8601String(),
          ),
      ];

      final metrics = DashboardSessionMetrics.fromSessions(
        sessions,
        nowUtc: _nowUtc,
      );

      expect(metrics.currentStreak, 21);
      expect(
        currentStreak(
          metrics.practicedDays,
          referenceDate: DateTime(2026, 9, 10),
        ),
        21,
      );
    });

    test(
      'uses trailing 7 vs prior 7 Manila days for Assessment V2 comparison',
      () {
        final sessions = [
          _v2(createdAt: '2026-09-10T03:00:00.000Z', rubricTotal: 12),
          _v2(createdAt: '2026-09-03T03:00:00.000Z', rubricTotal: 6),
          _v2(createdAt: '2026-08-27T03:00:00.000Z', rubricTotal: 3),
          _v1(createdAt: '2026-09-09T03:00:00.000Z', legacyScore: 100),
          _v1(createdAt: '2026-09-02T03:00:00.000Z', legacyScore: 10),
        ];

        final metrics = DashboardSessionMetrics.fromSessions(
          sessions,
          nowUtc: _nowUtc,
        );

        expect(metrics.weeklyComparison.currentAverage, 12);
        expect(metrics.weeklyComparison.comparisonAverage, 6);
        expect(metrics.weeklyComparison.percentageChange, 100);
      },
    );

    test('excludes legacy percentage scores from the V2 weekly comparison', () {
      final onlyLegacy = [
        _v1(createdAt: '2026-09-10T03:00:00.000Z', legacyScore: 100),
        _v1(createdAt: '2026-09-03T03:00:00.000Z', legacyScore: 40),
      ];

      final metrics = DashboardSessionMetrics.fromSessions(
        onlyLegacy,
        nowUtc: _nowUtc,
      );

      expect(metrics.weeklyComparison.currentAverage, isNull);
      expect(metrics.weeklyComparison.comparisonAverage, isNull);
      expect(metrics.weeklyComparison.percentageChange, isNull);
      expect(
        ComparableRubricProgress.scoreFor(
          assessmentVersion: onlyLegacy.first.assessmentVersion,
          rubricTotal: onlyLegacy.first.rubricTotal,
        ),
        isNull,
      );
    });

    test('prefers an all-time V2 personal best over a higher legacy score', () {
      final sessions = [
        _v2(createdAt: '2026-01-01T00:00:00.000Z', rubricTotal: 9),
        _v2(createdAt: '2026-09-10T03:00:00.000Z', rubricTotal: 4),
        _v1(createdAt: '2026-09-09T03:00:00.000Z', legacyScore: 99),
      ];

      final metrics = DashboardSessionMetrics.fromSessions(
        sessions,
        nowUtc: _nowUtc,
      );

      expect(metrics.bestSession?.rubricTotal, 9);
      expect(metrics.bestSession?.isRubricAssessed, isTrue);
    });

    test(
      'falls back to the all-time legacy best when no V2 session exists',
      () {
        final sessions = [
          _v1(createdAt: '2026-01-01T00:00:00.000Z', legacyScore: 40),
          _v1(createdAt: '2026-09-10T03:00:00.000Z', legacyScore: 88),
        ];

        final metrics = DashboardSessionMetrics.fromSessions(
          sessions,
          nowUtc: _nowUtc,
        );

        expect(metrics.bestSession?.legacyScore, 88);
      },
    );

    test('splits sessions around the UTC/Manila midnight boundary', () {
      final before = _v2(createdAt: '2026-09-09T15:59:59.000Z');
      final atBoundary = _v2(createdAt: '2026-09-09T16:00:00.000Z');

      expect(parseSessionLocalDate(before), DateTime(2026, 9, 9));
      expect(parseSessionLocalDate(atBoundary), DateTime(2026, 9, 10));

      final metrics = DashboardSessionMetrics.fromSessions([
        before,
        atBoundary,
      ], nowUtc: _nowUtc);

      expect(metrics.practicedDays, {
        DateTime(2026, 9, 9),
        DateTime(2026, 9, 10),
      });
      expect(metrics.currentStreak, 2);
      expect(metrics.sessionsThisWeek, 2);
    });
  });
}
