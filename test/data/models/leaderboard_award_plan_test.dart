import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaderboardAwardPlan', () {
    test('first session creates aggregate values', () {
      final plan = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: null,
        score: 80,
      );

      expect(plan.alreadyProcessed, isFalse);
      expect(plan.sessionsCompleted, 1);
      expect(plan.totalXp, 25);
      expect(plan.scoreSum, 80);
      expect(plan.averageScore, 80);
      expect(plan.bestScore, 80);
    });

    test('second session increments count and XP and recalculates average', () {
      final first = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: null,
        score: 80,
      );
      final second = LeaderboardAwardPlan.fromExisting(
        markerExists: false,
        existing: {
          'total_xp': first.totalXp,
          'sessions_completed': first.sessionsCompleted,
          'score_sum': first.scoreSum,
          'best_score': first.bestScore,
        },
        score: 60,
      );

      expect(second.sessionsCompleted, 2);
      expect(second.totalXp, 50);
      expect(second.scoreSum, 140);
      expect(second.averageScore, 70);
      expect(second.bestScore, 80);
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
      );
      expect(plan.alreadyProcessed, isTrue);
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
  });
}
