import 'package:elixr_application/core/constants/gamification_rules.dart';
import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/core/progression/progression_catalog.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('strict route resolution', () {
    test('accepts canonical supported movement and prop combinations', () {
      final bottle = resolveStrictPracticeRouteVariant(
        movementName: 'Normal Grip',
        propProtocolValue: 'bottle',
      );
      final handStallBottle = resolveStrictPracticeRouteVariant(
        movementName: 'Hand Stall',
        propProtocolValue: 'bottle',
      );
      final shaker = resolveStrictPracticeRouteVariant(
        movementName: 'Hand Stall',
        propProtocolValue: 'shaker',
      );
      final combined = resolveStrictPracticeRouteVariant(
        movementName: 'Bottle in a tin',
        propProtocolValue: 'bottle_and_shaker',
      );

      expect(bottle?.movement.difficulty, 'Easy');
      expect(handStallBottle?.movement.difficulty, 'Medium');
      expect(shaker?.movement.difficulty, 'Medium');
      expect(combined?.movement.difficulty, 'Hard');
    });

    test('URL difficulty metadata cannot override catalog difficulty', () {
      final uri = Uri.parse(
        '/practice?movement=Hand%20Stall&difficulty=Easy&prop=bottle',
      );
      final step = resolveStrictPracticeRouteVariant(
        movementName: uri.queryParameters['movement'],
        propProtocolValue: uri.queryParameters['prop'],
      );

      expect(uri.queryParameters['difficulty'], 'Easy');
      expect(step?.movement.difficulty, 'Medium');
    });

    test('rejects missing, malformed, unknown, and unsupported identities', () {
      final invalidInputs = <(String?, String?)>[
        (null, 'bottle'),
        ('', 'bottle'),
        ('Unknown Move', 'bottle'),
        ('Hand Stall', null),
        ('Hand Stall', 'Bottle'),
        ('Hand Stall', 'glass'),
        ('Hand Stall', 'bottle_and_shaker'),
        ('Bottle in a tin', 'bottle'),
      ];

      for (final (movement, prop) in invalidInputs) {
        expect(
          resolveStrictPracticeRouteVariant(
            movementName: movement,
            propProtocolValue: prop,
          ),
          isNull,
          reason: '$movement + $prop',
        );
      }
    });
  });

  test('exactly 20 milestones and one new unlock per level 1-20', () {
    expect(progressionMilestones.length, 20);
    for (var level = 1; level <= 20; level++) {
      expect(
        progressionMilestones.where((m) => m.requiredLevel == level).length,
        1,
      );
    }
  });

  test(
    'level 1 is Normal Grip / Bottle; level 20 is Double Forearm Stall Bottle',
    () {
      expect(
        progressionMilestones.first.variant,
        const PracticeVariant(
          movementName: 'Normal Grip',
          trainingProp: TrainingProp.bottle,
        ),
      );
      expect(
        progressionMilestones[18].variant,
        const PracticeVariant(
          movementName: 'Bottle in a tin',
          trainingProp: TrainingProp.bottleAndShaker,
        ),
      );
      expect(
        progressionMilestones.last.variant,
        const PracticeVariant(
          movementName: 'Double Forearm Stall',
          trainingProp: TrainingProp.bottle,
        ),
      );
    },
  );

  test('every milestone is a real catalog movement + supported prop', () {
    for (final milestone in progressionMilestones) {
      final step = resolvePracticeVariant(milestone.variant);
      expect(step, isNotNull, reason: milestone.variant.persistenceKey);
      expect(step!.movement.enabled, isTrue);
    }
  });

  test('Hand Stall bottle unlocks at 6 and shaker at 7', () {
    expect(
      requiredLevelFor(
        const PracticeVariant(
          movementName: 'Hand Stall',
          trainingProp: TrainingProp.bottle,
        ),
      ),
      6,
    );
    expect(
      requiredLevelFor(
        const PracticeVariant(
          movementName: 'Hand Stall',
          trainingProp: TrainingProp.shaker,
        ),
      ),
      7,
    );
  });

  test('Body Grip, Wrist Stall, and Double Forearm map to the new levels', () {
    expect(
      requiredLevelFor(
        const PracticeVariant(
          movementName: 'Body Grip',
          trainingProp: TrainingProp.bottle,
        ),
      ),
      5,
    );
    expect(
      requiredLevelFor(
        const PracticeVariant(
          movementName: 'Wrist Stall',
          trainingProp: TrainingProp.bottle,
        ),
      ),
      14,
    );
    expect(
      requiredLevelFor(
        const PracticeVariant(
          movementName: 'Wrist Stall',
          trainingProp: TrainingProp.shaker,
        ),
      ),
      15,
    );
    expect(
      requiredLevelFor(
        const PracticeVariant(
          movementName: 'Double Forearm Stall',
          trainingProp: TrainingProp.bottle,
        ),
      ),
      20,
    );
  });

  test('level 21 unlocks no new content; nextUnlock after 20 is null', () {
    expect(allPersonallyLevelUnlockedVariants(20).length, 20);
    expect(allPersonallyLevelUnlockedVariants(21).length, 20);
    expect(nextUnlockAfterLevel(20), isNull);
    expect(nextUnlockAfterLevel(21), isNull);
  });

  test('xpRemainingToNextUnlock uses GamificationRules', () {
    expect(xpRemainingToNextUnlock(80), GamificationRules.xpPerLevel - 80);
    final level20Xp = GamificationRules.xpPerLevel * 19;
    expect(xpRemainingToNextUnlock(level20Xp), 0);
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

  group('movement identity reveal', () {
    test('single-prop reveal uses that movement\'s milestone level', () {
      expect(earliestRequiredLevelForMovement('Normal Grip'), 1);
      expect(earliestRequiredLevelForMovement("Bartender's Grip"), 2);
      expect(earliestRequiredLevelForMovement('Claw Grip'), 4);
      expect(earliestRequiredLevelForMovement('Body Grip'), 5);
      expect(earliestRequiredLevelForMovement('Bottle in a tin'), 19);
      expect(earliestRequiredLevelForMovement('Double Forearm Stall'), 20);

      expect(isMovementIdentityRevealed('Normal Grip', 1), isTrue);
      expect(isMovementIdentityRevealed("Bartender's Grip", 1), isFalse);
      expect(isMovementIdentityRevealed("Bartender's Grip", 2), isTrue);
    });

    test('dual-prop movement uses the earliest official variant level', () {
      expect(earliestRequiredLevelForMovement('Hand Stall'), 6);
      expect(earliestRequiredLevelForMovement('One Finger Stall'), 8);
      expect(earliestRequiredLevelForMovement('Elbow Stall'), 12);
      expect(earliestRequiredLevelForMovement('Wrist Stall'), 14);
    });

    test('movement remains hidden below the earliest threshold', () {
      expect(isMovementIdentityRevealed('Hand Stall', 5), isFalse);
      expect(isMovementIdentityRevealed('One Finger Stall', 7), isFalse);
      expect(isMovementIdentityRevealed('Wrist Stall', 13), isFalse);
    });

    test('movement becomes revealed at the exact earliest threshold', () {
      expect(isMovementIdentityRevealed('Hand Stall', 6), isTrue);
      expect(isMovementIdentityRevealed('Hand Stall', 7), isTrue);
      expect(isMovementIdentityRevealed('One Finger Stall', 8), isTrue);
      expect(isMovementIdentityRevealed('Wrist Stall', 14), isTrue);
    });

    test('unknown movement and unresolved level fail closed', () {
      expect(earliestRequiredLevelForMovement('Unknown Move'), isNull);
      expect(isMovementIdentityRevealed('Unknown Move', 20), isFalse);
      expect(isMovementIdentityRevealed('Hand Stall', null), isFalse);
      expect(isMovementIdentityRevealed('Normal Grip', null), isFalse);
    });
  });
}
