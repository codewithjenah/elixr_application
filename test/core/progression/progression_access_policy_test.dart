import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/core/progression/progression_access.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const normalGripBottle = PracticeVariant(
    movementName: 'Normal Grip',
    trainingProp: TrainingProp.bottle,
  );
  const handStallShaker = PracticeVariant(
    movementName: 'Hand Stall',
    trainingProp: TrainingProp.shaker,
  );
  const elbowShaker = PracticeVariant(
    movementName: 'Elbow Stall',
    trainingProp: TrainingProp.shaker,
  );

  test('personal loading when level unknown does not require assignment', () {
    expect(
      evaluatePersonal(
        variant: normalGripBottle,
        currentLevel: null,
        tutorialCompleted: false,
      ),
      ProgressionAccessResult.personalLoading,
    );
  });

  test('personal loading when tutorial unknown', () {
    expect(
      evaluatePersonal(
        variant: normalGripBottle,
        currentLevel: 1,
        tutorialCompleted: null,
      ),
      ProgressionAccessResult.personalLoading,
    );
  });

  test('personal locked below level', () {
    expect(
      evaluatePersonal(
        variant: elbowShaker,
        currentLevel: 3,
        tutorialCompleted: true,
      ),
      ProgressionAccessResult.personalLocked,
    );
  });

  test('personal learn then ready', () {
    expect(
      evaluatePersonal(
        variant: handStallShaker,
        currentLevel: 7,
        tutorialCompleted: false,
      ),
      ProgressionAccessResult.personalLearn,
    );
    expect(
      evaluatePersonal(
        variant: handStallShaker,
        currentLevel: 7,
        tutorialCompleted: true,
      ),
      ProgressionAccessResult.personalReady,
    );
  });

  test('assignment ready ignores personal level', () {
    expect(
      evaluateAssignment(
        variant: elbowShaker,
        assignmentGrant: const AssignmentGrant(isAuthorized: true),
        tutorialCompleted: true,
      ),
      ProgressionAccessResult.assignmentReady,
    );
  });

  test('assignment learn when tutorial incomplete', () {
    expect(
      evaluateAssignment(
        variant: elbowShaker,
        assignmentGrant: const AssignmentGrant(isAuthorized: true),
        tutorialCompleted: false,
      ),
      ProgressionAccessResult.assignmentLearn,
    );
  });

  test('unauthorized assignment is invalid even if tutorial done', () {
    expect(
      evaluateAssignment(
        variant: elbowShaker,
        assignmentGrant: const AssignmentGrant(isAuthorized: false),
        tutorialCompleted: true,
      ),
      ProgressionAccessResult.invalid,
    );
  });

  test('assignment loading when grant unknown', () {
    expect(
      evaluateAssignment(
        variant: elbowShaker,
        assignmentGrant: null,
        tutorialCompleted: true,
      ),
      ProgressionAccessResult.assignmentLoading,
    );
  });

  test('unsupported variant is invalid', () {
    expect(
      evaluatePersonal(
        variant: const PracticeVariant(
          movementName: 'Not A Real Move',
          trainingProp: TrainingProp.bottle,
        ),
        currentLevel: 99,
        tutorialCompleted: true,
      ),
      ProgressionAccessResult.invalid,
    );
  });

  test(
    'catalog-supported but non-progression prop still invalid for personal',
    () {
      // All enabled catalog props are progression milestones today; guard the
      // policy against a future catalog-only prop by using a bogus pairing that
      // resolvePracticeVariant rejects.
      expect(
        evaluatePersonal(
          variant: const PracticeVariant(
            movementName: 'Normal Grip',
            trainingProp: TrainingProp.shaker,
          ),
          currentLevel: 99,
          tutorialCompleted: true,
        ),
        ProgressionAccessResult.invalid,
      );
    },
  );

  test('personalReadyVariants includes only ready movement+prop pairs', () {
    final ready = personalReadyVariants(
      currentLevel: 5,
      tutorialCompleted: (_) => true,
    );
    expect(
      ready.any(
        (variant) =>
            variant.movementName == 'Normal Grip' &&
            variant.trainingProp == TrainingProp.bottle,
      ),
      isTrue,
    );
    expect(
      ready.any(
        (variant) =>
            variant.movementName == 'Body Grip' &&
            variant.trainingProp == TrainingProp.bottle,
      ),
      isTrue,
    );
    expect(
      ready.any(
        (variant) =>
            variant.movementName == 'Hand Stall' &&
            variant.trainingProp == TrainingProp.bottle,
      ),
      isFalse,
    );
    expect(
      ready.any(
        (variant) =>
            variant.movementName == 'Hand Stall' &&
            variant.trainingProp == TrainingProp.shaker,
      ),
      isFalse,
    );
    expect(
      ready.any((variant) => variant.movementName == 'Elbow Stall'),
      isFalse,
    );
  });
}
