import '../../data/models/movement.dart';

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
    name: 'Hand Stall',
    difficulty: 'Medium',
    description: 'Balance the bottle on your open palm.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Arm Stall',
    difficulty: 'Medium',
    description: 'Balance the bottle on your forearm.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Elbow Stall',
    difficulty: 'Medium',
    description: 'Balance the bottle on your elbow crease.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Upper Forearm Stall',
    difficulty: 'Hard',
    description:
        'Balance the bottle on the upper forearm between the elbow and forearm midpoint.',
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
    description: 'Balance the bottle steadily above both open palms.',
    requiresHandsDetection: true,
    enabled: true,
  ),
];

List<Movement> movementsByDifficulty(String difficulty) {
  return movementCatalog.where((m) => m.difficulty == difficulty).toList();
}
