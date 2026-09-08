import 'practice_variant.dart';
import 'progression_catalog.dart';

/// Context-specific progression/access outcome for router and UI.
enum ProgressionAccessResult {
  /// Personal decision blocked: XP/level or tutorial state unknown.
  personalLoading,

  /// Assignment decision blocked: grant or tutorial state unknown.
  assignmentLoading,

  /// Unknown/unsupported variant, unauthorized assignment, or mismatch.
  invalid,

  /// Below required personal level.
  personalLocked,

  /// Level unlocked; exact tutorial incomplete.
  personalLearn,

  /// Level unlocked; exact tutorial complete.
  personalReady,

  /// Valid assignment-scoped access; exact tutorial incomplete.
  assignmentLearn,

  /// Valid assignment-scoped access; exact tutorial complete.
  assignmentReady,
}

/// Already-authenticated assignment authorization outcome for one variant.
///
/// Callers must set [isAuthorized] only after confirming assignment existence,
/// trainee recipient eligibility, accessibility, and movement/prop match.
class AssignmentGrant {
  const AssignmentGrant({required this.isAuthorized});

  final bool isAuthorized;
}

/// Pure personal access evaluation. Does not fetch XP, tutorials, or assignments.
ProgressionAccessResult evaluatePersonal({
  required PracticeVariant variant,
  required int? currentLevel,
  required bool? tutorialCompleted,
}) {
  if (resolvePracticeVariant(variant) == null) {
    return ProgressionAccessResult.invalid;
  }
  if (currentLevel == null || tutorialCompleted == null) {
    return ProgressionAccessResult.personalLoading;
  }
  final required = requiredLevelFor(variant);
  if (required == null || currentLevel < required) {
    return ProgressionAccessResult.personalLocked;
  }
  return tutorialCompleted
      ? ProgressionAccessResult.personalReady
      : ProgressionAccessResult.personalLearn;
}

/// Pure assignment access evaluation. Does not fetch authorization itself.
ProgressionAccessResult evaluateAssignment({
  required PracticeVariant variant,
  required AssignmentGrant? assignmentGrant,
  required bool? tutorialCompleted,
}) {
  if (resolvePracticeVariant(variant) == null) {
    return ProgressionAccessResult.invalid;
  }
  if (assignmentGrant == null || tutorialCompleted == null) {
    return ProgressionAccessResult.assignmentLoading;
  }
  if (!assignmentGrant.isAuthorized) {
    return ProgressionAccessResult.invalid;
  }
  return tutorialCompleted
      ? ProgressionAccessResult.assignmentReady
      : ProgressionAccessResult.assignmentLearn;
}
