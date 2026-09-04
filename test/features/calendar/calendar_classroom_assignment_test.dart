import 'package:elixr_application/core/utils/manila_day.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/calendar/calendar_screen.dart';
import 'package:elixr_application/features/calendar/models/calendar_classroom_assignment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final due = DateTime.utc(2026, 9, 10, 16); // Sept 11, midnight Manila.

  CalendarClassroomAssignment item({
    AssignmentAttempt? submission,
    DateTime? now,
    DateTime? deadline,
    bool noDeadline = false,
  }) => CalendarClassroomAssignment(
    assignment: _assignment(noDeadline ? null : deadline ?? due),
    submission: submission,
    now: now ?? DateTime.utc(2026, 9, 10, 12),
  );

  test('places a UTC deadline on its Manila calendar day', () {
    expect(ManilaDay.dayKeyFor(item().dueAt!.toUtc()), '20260911');
  });

  test('uses friendly due and overdue wording for unsubmitted work', () {
    expect(item().statusLabel, 'Due');
    expect(item().isOutstanding, isTrue);
    expect(item(now: DateTime.utc(2026, 9, 10, 16, 1)).statusLabel, 'Overdue');
    expect(item(now: DateTime.utc(2026, 9, 10, 16, 1)).isOverdue, isTrue);
  });

  test('preserves on-time, late, and checked submission semantics', () {
    expect(
      item(
        submission: _attempt(
          AssignmentAttemptStatus.submitted,
          due.subtract(const Duration(seconds: 1)),
        ),
      ).statusLabel,
      'Submitted on time',
    );
    expect(
      item(
        submission: _attempt(
          AssignmentAttemptStatus.submitted,
          due.add(const Duration(seconds: 1)),
        ),
      ).statusLabel,
      'Submitted late',
    );
    final checked = item(
      submission: _attempt(AssignmentAttemptStatus.checked, due),
    );
    expect(checked.statusLabel, 'Submitted on time');
    expect(checked.isChecked, isTrue);
    expect(checked.isOutstanding, isFalse);
  });

  test('draft attempts never appear submitted and no deadline has no date', () {
    expect(
      item(
        submission: _attempt(AssignmentAttemptStatus.draft, null),
      ).statusLabel,
      'Due',
    );
    expect(item(noDeadline: true).dueAt, isNull);
  });

  test(
    'counts only outstanding overdue work due in the visible Manila month',
    () {
      final now = DateTime.utc(2026, 10, 20, 12);
      final visibleMonth = DateTime(2026, 10);
      final visibleOverdue = item(
        deadline: DateTime.utc(2026, 9, 30, 18), // October 1 in Manila.
        now: now,
      );
      final otherMonthOverdue = item(
        deadline: DateTime.utc(2026, 9, 15, 12),
        now: now,
      );
      final checked = item(
        deadline: DateTime.utc(2026, 10, 5, 12),
        now: now,
        submission: _attempt(
          AssignmentAttemptStatus.checked,
          DateTime.utc(2026, 10, 5, 11),
        ),
      );
      final items = [visibleOverdue, otherMonthOverdue, checked];

      expect(classroomDueInMonth(visibleOverdue, visibleMonth), isTrue);
      expect(classroomDueInMonth(otherMonthOverdue, visibleMonth), isFalse);
      expect(checked.isOutstanding, isFalse);
      expect(
        items
            .where(
              (item) =>
                  classroomDueInMonth(item, visibleMonth) && item.isOutstanding,
            )
            .length,
        1,
      );
      expect(
        items
            .where(
              (item) =>
                  classroomDueInMonth(item, visibleMonth) && item.isOverdue,
            )
            .length,
        1,
      );
    },
  );
}

GroupAssignment _assignment(DateTime? dueAt) => GroupAssignment(
  id: 'assignment',
  teacherId: 'teacher',
  groupId: 'group',
  movementId: 'movement',
  revisionId: 'revision',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Bottle control',
  teacherDisplayName: 'Teacher',
  groupName: 'Class',
  dueAt: dueAt,
);

AssignmentAttempt _attempt(
  AssignmentAttemptStatus status,
  DateTime? submittedAt,
) => AssignmentAttempt(
  id: 'attempt',
  traineeId: 'trainee',
  teacherId: 'teacher',
  groupId: 'group',
  assignmentId: 'assignment',
  movementId: 'movement',
  revisionId: 'revision',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
  status: status,
  submittedAt: submittedAt,
);
