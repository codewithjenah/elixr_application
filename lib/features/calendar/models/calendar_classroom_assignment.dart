import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/assignment_review_state.dart';
import '../../../data/models/group_assignment.dart';

/// Thin, derived classroom projection for the trainee Planner.
///
/// This deliberately keeps assignment visibility and submission truth in the
/// classroom repositories and their canonical data contracts.
class CalendarClassroomAssignment {
  const CalendarClassroomAssignment({
    required this.assignment,
    required this.submission,
    required this.now,
  });

  final GroupAssignment assignment;
  final AssignmentAttempt? submission;
  final DateTime now;

  DateTime? get dueAt => assignment.dueAt;

  AssignmentDeadlineState get deadlineState =>
      AssignmentReviewSemantics.deadlineStateFor(
        assignment: assignment,
        attempt: submission,
        now: now,
      );

  bool get isChecked =>
      AssignmentReviewSemantics.reviewState(submission) ==
      AssignmentReviewState.checked;

  /// Friendly trainee-facing wording. `missing` is intentionally never shown
  /// before a deadline; it means the work is still due.
  String get statusLabel => switch (deadlineState) {
    AssignmentDeadlineState.noDeadline => 'Submitted',
    AssignmentDeadlineState.missing => 'Due',
    AssignmentDeadlineState.overdue => 'Overdue',
    AssignmentDeadlineState.submittedOnTime => 'Submitted on time',
    AssignmentDeadlineState.submittedLate => 'Submitted late',
  };
}
