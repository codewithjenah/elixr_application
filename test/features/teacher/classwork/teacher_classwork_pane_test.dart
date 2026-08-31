import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/classwork/teacher_classwork_controller.dart';
import 'package:elixr_application/features/teacher/classwork/teacher_classwork_pane.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FailingAttemptPaneRepository
    extends InMemoryClassroomAssignmentRepository {
  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  }) {
    return Stream<List<AssignmentAttempt>>.error(StateError('offline'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;
  late TeacherClassworkController controller;

  setUp(() async {
    groups = InMemoryGroupRepository();
    assignments = InMemoryClassroomAssignmentRepository();
    groups.seedGroup(
      const ElixrGroup(
        id: 'group',
        teacherId: 'teacher',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
    );
    groups.seedMembership(
      GroupMembership(
        id: GroupMembership.documentId(groupId: 'group', traineeId: 'student'),
        groupId: 'group',
        teacherId: 'teacher',
        traineeId: 'student',
        traineeDisplayName: 'Ada Lovelace',
        teacherDisplayName: 'Grace Hopper',
        status: GroupMembershipStatus.approved,
      ),
    );
    groups.seedMembership(
      GroupMembership(
        id: GroupMembership.documentId(groupId: 'group', traineeId: 'alan'),
        groupId: 'group',
        teacherId: 'teacher',
        traineeId: 'alan',
        traineeDisplayName: 'Alan Turing',
        teacherDisplayName: 'Grace Hopper',
        status: GroupMembershipStatus.approved,
      ),
    );
    assignments.seedAssignment(
      const GroupAssignment(
        id: 'assignment',
        teacherId: 'teacher',
        groupId: 'group',
        movementId: 'movement',
        revisionId: 'revision',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Tin Balance',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        maxScore: 100,
      ),
    );
    controller = TeacherClassworkController(
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      groupId: 'group',
      groupRepository: groups,
      assignmentRepository: assignments,
      initialAssignmentId: 'assignment',
    );
    await controller.start();
  });

  tearDown(() {
    controller.dispose();
    groups.dispose();
    assignments.dispose();
  });

  Future<void> pumpPane(
    WidgetTester tester,
    Size size, {
    String? Function(String traineeId)? profilePictureUrlFor,
    ValueChanged<GroupAssignment>? onEditAssignment,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: Padding(
          padding: const EdgeInsets.all(16),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => TeacherAssignmentWorkPane(
              controller: controller,
              profilePictureUrlFor: profilePictureUrlFor,
              onEditAssignment: onEditAssignment,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('assignment roster uses the full workspace before drill-down', (
    tester,
  ) async {
    await pumpPane(tester, const Size(1280, 720));

    expect(
      find.byKey(const Key('teacher_classwork_assignment_roster_workspace')),
      findsOneWidget,
    );
    expect(
      find.text('Select a student to view their submitted work.'),
      findsNothing,
    );
    expect(find.text('Ada Lovelace'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('teacher_classwork_student_student')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('teacher_classwork_not_turned_in')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('teacher_classwork_submission_workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('teacher_classwork_roster')), findsNothing);
  });

  testWidgets('targeted assignment roster excludes untargeted classmates', (
    tester,
  ) async {
    assignments.seedAssignment(
      assignments.assignments['assignment']!.copyWith(
        audience: AssignmentAudience.individualStudent(const ['student']),
      ),
    );
    await pumpPane(tester, const Size(1280, 720));

    expect(
      find.byKey(const Key('teacher_classwork_student_student')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('teacher_classwork_student_alan')),
      findsNothing,
    );
    expect(find.textContaining('Individual: Ada Lovelace'), findsOneWidget);
  });

  testWidgets('roster rows expose semantics and support keyboard activation', (
    tester,
  ) async {
    await pumpPane(tester, const Size(1280, 720));

    expect(
      find.bySemanticsLabel('Ada Lovelace, profile picture, Not turned in'),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('teacher_classwork_submission_workspace')),
      findsOneWidget,
    );
  });

  testWidgets(
    'narrow classroom layout drills into work and remains page-scrollable',
    (tester) async {
      await pumpPane(tester, const Size(700, 720));

      expect(find.byKey(const Key('teacher_classwork_roster')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('teacher_classwork_student_student')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('teacher_classwork_submission_workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_classwork_review_scroll')),
        findsNothing,
      );

      await controller.selectTrainee(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('teacher_classwork_roster')), findsOneWidget);
    },
  );

  testWidgets('roster and review header reuse profile avatars and initials', (
    tester,
  ) async {
    await pumpPane(
      tester,
      const Size(1280, 720),
      profilePictureUrlFor: (traineeId) =>
          traineeId == 'student' ? 'https://example.test/ada.png' : null,
    );

    final ada = tester.widget<ProfileAvatarWidget>(
      find.byKey(const Key('teacher_classwork_avatar_student')),
    );
    final alan = tester.widget<ProfileAvatarWidget>(
      find.byKey(const Key('teacher_classwork_avatar_alan')),
    );
    expect(ada.networkImageUrl, 'https://example.test/ada.png');
    expect(ada.initials, 'AL');
    expect(alan.networkImageUrl, isNull);
    expect(alan.initials, 'AT');

    await tester.tap(
      find.byKey(const Key('teacher_classwork_student_student')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    final selected = tester.widget<ProfileAvatarWidget>(
      find.byKey(const Key('teacher_classwork_selected_avatar')),
    );
    expect(selected.networkImageUrl, 'https://example.test/ada.png');
    expect(selected.initials, 'AL');
  });

  testWidgets('maximum score is metadata and editing uses settings action', (
    tester,
  ) async {
    GroupAssignment? edited;
    await pumpPane(
      tester,
      const Size(1280, 720),
      onEditAssignment: (assignment) => edited = assignment,
    );

    expect(find.textContaining('Maximum 100'), findsOneWidget);
    expect(find.text('Save maximum'), findsNothing);
    expect(find.byType(TextBox), findsNothing);
    await tester.tap(
      find.byKey(const Key('teacher_classwork_edit_assignment')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(edited?.id, 'assignment');
  });

  testWidgets('submitted work opens in the shared grading detail', (
    tester,
  ) async {
    assignments.seedAttempt(
      AssignmentAttempt(
        id: 'submission',
        traineeId: 'student',
        teacherId: 'teacher',
        groupId: 'group',
        assignmentId: 'assignment',
        movementId: 'movement',
        revisionId: 'revision',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.submitted,
        submittedAt: DateTime.utc(2026, 8, 30),
        videoStoragePath:
            'assignment_submissions/teacher/group/assignment/student/submission.mp4',
        videoContentType: 'video/mp4',
        videoSizeBytes: 2048,
        videoDurationMs: 4000,
        videoExpiresAt: DateTime.utc(2026, 9, 30),
      ),
    );
    await pumpPane(tester, const Size(1280, 720));
    await tester.tap(
      find.byKey(const Key('teacher_classwork_student_student')),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('teacher_classwork_submission_detail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('submission_desktop_two_column')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('teacher_classwork_roster')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('teacher_classwork_grade')),
      '92',
    );
    await tester.enterText(
      find.byKey(const Key('teacher_classwork_feedback')),
      'Strong control.',
    );
    final saveReview = find.byKey(const Key('teacher_classwork_save_review'));
    await tester.ensureVisible(saveReview);
    await tester.tap(saveReview);
    await tester.pumpAndSettle();

    final checked = await assignments.getAttempt(attemptId: 'submission');
    expect(checked?.status, AssignmentAttemptStatus.checked);
    expect(checked?.gradeScore, 92);
    expect(checked?.reviewFeedback, 'Strong control.');
    expect(find.text('Score: 92/100 • 92%'), findsOneWidget);
  });

  testWidgets('attempt load failure never reports work as not turned in', (
    tester,
  ) async {
    controller.dispose();
    assignments.dispose();
    assignments = _FailingAttemptPaneRepository();
    assignments.seedAssignment(
      const GroupAssignment(
        id: 'assignment',
        teacherId: 'teacher',
        groupId: 'group',
        movementId: 'movement',
        revisionId: 'revision',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Tin Balance',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        maxScore: 100,
      ),
    );
    controller = TeacherClassworkController(
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      groupId: 'group',
      groupRepository: groups,
      assignmentRepository: assignments,
      initialAssignmentId: 'assignment',
    );
    await controller.start();
    await pumpPane(tester, const Size(1280, 720));

    expect(
      find.byKey(const Key('teacher_classwork_attempts_error')),
      findsOneWidget,
    );
    expect(find.text('Not turned in'), findsNothing);
  });
}
