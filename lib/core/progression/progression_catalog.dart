import '../constants/gamification_rules.dart';
import '../constants/movements.dart';
import '../../data/models/movement.dart';
import '../../data/models/training_prop.dart';
import 'practice_variant.dart';

/// One personal content unlock milestone (Level 1–16).
class ProgressionMilestone {
  const ProgressionMilestone({
    required this.requiredLevel,
    required this.variant,
  });

  final int requiredLevel;
  final PracticeVariant variant;
}

/// Exactly sixteen content milestones. Levels 17+ add no official variants.
const progressionMilestones = <ProgressionMilestone>[
  ProgressionMilestone(
    requiredLevel: 1,
    variant: PracticeVariant(
      movementName: 'Normal Grip',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 2,
    variant: PracticeVariant(
      movementName: "Bartender's Grip",
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 3,
    variant: PracticeVariant(
      movementName: 'Reverse Grip',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 4,
    variant: PracticeVariant(
      movementName: 'Claw Grip',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 5,
    variant: PracticeVariant(
      movementName: 'Hand Stall',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 6,
    variant: PracticeVariant(
      movementName: 'Hand Stall',
      trainingProp: TrainingProp.shaker,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 7,
    variant: PracticeVariant(
      movementName: 'One Finger Stall',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 8,
    variant: PracticeVariant(
      movementName: 'One Finger Stall',
      trainingProp: TrainingProp.shaker,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 9,
    variant: PracticeVariant(
      movementName: 'Forearm Stall',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 10,
    variant: PracticeVariant(
      movementName: 'Forearm Stall',
      trainingProp: TrainingProp.shaker,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 11,
    variant: PracticeVariant(
      movementName: 'Elbow Stall',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 12,
    variant: PracticeVariant(
      movementName: 'Elbow Stall',
      trainingProp: TrainingProp.shaker,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 13,
    variant: PracticeVariant(
      movementName: 'Reverse Forearm Stall',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 14,
    variant: PracticeVariant(
      movementName: 'Shoulder Stall',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 15,
    variant: PracticeVariant(
      movementName: 'Double Hand Stall',
      trainingProp: TrainingProp.bottle,
    ),
  ),
  ProgressionMilestone(
    requiredLevel: 16,
    variant: PracticeVariant(
      movementName: 'Bottle in a tin',
      trainingProp: TrainingProp.bottleAndShaker,
    ),
  ),
];

/// Resolves [variant] against the official catalog. Returns null when the
/// movement is unknown or the prop is not supported.
PracticeCatalogStep? resolvePracticeVariant(PracticeVariant variant) {
  Movement? movement;
  for (final candidate in movementCatalog) {
    if (candidate.name == variant.movementName) {
      movement = candidate;
      break;
    }
  }
  if (movement == null) return null;
  if (!movement.supportedProps.contains(variant.trainingProp)) return null;
  return PracticeCatalogStep(movement: movement, prop: variant.trainingProp);
}

/// Resolves strict route inputs to one canonical official catalog step.
///
/// Route parameters must use the exact movement name and prop protocol value.
/// Missing values, display labels, and unsupported combinations fail closed.
PracticeCatalogStep? resolveStrictPracticeRouteVariant({
  required String? movementName,
  required String? propProtocolValue,
}) {
  if (movementName == null || movementName.isEmpty) return null;
  final prop = TrainingProp.tryParseStrict(propProtocolValue);
  if (prop == null || propProtocolValue != prop.protocolValue) return null;
  return resolvePracticeVariant(
    PracticeVariant(movementName: movementName, trainingProp: prop),
  );
}

/// Personal required level for [variant], or null when not in the progression.
int? requiredLevelFor(PracticeVariant variant) {
  for (final milestone in progressionMilestones) {
    if (milestone.variant == variant) return milestone.requiredLevel;
  }
  return null;
}

bool isLevelUnlocked(PracticeVariant variant, int level) {
  final required = requiredLevelFor(variant);
  if (required == null) return false;
  return level >= required;
}

/// Next content unlock after the trainee has reached [level], or null at 16+.
PracticeVariant? nextUnlockAfterLevel(int level) {
  for (final milestone in progressionMilestones) {
    if (milestone.requiredLevel > level) return milestone.variant;
  }
  return null;
}

/// XP still needed to reach the next content-unlock level, or `0` at Level 16+.
int xpRemainingToNextUnlock(int totalXp) {
  final level = GamificationRules.levelForXp(totalXp);
  if (nextUnlockAfterLevel(level) == null) return 0;
  return GamificationRules.xpPerLevel - GamificationRules.xpIntoLevel(totalXp);
}

List<PracticeVariant> allPersonallyLevelUnlockedVariants(int level) {
  return [
    for (final milestone in progressionMilestones)
      if (level >= milestone.requiredLevel) milestone.variant,
  ];
}

/// Earliest personal level that reveals [movementName]'s identity.
///
/// Dual-prop movements use the minimum required level across official
/// variants. Unknown names return null (fail closed).
int? earliestRequiredLevelForMovement(String movementName) {
  int? earliest;
  for (final milestone in progressionMilestones) {
    if (milestone.variant.movementName != movementName) continue;
    final required = milestone.requiredLevel;
    if (earliest == null || required < earliest) {
      earliest = required;
    }
  }
  return earliest;
}

/// Whether a trainee at [currentLevel] may see [movementName]'s identity.
///
/// Unresolved [currentLevel] and unknown movements fail closed.
bool isMovementIdentityRevealed(String movementName, int? currentLevel) {
  if (currentLevel == null) return false;
  final required = earliestRequiredLevelForMovement(movementName);
  if (required == null) return false;
  return currentLevel >= required;
}
