import 'package:elixr_application/data/models/quest_claim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuestAwardPlan.fromExisting', () {
    test('adds quest XP once and preserves session aggregates', () {
      final plan = QuestAwardPlan.fromExisting(
        claimExists: false,
        existing: {
          'total_xp': 65,
          'quest_xp': 15,
          'sessions_completed': 2,
          'score_sum': 180.0,
          'average_score': 90.0,
          'best_score': 100,
          'last_awarded_session_id': 's2',
          'last_session_at': '2026-08-01T00:00:00.000Z',
        },
        xpAwarded: 10,
      );

      expect(plan.alreadyClaimed, isFalse);
      expect(plan.totalXp, 75);
      expect(plan.questXp, 25);
      expect(plan.sessionsCompleted, 2);
      expect(plan.scoreSum, 180.0);
      expect(plan.averageScore, 90.0);
      expect(plan.bestScore, 100);
      expect(plan.lastAwardedSessionId, 's2');
    });

    test(
      'legacy leaderboard documents without quest_xp default it to zero',
      () {
        final plan = QuestAwardPlan.fromExisting(
          claimExists: false,
          existing: {
            'total_xp': 25,
            'sessions_completed': 1,
            'score_sum': 80.0,
            'average_score': 80.0,
            'best_score': 80,
          },
          xpAwarded: 20,
        );

        expect(plan.questXp, 20);
        expect(plan.totalXp, 45);
      },
    );

    test('already-claimed short-circuits without awarding XP again', () {
      final plan = QuestAwardPlan.fromExisting(
        claimExists: true,
        existing: {'total_xp': 100, 'quest_xp': 50},
        xpAwarded: 15,
      );

      expect(plan.alreadyClaimed, isTrue);
      expect(plan.totalXp, 0);
      expect(plan.questXp, 0);
    });

    test('a missing existing document is treated as all-zero aggregates', () {
      final plan = QuestAwardPlan.fromExisting(
        claimExists: false,
        existing: null,
        xpAwarded: 10,
      );

      expect(plan.totalXp, 10);
      expect(plan.questXp, 10);
      expect(plan.sessionsCompleted, 0);
      expect(plan.scoreSum, 0);
      expect(plan.bestScore, 0);
    });
  });

  group('QuestClaim', () {
    test('documentId is deterministic', () {
      expect(
        QuestClaim.documentId('u1', '20260804', 'two_movements'),
        'u1_20260804_two_movements',
      );
    });

    test('toMap contains exactly the persisted claim fields', () {
      final claim = QuestClaim(
        userId: 'u1',
        boardId: 'u1_20260804',
        dayKey: '20260804',
        dayStart: DateTime.utc(2026, 8, 3, 16, 0, 0),
        questId: 'two_movements',
        xpAwarded: 10,
      );

      expect(claim.toMap(), {
        'user_id': 'u1',
        'board_id': 'u1_20260804',
        'day_key': '20260804',
        'day_start': DateTime.utc(2026, 8, 3, 16, 0, 0),
        'quest_id': 'two_movements',
        'xp_awarded': 10,
      });
    });
  });

  group('QuestClaimResult', () {
    test('exposes the awarded XP only for a claimed result', () {
      const claimed = QuestClaimResult.claimed(10);
      expect(claimed.status, QuestClaimStatus.claimed);
      expect(claimed.xpAwarded, 10);

      const alreadyClaimed = QuestClaimResult.alreadyClaimed();
      expect(alreadyClaimed.status, QuestClaimStatus.alreadyClaimed);
      expect(alreadyClaimed.xpAwarded, 0);
    });

    test('every typed outcome has a matching status', () {
      expect(
        const QuestClaimResult.questNotCompleted().status,
        QuestClaimStatus.questNotCompleted,
      );
      expect(
        const QuestClaimResult.boardMissing().status,
        QuestClaimStatus.boardMissing,
      );
      expect(
        const QuestClaimResult.boardExpired().status,
        QuestClaimStatus.boardExpired,
      );
      expect(
        const QuestClaimResult.leaderboardMissing().status,
        QuestClaimStatus.leaderboardMissing,
      );
      expect(
        const QuestClaimResult.invalidQuest().status,
        QuestClaimStatus.invalidQuest,
      );
    });
  });
}
