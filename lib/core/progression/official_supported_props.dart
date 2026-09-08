import '../constants/movements.dart';
import 'practice_variant.dart';

/// All official enabled catalog movement + supported prop pairs.
///
/// Flutter source of truth for cross-language parity tests against Rules and
/// Cloud Functions allowlists.
Set<PracticeVariant> officialSupportedPracticeVariants() {
  return {
    for (final movement in movementCatalog)
      if (movement.enabled)
        for (final prop in movement.supportedProps)
          PracticeVariant(movementName: movement.name, trainingProp: prop),
  };
}
