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
    difficulty: 'Easy',
    description: 'Balance the bottle on your open palm.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Arm Stall',
    difficulty: 'Easy',
    description: 'Balance the bottle on your forearm.',
    requiresHandsDetection: false,
    enabled: true,
  ),
  Movement(
    name: 'Elbow Stall',
    difficulty: 'Easy',
    description: 'Balance the bottle on your elbow crease.',
    requiresHandsDetection: false,
    enabled: true,
  ),
  Movement(
    name: 'Clip',
    difficulty: 'Medium',
    description: 'Quick catch between thumb and fingers.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Tap',
    difficulty: 'Medium',
    description: 'Tap the bottle with controlled rhythm.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Basket',
    difficulty: 'Medium',
    description: 'Catch the bottle in a basket hold.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Switching',
    difficulty: 'Medium',
    description: 'Transfer the bottle between hands smoothly.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Front Flip',
    difficulty: 'Medium',
    description: 'Flip the bottle forward and catch.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Side Flip',
    difficulty: 'Medium',
    description: 'Flip the bottle sideways and catch.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Quick Chest Pass',
    difficulty: 'Hard',
    description: 'Pass the bottle across your chest to the other hand.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Staggered Switch',
    difficulty: 'Hard',
    description: 'Cross the bottle through center, then switch hands.',
    requiresHandsDetection: true,
    enabled: true,
  ),
  Movement(
    name: 'Elbow Tap',
    difficulty: 'Hard',
    description: 'Tap the bottle against your elbow with controlled contact.',
    requiresHandsDetection: false,
    enabled: true,
  ),
];

List<Movement> movementsByDifficulty(String difficulty) {
  return movementCatalog.where((m) => m.difficulty == difficulty).toList();
}
