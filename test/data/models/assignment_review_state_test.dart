import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:elixr_application/data/models/assignment_review_state.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final due = DateTime.utc(2026, 9, 1, 17);
  final beforeDue = DateTime.utc(2026, 9, 1, 16, 50);
  final afterDue = DateTime.utc(2026, 9, 1, 17, 10);

  test('deadline classification uses submission time, not review time', () {
    expect(
      AssignmentReviewSemantics.deadlineState(
        dueAt: due,
        submittedAt: beforeDue,
        now: DateTime.utc(2026, 9, 5),
      ),
      AssignmentDeadlineState.submittedOnTime,
    );
    expect(
      AssignmentReviewSemantics.deadlineState(
        dueAt: due,
        submittedAt: due,
        now: afterDue,
      ),
      AssignmentDeadlineState.submittedOnTime,
    );
    expect(
      AssignmentReviewSemantics.deadlineState(
        dueAt: due,
        submittedAt: afterDue,
        now: afterDue,
      ),
      AssignmentDeadlineState.submittedLate,
    );
  });

  test('missing and overdue classification uses an injected clock', () {
    expect(
      AssignmentReviewSemantics.deadlineState(
        dueAt: due,
        submittedAt: null,
        now: beforeDue,
      ),
      AssignmentDeadlineState.missing,
    );
    expect(
      AssignmentReviewSemantics.deadlineState(
        dueAt: due,
        submittedAt: null,
        now: afterDue,
      ),
      AssignmentDeadlineState.overdue,
    );
    expect(
      AssignmentReviewSemantics.deadlineState(
        dueAt: null,
        submittedAt: beforeDue,
        now: afterDue,
      ),
      AssignmentDeadlineState.noDeadline,
    );
    expect(
      AssignmentReviewSemantics.deadlineState(
        dueAt: null,
        submittedAt: null,
        now: afterDue,
      ),
      AssignmentDeadlineState.missing,
    );
  });

  test('canonical submitted work is pending until checked', () {
    final submitted = _attempt(AssignmentAttemptStatus.submitted);
    expect(
      AssignmentReviewSemantics.reviewState(submitted),
      AssignmentReviewState.toReview,
    );
    expect(
      AssignmentReviewSemantics.isActionablePending(
        submitted,
        now: DateTime.utc(2026, 9, 2),
      ),
      isTrue,
    );
    expect(
      AssignmentReviewSemantics.reviewState(
        _attempt(AssignmentAttemptStatus.checked),
      ),
      AssignmentReviewState.checked,
    );
    expect(
      AssignmentReviewSemantics.reviewState(null),
      AssignmentReviewState.missing,
    );
  });
}

AssignmentAttempt _attempt(AssignmentAttemptStatus status) => AssignmentAttempt(
  id: assignmentAttemptIdForCanonicalTeacherReviewSubmission(
    assignmentId: 'assignment',
    traineeId: 'student',
  ),
  traineeId: 'student',
  teacherId: 'teacher',
  groupId: 'group',
  assignmentId: 'assignment',
  movementId: 'movement',
  revisionId: 'revision',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
  status: status,
  submittedAt: DateTime.utc(2026, 9, 1, 16),
  videoStoragePath: 'assignment_submissions/clip.mp4',
  videoExpiresAt: DateTime.utc(2026, 10, 1),
);
