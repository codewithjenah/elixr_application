import 'package:elixr_application/core/constants/gamification_rules.dart';
import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/core/progression/progression_catalog.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exactly 16 milestones and one new unlock per level 1-16', () {
    expect(progressionMilestones.length, 16);
    for (var level = 1; level <= 16; level++) {
      expect(
        progressionMilestones.where((m) => m.requiredLevel == level).length,
        1,
      );
    }
  });

  test('level 1 is Normal Grip / Bottle; level 16 is Bottle in a tin combined', () {
    expect(
      progressionMilestones.first.variant,
      const PracticeVariant(
        movementName: 'Normal Grip',
        trainingProp: TrainingProp.bottle,
      ),
    );
    expect(
      progressionMilestones.last.variant,
      const PracticeVariant(
        movementName: 'Bottle in a tin',
        trainingProp: TrainingProp.bottleAndShaker,
      ),
    );
  });

  test('every milestone is a real catalog movement + supported prop', () {
    for (final milestone in progressionMilestones) {
      final step = resolvePracticeVariant(milestone.variant);
      expect(step, isNotNull, reason: milestone.variant.persistenceKey);
      expect(step!.movement.enabled, isTrue);
    }
  });

  test('Hand Stall bottle unlocks at 5 and shaker at 6', () {
    expect(
      requiredLevelFor(
        const PracticeVariant(
          movementName: 'Hand Stall',
          trainingProp: TrainingProp.bottle,
        ),
      ),
      5,
    );
    expect(
      requiredLevelFor(
        const PracticeVariant(
          movementName: 'Hand Stall',
          trainingProp: TrainingProp.shaker,
        ),
      ),
      6,
    );
  });

  test('level 17 unlocks no new content; nextUnlock after 16 is null', () {
    expect(allPersonallyLevelUnlockedVariants(16).length, 16);
    expect(allPersonallyLevelUnlockedVariants(17).length, 16);
    expect(nextUnlockAfterLevel(16), isNull);
  });

  test('xpRemainingToNextUnlock uses GamificationRules', () {
    expect(xpRemainingToNextUnlock(80), GamificationRules.xpPerLevel - 80);
    final level16Xp = GamificationRules.xpPerLevel * 15;
    expect(xpRemainingToNextUnlock(level16Xp), 0);
  });

  test('Medium dual-prop milestones stay distinct official identities', () {
    final bottle = resolvePracticeVariant(
      const PracticeVariant(
        movementName: 'Elbow Stall',
        trainingProp: TrainingProp.bottle,
      ),
    );
    final shaker = resolvePracticeVariant(
      const PracticeVariant(
        movementName: 'Elbow Stall',
        trainingProp: TrainingProp.shaker,
      ),
    );
    expect(bottle, isNotNull);
    expect(shaker, isNotNull);
    expect(bottle!.movement.name, shaker!.movement.name);
    expect(bottle.prop, isNot(equals(shaker.prop)));
  });

  test('unsupported movement/prop fails resolve', () {
    expect(
      resolvePracticeVariant(
        const PracticeVariant(
          movementName: 'Hand Stall',
          trainingProp: TrainingProp.bottleAndShaker,
        ),
      ),
      isNull,
    );
  });
}
