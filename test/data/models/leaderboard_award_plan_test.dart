import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaderboardAwardPlan', () {
    test('first session creates aggregate values', () {
      final plan = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: null,
        score: 80,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );

      expect(plan.alreadyProcessed, isFalse);
      expect(plan.sessionsCompleted, 1);
      expect(plan.totalXp, 25);
      expect(plan.scoreSum, 80);
      expect(plan.averageScore, 80);
      expect(plan.bestScore, 80);
      expect(plan.daily.key, '20260810');
      expect(plan.daily.xp, 25);
      expect(plan.daily.sessionsCompleted, 1);
      expect(plan.monthly.key, '202608');
      expect(plan.monthly.xp, 25);
    });

    test('second session increments count and XP and recalculates average', () {
      final first = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: null,
        score: 80,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );
      final second = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: {
          'total_xp': first.totalXp,
          'sessions_completed': first.sessionsCompleted,
          'score_sum': first.scoreSum,
          'best_score': first.bestScore,
          ...first.periodFields,
        },
        score: 60,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10, 1),
      );

      expect(second.sessionsCompleted, 2);
      expect(second.totalXp, 50);
      expect(second.scoreSum, 140);
      expect(second.averageScore, 70);
      expect(second.bestScore, 80);
      expect(second.daily.xp, 50);
      expect(second.daily.sessionsCompleted, 2);
      expect(second.daily.averageScore, 70);
      expect(second.monthly.xp, 50);
    });

    test('best score remains the maximum', () {
      final plan = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: {
          'total_xp': 25,
          'sessions_completed': 1,
          'score_sum': 90,
          'best_score': 90,
        },
        score: 40,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );
      expect(plan.bestScore, 90);

      final higher = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: {
          'total_xp': 50,
          'sessions_completed': 2,
          'score_sum': 130,
          'best_score': 90,
        },
        score: 95,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );
      expect(higher.bestScore, 95);
    });

    test('session award preserves an existing quest_xp value unchanged', () {
      final plan = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: {
          'total_xp': 65,
          'sessions_completed': 2,
          'score_sum': 160,
          'best_score': 90,
          'quest_xp': 15,
        },
        score: 100,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );

      expect(plan.questXp, 15);
      expect(plan.totalXp, 90);
      expect(plan.sessionsCompleted, 3);
    });

    test('legacy documents without quest_xp default it to zero', () {
      final plan = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: {
          'total_xp': 25,
          'sessions_completed': 1,
          'score_sum': 80,
          'best_score': 80,
        },
        score: 90,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );

      expect(plan.questXp, 0);
      expect(plan.totalXp, 50);
    });

    test('same session marker skips award', () {
      final plan = LeaderboardAwardPlan.fromExisting(
        markerExists: true,
        existing: {
          'total_xp': 25,
          'sessions_completed': 1,
          'score_sum': 80,
          'best_score': 80,
        },
        score: 80,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );
      expect(plan.alreadyProcessed, isTrue);
    });
  });

  group('LeaderboardAwardPlan Assessment V2 (null score)', () {
    test('awards XP and a session while freezing legacy score aggregates', () {
      final plan = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: {
          'total_xp': 50,
          'sessions_completed': 2,
          'score_sum': 170.0,
          'average_score': 85.0,
          'best_score': 90,
          'daily_key': '20260810',
          'daily_xp': 50,
          'daily_sessions_completed': 2,
          'daily_score_sum': 170.0,
          'daily_average_score': 85.0,
          'daily_best_score': 90,
          'monthly_key': '202608',
          'monthly_xp': 50,
          'monthly_sessions_completed': 2,
          'monthly_score_sum': 170.0,
          'monthly_average_score': 85.0,
          'monthly_best_score': 90,
        },
        score: null,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10, 3),
      );

      expect(plan.alreadyProcessed, isFalse);
      expect(plan.totalXp, 75);
      expect(plan.sessionsCompleted, 3);
      expect(plan.scoreSum, 170.0);
      expect(plan.averageScore, 85.0);
      expect(plan.bestScore, 90);

      expect(plan.daily.xp, 75);
      expect(plan.daily.sessionsCompleted, 3);
      expect(plan.daily.scoreSum, 170.0);
      expect(plan.daily.averageScore, 85.0);
      expect(plan.daily.bestScore, 90);

      expect(plan.monthly.xp, 75);
      expect(plan.monthly.sessionsCompleted, 3);
      expect(plan.monthly.scoreSum, 170.0);
      expect(plan.monthly.averageScore, 85.0);
      expect(plan.monthly.bestScore, 90);
    });

    test('first-ever V2 award leaves every score aggregate at zero', () {
      final plan = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: null,
        score: null,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );

      expect(plan.totalXp, 25);
      expect(plan.sessionsCompleted, 1);
      expect(plan.scoreSum, 0);
      expect(plan.averageScore, 0);
      expect(plan.bestScore, 0);
      expect(plan.daily.key, '20260810');
      expect(plan.daily.sessionsCompleted, 1);
      expect(plan.daily.bestScore, 0);
      expect(plan.monthly.key, '202608');
      expect(plan.monthly.sessionsCompleted, 1);
    });

    test('V2 award preserves quest XP and stays idempotent on a marker', () {
      final existing = {
        'total_xp': 65,
        'sessions_completed': 2,
        'score_sum': 160.0,
        'average_score': 80.0,
        'best_score': 90,
        'quest_xp': 15,
      };
      final plan = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: existing,
        score: null,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );
      expect(plan.questXp, 15);
      expect(plan.totalXp, 90);

      final replay = LeaderboardAwardPlan.fromExisting(
        markerExists: true,
        existing: existing,
        score: null,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );
      expect(replay.alreadyProcessed, isTrue);
      expect(replay.totalXp, 0);
    });

    test('a later V1 award still accumulates on top of frozen V2 state', () {
      final v2 = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: {
          'total_xp': 25,
          'sessions_completed': 1,
          'score_sum': 80.0,
          'average_score': 80.0,
          'best_score': 80,
        },
        score: null,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10),
      );
      final v1 = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: {
          'total_xp': v2.totalXp,
          'sessions_completed': v2.sessionsCompleted,
          'score_sum': v2.scoreSum,
          'average_score': v2.averageScore,
          'best_score': v2.bestScore,
        },
        score: 100,
        sessionCreatedAtUtc: DateTime.utc(2026, 8, 10, 2),
      );

      expect(v1.sessionsCompleted, 3);
      expect(v1.totalXp, 75);
      expect(v1.scoreSum, 180.0);
      expect(v1.bestScore, 100);
    });
  });

  group('LeaderboardSyncPlanner', () {
    test('returns only missing sessions in chronological order', () {
      final missing = LeaderboardSyncPlanner.sessionsMissingAwards(
        sessions: const [
          SessionRef(id: 'c', userId: 'u1', createdAtMs: 300),
          SessionRef(id: 'a', userId: 'u1', createdAtMs: 100),
          SessionRef(id: 'b', userId: 'u1', createdAtMs: 200),
        ],
        processedSessionIds: {'b'},
      );

      expect(missing.map((s) => s.id), ['a', 'c']);
    });

    test('skips already processed sessions', () {
      final missing = LeaderboardSyncPlanner.sessionsMissingAwards(
        sessions: const [
          SessionRef(id: 'a', userId: 'u1', createdAtMs: 100),
          SessionRef(id: 'b', userId: 'u1', createdAtMs: 200),
        ],
        processedSessionIds: {'a', 'b'},
      );
      expect(missing, isEmpty);
    });

    test('partially processed user only receives missing awards', () {
      final missing = LeaderboardSyncPlanner.sessionsMissingAwards(
        sessions: const [
          SessionRef(id: 'old', userId: 'u1', createdAtMs: 1),
          SessionRef(id: 'new', userId: 'u1', createdAtMs: 2),
        ],
        processedSessionIds: {'old'},
      );
      expect(missing.map((s) => s.id), ['new']);
    });

    test('official sessions missing markers remain awardable', () {
      final eligible =
          LeaderboardSyncPlanner.sessionsEligibleForGlobalXp(const [
            SessionRef(
              id: 'official',
              userId: 'u1',
              createdAtMs: 1,
              movementName: 'Hand Stall',
            ),
            SessionRef(
              id: 'alias',
              userId: 'u1',
              createdAtMs: 2,
              movementName: 'Arm Stall',
            ),
          ]);
      expect(eligible.map((s) => s.id), ['official']);
    });

    test(
      'historical non-official sessions are skipped without counting as missing awards',
      () {
        final sessions = const [
          SessionRef(
            id: 'legacy-alias',
            userId: 'u1',
            createdAtMs: 1,
            movementName: 'Arm Stall',
          ),
          SessionRef(
            id: 'custom',
            userId: 'u1',
            createdAtMs: 2,
            movementName: 'Basic Flip',
          ),
          SessionRef(
            id: 'official',
            userId: 'u1',
            createdAtMs: 3,
            movementName: 'Hand Stall',
          ),
        ];
        final missing = LeaderboardSyncPlanner.sessionsMissingAwards(
          sessions: sessions,
          processedSessionIds: const {},
        );
        final awardable = LeaderboardSyncPlanner.sessionsEligibleForGlobalXp(
          missing,
        );

        expect(missing.map((s) => s.id), [
          'legacy-alias',
          'custom',
          'official',
        ]);
        expect(awardable.map((s) => s.id), ['official']);
      },
    );

    test('sessions without a movement name are not eligible for global XP', () {
      final awardable = LeaderboardSyncPlanner.sessionsEligibleForGlobalXp(
        const [SessionRef(id: 'unknown', userId: 'u1', createdAtMs: 1)],
      );
      expect(awardable, isEmpty);
    });
  });
}
