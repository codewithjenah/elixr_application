import '../../data/models/movement.dart';
import '../../data/models/training_prop.dart';

const _bottleOrShaker = [TrainingProp.bottle, TrainingProp.shaker];

const movementCatalog = <Movement>[
  Movement(
    name: 'Normal Grip',
    difficulty: 'Easy',
    description: 'Hold the bottle with a standard overhand grip.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: "Bartender's Grip",
    difficulty: 'Easy',
    description: 'Pinch the neck with thumb and index finger.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Reverse Grip',
    difficulty: 'Easy',
    description: 'Hold the bottle with an underhand grip.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Claw Grip',
    difficulty: 'Easy',
    description:
        'Hold the upright bottle from above with curled fingers around the upper neck.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Hand Stall',
    difficulty: 'Medium',
    description: 'Balance the bottle on your open palm.',
    requiresHandsDetection: true,
    enabled: true,
    supportedProps: _bottleOrShaker,
  ),
  Movement(
    name: 'One Finger Stall',
    difficulty: 'Medium',
    description:
        'Balance the selected prop upright on the thenar eminence with the index finger extended horizontally.',
    requiresHandsDetection: true,
    enabled: true,
    supportedProps: _bottleOrShaker,
  ),
  Movement(
    name: 'Forearm Stall',
    difficulty: 'Medium',
    description: 'Balance the bottle on your forearm.',
    requiresHandsDetection: true,
    enabled: true,
    supportedProps: _bottleOrShaker,
  ),
  Movement(
    name: 'Elbow Stall',
    difficulty: 'Medium',
    description: 'Balance the bottle on your elbow crease.',
    requiresHandsDetection: true,
    enabled: true,
    supportedProps: _bottleOrShaker,
  ),
  Movement(
    name: 'Reverse Forearm Stall',
    difficulty: 'Hard',
    description:
        'Balance the bottle on the reverse forearm between the elbow and forearm midpoint.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Shoulder Stall',
    difficulty: 'Hard',
    description: 'Balance the bottle steadily on either shoulder.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Double Hand Stall',
    difficulty: 'Hard',
    description:
        'Balance two bottles simultaneously, with one upright bottle on each open palm.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Bottle in a tin',
    difficulty: 'Hard',
    description:
        'Balance an upright bottle steadily on a horizontally held cocktail shaker.',
    requiresHandsDetection: true,
    enabled: true,
    supportedProps: [TrainingProp.bottleAndShaker],
  ),
];

List<Movement> movementsByDifficulty(String difficulty) {
  return movementCatalog.where((m) => m.difficulty == difficulty).toList();
}

/// One enabled catalog step: a movement practiced with one of its
/// [Movement.supportedProps], in catalog order then prop-declaration order.
class PracticeCatalogStep {
  const PracticeCatalogStep({required this.movement, required this.prop});

  final Movement movement;
  final TrainingProp prop;
}

/// Flattened enabled practice sequence. Medium stalls contribute both
/// Bottle and Cocktail Shaker steps so Session Complete Next visits each.
List<PracticeCatalogStep> enabledPracticeSteps() {
  return [
    for (final movement in movementCatalog)
      if (movement.enabled)
        for (final prop in movement.supportedProps)
          PracticeCatalogStep(movement: movement, prop: prop),
  ];
}

/// Session Complete Next label. Includes the prop when the movement offers
/// a choice or uses a non-default prop, so Bottle vs Cocktail Shaker is
/// visible when advancing.
String nextPracticeLabel(Movement movement, TrainingProp prop) {
  final showProp =
      movement.supportedProps.length > 1 || prop != TrainingProp.bottle;
  if (!showProp) return movement.name;
  return '${movement.name} (${prop.displayLabel})';
}

/// Returns the next enabled (movement, prop) step after [name] + [prop].
///
/// Walks [enabledPracticeSteps]: catalog order, and within a movement the
/// declared [Movement.supportedProps] order (Bottle then Cocktail Shaker
/// for Medium stalls). Returns null when [name] is unknown, or when the
/// current step is last.
///
/// If [name] exists but [prop] is not a catalog step for that movement,
/// Next advances past the last step of [name] so progress is not stuck.
PracticeCatalogStep? nextEnabledPracticeAfter(String name, TrainingProp prop) {
  final steps = enabledPracticeSteps();
  var currentIndex = steps.indexWhere(
    (step) => step.movement.name == name && step.prop == prop,
  );
  if (currentIndex == -1) {
    var lastForName = -1;
    for (var i = 0; i < steps.length; i++) {
      if (steps[i].movement.name == name) lastForName = i;
    }
    if (lastForName == -1) return null;
    currentIndex = lastForName;
  }
  if (currentIndex + 1 >= steps.length) return null;
  return steps[currentIndex + 1];
}
