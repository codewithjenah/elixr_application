import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movements_controller.dart';
import 'package:elixr_application/features/teacher/movements/teacher_reviews_pane.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'submitted review detail scrolls to its grading controls and returns to reviews',
    (tester) async {
      _setConstrainedViewport(tester);
      final controller = await _buildController(
        status: AssignmentAttemptStatus.submitted,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(controller));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await _scrollTo(tester, find.text('Save review'));
      expect(find.text('Save review'), findsOneWidget);

      await _scrollToTop(tester);
      await tester.tap(find.text('Back to reviews'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.selectedReview, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'checked review detail scrolls to the result action without overflowing',
    (tester) async {
      _setConstrainedViewport(tester);
      final controller = await _buildController(
        status: AssignmentAttemptStatus.checked,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(controller));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await _scrollTo(tester, find.text('Send to student'));
      expect(find.text('Update review'), findsOneWidget);
      expect(find.text('Send to student'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

void _setConstrainedViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1216, 552);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<TeacherMovementsController> _buildController({
  required AssignmentAttemptStatus status,
}) async {
  final groups = InMemoryGroupRepository();
  final movements = InMemoryTeacherMovementRepository();
  final assignments = InMemoryClassroomAssignmentRepository();
  const group = ElixrGroup(
    id: 'group-1',
    teacherId: 'teacher-1',
    name: 'BSHM 4A',
    status: ElixrGroupStatus.active,
  );
  groups.seedGroup(group);
  groups.seedMembership(
    const GroupMembership(
      id: 'group-1_trainee-1',
      groupId: 'group-1',
      teacherId: 'teacher-1',
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      teacherDisplayName: 'Grace Hopper',
      status: GroupMembershipStatus.approved,
    ),
  );
  assignments.seedAssignment(
    const GroupAssignment(
      id: 'assignment-1',
      teacherId: 'teacher-1',
      groupId: 'group-1',
      movementId: 'movement-1',
      revisionId: 'revision-1',
      origin: MovementOrigin.teacherCreated,
      assessmentMode: AssessmentMode.teacherReviewed,
      status: GroupAssignmentStatus.active,
      displayTitle: 'Bottle Balance',
      teacherDisplayName: 'Grace Hopper',
      groupName: 'BSHM 4A',
      maxScore: 100,
    ),
  );
  assignments.seedAttempt(
    AssignmentAttempt(
      id: 'attempt-1',
      traineeId: 'trainee-1',
      teacherId: 'teacher-1',
      groupId: 'group-1',
      assignmentId: 'assignment-1',
      movementId: 'movement-1',
      revisionId: 'revision-1',
      origin: MovementOrigin.teacherCreated,
      assessmentMode: AssessmentMode.teacherReviewed,
      attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
      status: status,
      createdAt: DateTime.utc(2026, 8, 30),
      submittedAt: DateTime.utc(2026, 8, 30),
      gradeScore: status == AssignmentAttemptStatus.checked ? 90 : null,
      gradeMaxScore: status == AssignmentAttemptStatus.checked ? 100 : null,
      checkedAt: status == AssignmentAttemptStatus.checked
          ? DateTime.utc(2026, 8, 30)
          : null,
      reviewRevision: status == AssignmentAttemptStatus.checked ? 1 : null,
    ),
  );
  final controller = TeacherMovementsController(
    teacherId: 'teacher-1',
    teacherDisplayName: 'Grace Hopper',
    groupRepository: groups,
    movementRepository: movements,
    assignmentRepository: assignments,
  );
  await controller.start();
  await controller.selectReview(
    status == AssignmentAttemptStatus.submitted
        ? controller.reviewQueue.single
        : controller.attempts.single,
  );
  return controller;
}

Widget _host(TeacherMovementsController controller) {
  return FluentApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: const TextScaler.linear(1.25)),
      child: child!,
    ),
    home: ScaffoldPage(
      content: TeacherReviewsPane(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    ),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder target) {
  return tester.dragUntilVisible(
    target,
    _detailScrollable(),
    const Offset(0, -200),
  );
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(_detailScrollable(), const Offset(0, 400));
  await tester.pumpAndSettle();
}

Finder _detailScrollable() {
  return find
      .descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )
      .first;
}
