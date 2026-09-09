import 'package:elixr_application/core/progression/assignment_prop_resolution.dart';
import 'package:elixr_application/core/progression/practice_variant.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy missing allowed_prop uses first supported Medium Bottle', () {
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Hand Stall',
        storedAllowedProp: null,
      ),
      TrainingProp.bottle,
    );
  });

  test('legacy Bottle in a tin uses combined prop', () {
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Bottle in a tin',
        storedAllowedProp: null,
      ),
      TrainingProp.bottleAndShaker,
    );
  });

  test('stored supported prop is honored', () {
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Elbow Stall',
        storedAllowedProp: TrainingProp.shaker,
      ),
      TrainingProp.shaker,
    );
  });

  test('stored unsupported prop is invalid', () {
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Normal Grip',
        storedAllowedProp: TrainingProp.shaker,
      ),
      isNull,
    );
  });

  test('practiceVariantForOfficialAssignment builds exact variant', () {
    expect(
      practiceVariantForOfficialAssignment(
        officialMovementName: 'Forearm Stall',
        storedAllowedProp: TrainingProp.shaker,
      ),
      const PracticeVariant(
        movementName: 'Forearm Stall',
        trainingProp: TrainingProp.shaker,
      ),
    );
  });

  test('Body Grip official assignment resolves Bottle', () {
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Body Grip',
        storedAllowedProp: TrainingProp.bottle,
      ),
      TrainingProp.bottle,
    );
    expect(
      practiceVariantForOfficialAssignment(
        officialMovementName: 'Body Grip',
        storedAllowedProp: TrainingProp.bottle,
      ),
      const PracticeVariant(
        movementName: 'Body Grip',
        trainingProp: TrainingProp.bottle,
      ),
    );
  });

  test('Wrist Stall official assignment persists Bottle or Shaker', () {
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Wrist Stall',
        storedAllowedProp: TrainingProp.bottle,
      ),
      TrainingProp.bottle,
    );
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Wrist Stall',
        storedAllowedProp: TrainingProp.shaker,
      ),
      TrainingProp.shaker,
    );
    expect(
      practiceVariantForOfficialAssignment(
        officialMovementName: 'Wrist Stall',
        storedAllowedProp: TrainingProp.shaker,
      ),
      const PracticeVariant(
        movementName: 'Wrist Stall',
        trainingProp: TrainingProp.shaker,
      ),
    );
  });

  test('Double Forearm Stall official assignment resolves Bottle', () {
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Double Forearm Stall',
        storedAllowedProp: TrainingProp.bottle,
      ),
      TrainingProp.bottle,
    );
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Double Forearm Stall',
        storedAllowedProp: TrainingProp.shaker,
      ),
      isNull,
    );
  });

  test('Body Grip unsupported shaker is invalid', () {
    expect(
      resolvedAllowedPropForOfficialAssignment(
        officialMovementName: 'Body Grip',
        storedAllowedProp: TrainingProp.shaker,
      ),
      isNull,
    );
  });
}
