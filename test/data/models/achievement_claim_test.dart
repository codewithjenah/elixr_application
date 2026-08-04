import 'package:elixr_application/data/models/achievement_claim.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AchievementClaim.documentId', () {
    test('is deterministic', () {
      expect(
        AchievementClaim.documentId('alice', 'first_steps'),
        'alice_first_steps',
      );
    });
  });

  group('AchievementUnlockPlan', () {
    test('first unlock creates a single-border inventory', () {
      final plan = AchievementUnlockPlan.fromExisting(
        claimExists: false,
        existingCosmetics: null,
        achievementId: 'first_steps',
        claimDocumentId: 'alice_first_steps',
      );

      expect(plan.alreadyClaimed, isFalse);
      expect(plan.unlockedBorderIds, ['starter_glow']);
      expect(plan.rewardBorderId, 'starter_glow');
      expect(plan.lastAchievementClaimId, 'alice_first_steps');
    });

    test('append unlock preserves order and adds exactly one border', () {
      final plan = AchievementUnlockPlan.fromExisting(
        claimExists: false,
        existingCosmetics: {
          'unlocked_border_ids': ['starter_glow', 'bronze_ember'],
          'last_achievement_claim_id': 'alice_getting_started',
        },
        achievementId: 'sharp_pour',
        claimDocumentId: 'alice_sharp_pour',
      );

      expect(plan.unlockedBorderIds, [
        'starter_glow',
        'bronze_ember',
        'cyan_orbit',
      ]);
      expect(plan.lastAchievementClaimId, 'alice_sharp_pour');
    });

    test('does not duplicate an already-unlocked reward border', () {
      final plan = AchievementUnlockPlan.fromExisting(
        claimExists: false,
        existingCosmetics: {
          'unlocked_border_ids': ['starter_glow'],
        },
        achievementId: 'first_steps',
        claimDocumentId: 'alice_first_steps',
      );

      expect(plan.unlockedBorderIds, ['starter_glow']);
    });

    test('already claimed returns without modifying data', () {
      final plan = AchievementUnlockPlan.fromExisting(
        claimExists: true,
        existingCosmetics: {
          'unlocked_border_ids': ['starter_glow'],
        },
        achievementId: 'first_steps',
        claimDocumentId: 'alice_first_steps',
      );

      expect(plan.alreadyClaimed, isTrue);
      expect(plan.unlockedBorderIds, isEmpty);
    });

    test('invalid mapping throws', () {
      expect(
        () => AchievementUnlockPlan.fromExisting(
          claimExists: false,
          existingCosmetics: null,
          achievementId: 'not_a_real_achievement',
          claimDocumentId: 'alice_x',
        ),
        throwsArgumentError,
      );
    });
  });
}
