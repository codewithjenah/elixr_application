import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/teacher/classwork/teacher_gradebook.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ada = GroupMembership(
    id: 'g_ada',
    groupId: 'g',
    teacherId: 't',
    traineeId: 'ada',
    traineeDisplayName: 'Ada',
    teacherDisplayName: 'Teacher',
    status: GroupMembershipStatus.approved,
  );
  const alan = GroupMembership(
    id: 'g_alan',
    groupId: 'g',
    teacherId: 't',
    traineeId: 'alan',
    traineeDisplayName: 'Alan',
    teacherDisplayName: 'Teacher',
    status: GroupMembershipStatus.approved,
  );
  const jenah = GroupMembership(
    id: 'g_jenah',
    groupId: 'g',
    teacherId: 't',
    traineeId: 'jenah',
    traineeDisplayName: 'Jenah',
    teacherDisplayName: 'Teacher',
    status: GroupMembershipStatus.approved,
  );
  final now = DateTime.utc(2026, 9, 2);

  GroupAssignment assignment({
    MovementOrigin origin = MovementOrigin.teacherCreated,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
    DateTime? dueAt,
  }) => GroupAssignment(
    id: 'a',
    teacherId: 't',
    groupId: 'g',
    movementId: 'm',
    revisionId: 'r',
    origin: origin,
    assessmentMode: origin == MovementOrigin.officialElixr
        ? AssessmentMode.officialGuided
        : AssessmentMode.teacherReviewed,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Hand Stall',
    teacherDisplayName: 'Teacher',
    groupName: 'Class',
    officialMovementName: origin == MovementOrigin.officialElixr
        ? 'Hand Stall'
        : null,
    maxScore: origin == MovementOrigin.teacherCreated ? 20 : null,
    audience: audience,
    dueAt: dueAt,
  );

  AssignmentAttempt attempt({
    required String traineeId,
    required MovementOrigin origin,
    required AssignmentAttemptKind kind,
    required AssignmentAttemptStatus status,
    int? score,
    int? maximum,
    RubricAssessment? rubric,
  }) => AssignmentAttempt(
    id: 'attempt-$traineeId',
    traineeId: traineeId,
    teacherId: 't',
    groupId: 'g',
    assignmentId: 'a',
    movementId: 'm',
    revisionId: 'r',
    origin: origin,
    assessmentMode: origin == MovementOrigin.officialElixr
        ? AssessmentMode.officialGuided
        : AssessmentMode.teacherReviewed,
    attemptKind: kind,
    status: status,
    gradeScore: score,
    gradeMaxScore: maximum,
    rubric: rubric,
    submittedAt: status == AssignmentAttemptStatus.submitted ? now : null,
    checkedAt: status == AssignmentAttemptStatus.checked ? now : null,
    reviewUpdatedAt: status == AssignmentAttemptStatus.checked ? now : null,
    reviewRevision: status == AssignmentAttemptStatus.checked ? 1 : null,
  );

  TeacherGradebookCell cell(
    GroupMembership student,
    GroupAssignment work, {
    AssignmentAttempt? attempt,
    bool unavailable = false,
  }) => TeacherGradebookSemantics.cellFor(
    membership: student,
    assignment: work,
    attempt: attempt,
    attemptUnavailable: unavailable,
    now: now,
  );

  test('targeted assignment never marks non-recipients missing or overdue', () {
    final work = assignment(
      audience: AssignmentAudience.selectedStudents(const ['ada', 'alan']),
      dueAt: DateTime.utc(2026, 9, 1),
    );
    expect(cell(ada, work).state, TeacherGradebookCellState.overdue);
    expect(cell(alan, work).state, TeacherGradebookCellState.overdue);
    final outside = cell(jenah, work);
    expect(outside.state, TeacherGradebookCellState.notAssigned);
    expect(outside.isActionable, isFalse);
  });

  test(
    'teacher checked score and pending review use canonical presentation',
    () {
      final work = assignment();
      final checked = cell(
        ada,
        work,
        attempt: attempt(
          traineeId: 'ada',
          origin: MovementOrigin.teacherCreated,
          kind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.checked,
          score: 18,
          maximum: 20,
        ),
      );
      expect((checked.label, checked.detail), ('18/20', '90%'));
      expect(
        cell(
          alan,
          work,
          attempt: attempt(
            traineeId: 'alan',
            origin: MovementOrigin.teacherCreated,
            kind: AssignmentAttemptKind.teacherReviewSubmission,
            status: AssignmentAttemptStatus.submitted,
          ),
        ).state,
        TeacherGradebookCellState.toReview,
      );
    },
  );

  test(
    'missing, overdue, unavailable, and official rubric results stay distinct',
    () {
      expect(
        cell(ada, assignment(dueAt: DateTime.utc(2026, 9, 3))).state,
        TeacherGradebookCellState.missing,
      );
      expect(
        cell(ada, assignment(), unavailable: true).state,
        TeacherGradebookCellState.unavailable,
      );
      final official = cell(
        ada,
        assignment(origin: MovementOrigin.officialElixr),
        attempt: attempt(
          traineeId: 'ada',
          origin: MovementOrigin.officialElixr,
          kind: AssignmentAttemptKind.practicePointer,
          status: AssignmentAttemptStatus.submitted,
          rubric: const RubricAssessment(
            technique: 3,
            stability: 3,
            completion: 2,
            propPositioning: 2,
          ),
        ),
      );
      expect(
        (official.label, official.detail, official.state),
        ('10/12', '83.3%', TeacherGradebookCellState.scored),
      );
    },
  );
}
