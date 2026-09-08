import '../constants/movements.dart';
import '../../data/models/movement.dart';
import '../../data/models/training_prop.dart';
import 'practice_variant.dart';

/// Resolves the exact prop for an official assignment.
///
/// New-format assignments store [storedAllowedProp]. Legacy official
/// assignments without `allowed_prop` fall back to the movement's first
/// supported prop (Medium → Bottle; Bottle in a tin → combined).
TrainingProp? resolvedAllowedPropForOfficialAssignment({
  required String officialMovementName,
  required TrainingProp? storedAllowedProp,
}) {
  Movement? movement;
  for (final candidate in movementCatalog) {
    if (candidate.name == officialMovementName) {
      movement = candidate;
      break;
    }
  }
  if (movement == null || movement.supportedProps.isEmpty) return null;

  if (storedAllowedProp != null) {
    if (!movement.supportedProps.contains(storedAllowedProp)) return null;
    return storedAllowedProp;
  }
  return movement.supportedProps.first;
}

PracticeVariant? practiceVariantForOfficialAssignment({
  required String officialMovementName,
  required TrainingProp? storedAllowedProp,
}) {
  final prop = resolvedAllowedPropForOfficialAssignment(
    officialMovementName: officialMovementName,
    storedAllowedProp: storedAllowedProp,
  );
  if (prop == null) return null;
  return PracticeVariant(
    movementName: officialMovementName,
    trainingProp: prop,
  );
}
