import 'package:elixr_application/data/models/quest_claim.dart';
import 'package:elixr_application/data/repositories/gamification_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseQuestClaimResponse', () {
    test('maps a claimed result with its server-awarded XP', () {
      final result = parseQuestClaimResponse({
        'status': 'claimed',
        'xp_awarded': 15,
      });
      expect(result.status, QuestClaimStatus.claimed);
      expect(result.xpAwarded, 15);
    });

    test('maps idempotent and ineligible outcomes', () {
      expect(
        parseQuestClaimResponse({'status': 'already_claimed'}),
        const QuestClaimResult.alreadyClaimed(),
      );
      expect(
        parseQuestClaimResponse({'status': 'quest_not_completed'}),
        const QuestClaimResult.questNotCompleted(),
      );
      expect(
        parseQuestClaimResponse({'status': 'board_missing'}),
        const QuestClaimResult.boardMissing(),
      );
      expect(
        parseQuestClaimResponse({'status': 'leaderboard_missing'}),
        const QuestClaimResult.leaderboardMissing(),
      );
      expect(
        parseQuestClaimResponse({'status': 'invalid_quest'}),
        const QuestClaimResult.invalidQuest(),
      );
    });

    test('turns malformed results into a controlled service error', () {
      for (final raw in <Object?>[
        null,
        'claimed',
        const <String, dynamic>{},
        {'status': 'surprise'},
      ]) {
        expect(
          () => parseQuestClaimResponse(raw),
          throwsA(
            isA<QuestClaimServiceException>().having(
              (error) => error.error,
              'error',
              QuestClaimServiceError.malformedResponse,
            ),
          ),
        );
      }
    });
  });
}
