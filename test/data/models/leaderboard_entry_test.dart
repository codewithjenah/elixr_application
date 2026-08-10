import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/leaderboard_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaderboardEntry.tryFromMap', () {
    test('parses a complete Firestore map', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada Lovelace',
        'total_xp': 250,
        'sessions_completed': 10,
        'score_sum': 800,
        'average_score': 80,
        'best_score': 95,
        'last_session_at': '2026-07-27T10:00:00.000',
        'updated_at': '2026-07-27T10:00:00.000',
      });

      expect(entry, isNotNull);
      expect(entry!.userId, 'u1');
      expect(entry.displayName, 'Ada Lovelace');
      expect(entry.totalXp, 250);
      expect(entry.sessionsCompleted, 10);
      expect(entry.scoreSum, 800);
      expect(entry.averageScore, 80);
      expect(entry.bestScore, 95);
      expect(entry.level, 2);
      expect(entry.xpIntoLevel, 0);
      expect(entry.profilePictureUrl, isNull);
    });

    test('parses profile_picture_url when present', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada Lovelace',
        'total_xp': 25,
        'profile_picture_url': 'https://storage.example/avatar.jpg',
      });

      expect(entry, isNotNull);
      expect(entry!.profilePictureUrl, 'https://storage.example/avatar.jpg');
    });

    test('treats missing, empty, or invalid profile_picture_url as null', () {
      final missing = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
      });
      expect(missing!.profilePictureUrl, isNull);

      final empty = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
        'profile_picture_url': '   ',
      });
      expect(empty!.profilePictureUrl, isNull);

      final wrongType = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
        'profile_picture_url': 42,
      });
      expect(wrongType!.profilePictureUrl, isNull);
    });

    test('tolerates missing optional fields and uses document id', () {
      final entry = LeaderboardEntry.tryFromMap({
        'display_name': 'Grace',
        'total_xp': 25,
      }, id: 'u2');

      expect(entry, isNotNull);
      expect(entry!.userId, 'u2');
      expect(entry.sessionsCompleted, 0);
      expect(entry.scoreSum, 0);
      expect(entry.averageScore, 0);
      expect(entry.bestScore, 0);
      expect(entry.lastSessionAt, isNull);
      expect(entry.updatedAt, isNull);
      expect(entry.level, 1);
    });

    test('parses equipped_border_id when present', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
        'equipped_border_id': 'starter_glow',
      });

      expect(entry, isNotNull);
      expect(entry!.equippedBorderId, 'starter_glow');
    });

    test('treats missing or empty equipped_border_id as null', () {
      final missing = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
      });
      expect(missing!.equippedBorderId, isNull);

      final empty = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
        'equipped_border_id': '   ',
      });
      expect(empty!.equippedBorderId, isNull);
    });

    test('legacy documents without quest_xp default it to zero', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
        'sessions_completed': 1,
      });

      expect(entry, isNotNull);
      expect(entry!.questXp, 0);
      expect(entry.totalXp, 25);
    });

    test('parses quest_xp when present and includes it in totalXp', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 65,
        'sessions_completed': 2,
        'quest_xp': 15,
      });

      expect(entry, isNotNull);
      expect(entry!.questXp, 15);
      expect(entry.totalXp, 65);
      // sessionsCompleted * 25 + questXp == totalXp
      expect(entry.sessionsCompleted * 25 + entry.questXp, entry.totalXp);
    });

    test('a negative quest_xp is clamped to zero', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
        'quest_xp': -5,
      });

      expect(entry!.questXp, 0);
    });

    test(
      'direct construction defaults questXp to zero without callers passing it',
      () {
        const entry = LeaderboardEntry(
          userId: 'u1',
          displayName: 'Ada',
          totalXp: 25,
          sessionsCompleted: 1,
          scoreSum: 80,
          averageScore: 80,
          bestScore: 80,
        );

        expect(entry.questXp, 0);
      },
    );

    test('accepts numeric values as int or double', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u3',
        'display_name': 'Alan',
        'total_xp': 25.0,
        'sessions_completed': 1.0,
        'score_sum': 88,
        'average_score': 88.5,
        'best_score': 88.0,
      });

      expect(entry, isNotNull);
      expect(entry!.totalXp, 25);
      expect(entry.sessionsCompleted, 1);
      expect(entry.scoreSum, 88);
      expect(entry.averageScore, 88.5);
      expect(entry.bestScore, 88);
    });

    test('parses and selects daily, monthly, and all-time metrics', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u-periods',
        'display_name': 'Period Player',
        'total_xp': 500,
        'sessions_completed': 16,
        'score_sum': 1280,
        'average_score': 80,
        'best_score': 99,
        'daily_key': '20260810',
        'daily_xp': 45,
        'daily_sessions_completed': 1,
        'daily_score_sum': 82,
        'daily_average_score': 82,
        'daily_best_score': 82,
        'monthly_key': '202608',
        'monthly_xp': 170,
        'monthly_sessions_completed': 6,
        'monthly_score_sum': 510,
        'monthly_average_score': 85,
        'monthly_best_score': 96,
      })!;

      expect(entry.dailyKey, '20260810');
      expect(entry.monthlyKey, '202608');
      expect(entry.xpFor(LeaderboardPeriod.today), 45);
      expect(entry.sessionsCompletedFor(LeaderboardPeriod.today), 1);
      expect(entry.averageScoreFor(LeaderboardPeriod.today), 82);
      expect(entry.bestScoreFor(LeaderboardPeriod.today), 82);
      expect(entry.xpFor(LeaderboardPeriod.thisMonth), 170);
      expect(entry.sessionsCompletedFor(LeaderboardPeriod.thisMonth), 6);
      expect(entry.scoreSumFor(LeaderboardPeriod.thisMonth), 510);
      expect(entry.bestScoreFor(LeaderboardPeriod.thisMonth), 96);
      expect(entry.xpFor(LeaderboardPeriod.allTime), 500);
      expect(entry.sessionsCompletedFor(LeaderboardPeriod.allTime), 16);
      expect(entry.metricsFor(LeaderboardPeriod.allTime).bestScore, 99);
    });

    test('legacy documents default all period metrics to zero', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'legacy',
        'display_name': 'Legacy Player',
        'total_xp': 25,
      })!;

      expect(entry.dailyKey, isNull);
      expect(entry.monthlyKey, isNull);
      expect(entry.xpFor(LeaderboardPeriod.today), 0);
      expect(entry.sessionsCompletedFor(LeaderboardPeriod.today), 0);
      expect(entry.xpFor(LeaderboardPeriod.thisMonth), 0);
      expect(entry.bestScoreFor(LeaderboardPeriod.thisMonth), 0);
      expect(entry.xpFor(LeaderboardPeriod.allTime), 25);
    });

    test('invalid period keys are ignored without rejecting the document', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'invalid-period',
        'display_name': 'Invalid Period',
        'daily_key': '20260230',
        'monthly_key': '202613',
      })!;

      expect(entry.dailyKey, isNull);
      expect(entry.monthlyKey, isNull);
    });

    test('returns null when identity fields are invalid', () {
      expect(LeaderboardEntry.tryFromMap({'display_name': 'X'}), isNull);
      expect(LeaderboardEntry.tryFromMap({'user_id': 'u1'}), isNull);
      expect(
        LeaderboardEntry.tryFromMap({'user_id': '', 'display_name': 'X'}),
        isNull,
      );
      expect(
        LeaderboardEntry.tryFromMap({'user_id': 'u1', 'display_name': '   '}),
        isNull,
      );
    });
  });
}
