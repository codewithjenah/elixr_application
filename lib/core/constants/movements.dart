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
    name: 'Tap',
    difficulty: 'Hard',
    description: 'Tap the bottle with controlled rhythm.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Basket',
    difficulty: 'Hard',
    description: 'Catch the bottle in a basket hold.',
    requiresHandsDetection: true,
    enabled: true,
  ),
];

List<Movement> movementsByDifficulty(String difficulty) {
  return movementCatalog.where((m) => m.difficulty == difficulty).toList();
}
