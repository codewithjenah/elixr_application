import '../../../core/progression/progression_access.dart';

/// Presentation state for one exact variant in Build Your Set / Practice prefs.
enum PracticeSetlistSelectionState {
  selectable,
  learnFirst,
  locked,
  loading,
  unavailable,
}

PracticeSetlistSelectionState practiceSetlistSelectionState(
  ProgressionAccessResult access,
) {
  return switch (access) {
    ProgressionAccessResult.personalReady =>
      PracticeSetlistSelectionState.selectable,
    ProgressionAccessResult.personalLearn =>
      PracticeSetlistSelectionState.learnFirst,
    ProgressionAccessResult.personalLocked =>
      PracticeSetlistSelectionState.locked,
    ProgressionAccessResult.personalLoading =>
      PracticeSetlistSelectionState.loading,
    ProgressionAccessResult.invalid ||
    ProgressionAccessResult.assignmentLoading ||
    ProgressionAccessResult.assignmentLearn ||
    ProgressionAccessResult.assignmentReady =>
      PracticeSetlistSelectionState.unavailable,
  };
}

bool practiceSetlistCanAdd(PracticeSetlistSelectionState state) =>
    state == PracticeSetlistSelectionState.selectable;

bool practiceSetlistCanRemove(
  PracticeSetlistSelectionState state, {
  required bool selected,
}) => selected;

String? practiceSetlistStatusLabel(
  PracticeSetlistSelectionState state, {
  required int? requiredLevel,
}) {
  return switch (state) {
    PracticeSetlistSelectionState.selectable => null,
    PracticeSetlistSelectionState.learnFirst => 'Learn first',
    PracticeSetlistSelectionState.locked =>
      'Locked · Level ${requiredLevel ?? '?'}',
    PracticeSetlistSelectionState.loading => 'Checking access…',
    PracticeSetlistSelectionState.unavailable => 'Unavailable',
  };
}
