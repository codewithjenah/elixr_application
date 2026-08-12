import 'package:elixr_application/data/models/leaderboard_period.dart';
import 'package:elixr_application/data/models/leaderboard_period_aggregate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaderboardPeriodAggregate session transitions', () {
    test('newer key resets before applying the session', () {
      final transition = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.today,
        existing: {
          'daily_key': '20260809',
          'daily_xp': 90,
          'daily_sessions_completed': 3,
          'daily_score_sum': 240,
          'daily_average_score': 80,
          'daily_best_score': 95,
        },
      ).applySession(eventKey: '20260810', xpAwarded: 25, score: 72);

      expect(transition.kind, LeaderboardPeriodTransitionKind.reset);
      expect(transition.aggregate.key, '20260810');
      expect(transition.aggregate.xp, 25);
      expect(transition.aggregate.sessionsCompleted, 1);
      expect(transition.aggregate.scoreSum, 72);
      expect(transition.aggregate.averageScore, 72);
      expect(transition.aggregate.bestScore, 72);
    });

    test('equal key accumulates session XP and metrics', () {
      final transition = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.thisMonth,
        existing: {
          'monthly_key': '202608',
          'monthly_xp': 65,
          'monthly_sessions_completed': 2,
          'monthly_score_sum': 150,
          'monthly_average_score': 75,
          'monthly_best_score': 90,
        },
      ).applySession(eventKey: '202608', xpAwarded: 25, score: 99);

      expect(transition.kind, LeaderboardPeriodTransitionKind.accumulate);
      expect(transition.aggregate.xp, 90);
      expect(transition.aggregate.sessionsCompleted, 3);
      expect(transition.aggregate.scoreSum, 249);
      expect(transition.aggregate.averageScore, 83);
      expect(transition.aggregate.bestScore, 99);
    });

    test('older backfilled event preserves every newer metric', () {
      const existing = {
        'daily_key': '20260810',
        'daily_xp': 50,
        'daily_sessions_completed': 2,
        'daily_score_sum': 170,
        'daily_average_score': 85,
        'daily_best_score': 90,
      };
      final aggregate = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.today,
        existing: existing,
      );
      final transition = aggregate.applySession(
        eventKey: '20260809',
        xpAwarded: 25,
        score: 100,
      );

      expect(transition.kind, LeaderboardPeriodTransitionKind.preserve);
      expect(identical(transition.aggregate, aggregate), isTrue);
      expect(transition.aggregate.toFirestoreFields(), existing);
    });

    test('legacy missing period fields initialize from the event', () {
      final transition = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.thisMonth,
        existing: {'total_xp': 500},
      ).applySession(eventKey: '202608', xpAwarded: 25, score: 88);

      expect(transition.kind, LeaderboardPeriodTransitionKind.reset);
      expect(transition.aggregate.key, '202608');
      expect(transition.aggregate.xp, 25);
      expect(transition.aggregate.sessionsCompleted, 1);
    });
  });

  group('LeaderboardPeriodAggregate Assessment V2 session transitions', () {
    test('null score counts the session but freezes score metrics', () {
      final transition = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.today,
        existing: {
          'daily_key': '20260810',
          'daily_xp': 50,
          'daily_sessions_completed': 2,
          'daily_score_sum': 170,
          'daily_average_score': 85,
          'daily_best_score': 90,
        },
      ).applySession(eventKey: '20260810', xpAwarded: 25, score: null);

      expect(transition.kind, LeaderboardPeriodTransitionKind.accumulate);
      expect(transition.aggregate.xp, 75);
      expect(transition.aggregate.sessionsCompleted, 3);
      expect(transition.aggregate.scoreSum, 170);
      expect(transition.aggregate.averageScore, 85);
      expect(transition.aggregate.bestScore, 90);
    });

    test('null score in a newer period resets score metrics to zero', () {
      final transition = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.thisMonth,
        existing: {
          'monthly_key': '202607',
          'monthly_xp': 125,
          'monthly_sessions_completed': 4,
          'monthly_score_sum': 320,
          'monthly_average_score': 80,
          'monthly_best_score': 95,
        },
      ).applySession(eventKey: '202608', xpAwarded: 25, score: null);

      expect(transition.kind, LeaderboardPeriodTransitionKind.reset);
      expect(transition.aggregate.xp, 25);
      expect(transition.aggregate.sessionsCompleted, 1);
      expect(transition.aggregate.scoreSum, 0);
      expect(transition.aggregate.averageScore, 0);
      expect(transition.aggregate.bestScore, 0);
    });

    test('an older V2 backfill still cannot roll a newer period back', () {
      final aggregate = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.today,
        existing: {
          'daily_key': '20260810',
          'daily_xp': 50,
          'daily_sessions_completed': 2,
          'daily_score_sum': 170,
          'daily_average_score': 85,
          'daily_best_score': 90,
        },
      );
      final transition = aggregate.applySession(
        eventKey: '20260809',
        xpAwarded: 25,
        score: null,
      );

      expect(transition.kind, LeaderboardPeriodTransitionKind.preserve);
      expect(identical(transition.aggregate, aggregate), isTrue);
    });
  });

  group('LeaderboardPeriodAggregate quest transitions', () {
    test('equal-period quest adds XP without changing session metrics', () {
      final transition = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.today,
        existing: {
          'daily_key': '20260810',
          'daily_xp': 25,
          'daily_sessions_completed': 1,
          'daily_score_sum': 80,
          'daily_average_score': 80,
          'daily_best_score': 80,
        },
      ).applyQuest(eventKey: '20260810', xpAwarded: 15);

      expect(transition.kind, LeaderboardPeriodTransitionKind.accumulate);
      expect(transition.aggregate.xp, 40);
      expect(transition.aggregate.sessionsCompleted, 1);
      expect(transition.aggregate.scoreSum, 80);
      expect(transition.aggregate.averageScore, 80);
      expect(transition.aggregate.bestScore, 80);
    });

    test('quest in a newer period resets metrics and adds only XP', () {
      final transition = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.thisMonth,
        existing: {
          'monthly_key': '202607',
          'monthly_xp': 125,
          'monthly_sessions_completed': 4,
          'monthly_score_sum': 320,
          'monthly_average_score': 80,
          'monthly_best_score': 95,
        },
      ).applyQuest(eventKey: '202608', xpAwarded: 10);

      expect(transition.kind, LeaderboardPeriodTransitionKind.reset);
      expect(transition.aggregate.xp, 10);
      expect(transition.aggregate.sessionsCompleted, 0);
      expect(transition.aggregate.scoreSum, 0);
      expect(transition.aggregate.averageScore, 0);
      expect(transition.aggregate.bestScore, 0);
    });

    test('older quest cannot overwrite a newer period', () {
      final transition = LeaderboardPeriodAggregate.fromExisting(
        period: LeaderboardPeriod.today,
        existing: {
          'daily_key': '20260810',
          'daily_xp': 25,
          'daily_sessions_completed': 1,
          'daily_score_sum': 90,
          'daily_average_score': 90,
          'daily_best_score': 90,
        },
      ).applyQuest(eventKey: '20260809', xpAwarded: 20);

      expect(transition.kind, LeaderboardPeriodTransitionKind.preserve);
      expect(transition.aggregate.key, '20260810');
      expect(transition.aggregate.xp, 25);
      expect(transition.aggregate.sessionsCompleted, 1);
    });
  });
}
