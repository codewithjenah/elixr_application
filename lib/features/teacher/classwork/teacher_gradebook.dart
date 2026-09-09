import 'package:elixr_core/models/group_membership.dart';

import '../../../data/models/assessment_score_display.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/assignment_review_state.dart';
import '../../../data/models/group_assignment.dart';

/// Presentation-only result for one approved student and one class assignment.
///
/// This is deliberately derived from the classroom controller's canonical
/// streams. It is not a grade record and must never be persisted.
enum TeacherGradebookCellState {
  notAssigned,
  unavailable,
  toReview,
  missing,
  overdue,
  scored,
  checked,
  completed,
  historical,
}

class TeacherGradebookCell {
  const TeacherGradebookCell({
    required this.studentId,
    required this.assignmentId,
    required this.state,
    required this.label,
    required this.detail,
    required this.isActionable,
  });

  final String studentId;
  final String assignmentId;
  final TeacherGradebookCellState state;
  final String label;
  final String? detail;
  final bool isActionable;

  String get semanticValue => detail == null ? label : '$label, $detail';
}

/// Centralizes gradebook semantics so the matrix cannot accidentally turn a
/// targeted-assignment non-recipient into a missing grade.
abstract final class TeacherGradebookSemantics {
  static TeacherGradebookCell cellFor({
    required GroupMembership membership,
    required GroupAssignment assignment,
    required AssignmentAttempt? attempt,
    required bool attemptUnavailable,
    required DateTime now,
  }) {
    final studentId = membership.traineeId;
    TeacherGradebookCell base(
      TeacherGradebookCellState state,
      String label, {
      String? detail,
      bool actionable = true,
    }) => TeacherGradebookCell(
      studentId: studentId,
      assignmentId: assignment.id,
      state: state,
      label: label,
      detail: detail,
      isActionable: actionable,
    );

    // Audience must be evaluated before missing/deadline semantics.
    if (!assignment.isAvailableToTrainee(studentId)) {
      return base(
        TeacherGradebookCellState.notAssigned,
        'Not assigned',
        actionable: false,
      );
    }
    if (attemptUnavailable) {
      return base(TeacherGradebookCellState.unavailable, 'Unavailable');
    }

    final reviewState = AssignmentReviewSemantics.reviewState(attempt);
    if (reviewState == AssignmentReviewState.missing) {
      final deadline = AssignmentReviewSemantics.deadlineStateFor(
        assignment: assignment,
        attempt: attempt,
        now: now,
      );
      return base(
        deadline == AssignmentDeadlineState.overdue
            ? TeacherGradebookCellState.overdue
            : TeacherGradebookCellState.missing,
        deadline == AssignmentDeadlineState.overdue ? 'Overdue' : 'Missing',
      );
    }
    if (reviewState == AssignmentReviewState.toReview) {
      return base(TeacherGradebookCellState.toReview, 'To Review');
    }

    final score = _scoreFor(assignment, attempt);
    if (score != null) {
      return base(TeacherGradebookCellState.scored, score.$1, detail: score.$2);
    }
    if (assignment.isRetiredTemplate) {
      return base(TeacherGradebookCellState.historical, 'Historical');
    }
    if (assignment.isTeacherCreated) {
      return base(TeacherGradebookCellState.checked, 'Checked');
    }
    return base(TeacherGradebookCellState.completed, 'Completed');
  }

  static (String, String)? _scoreFor(
    GroupAssignment assignment,
    AssignmentAttempt? attempt,
  ) {
    if (attempt == null) return null;
    if (assignment.isTeacherCreated &&
        attempt.isChecked &&
        attempt.gradeScore != null &&
        attempt.gradeMaxScore != null &&
        attempt.gradeMaxScore! > 0) {
      return _split(
        AssessmentScoreDisplay.teacherActivity(
          earned: attempt.gradeScore!,
          maximum: attempt.gradeMaxScore!,
        ),
      );
    }
    final rubricTotal = attempt.rubricTotal;
    if ((assignment.isOfficial || assignment.isRetiredTemplate) &&
        rubricTotal != null &&
        rubricTotal >= 0 &&
        rubricTotal <= 12) {
      return _split(AssessmentScoreDisplay.official(rubricTotal));
    }
    return null;
  }

  static (String, String) _split(String display) {
    final parts = display.split(' • ');
    return (parts.first, parts.length > 1 ? parts.last : '');
  }
}
