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
        'Balance the selected prop upright on one extended index finger.',
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
