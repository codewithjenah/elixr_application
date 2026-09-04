import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/classwork/teacher_classwork_controller.dart';
import 'package:elixr_application/features/teacher/groups/teacher_group_detail_screen.dart';
import 'package:elixr_application/features/teacher/groups/teacher_groups_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'checked roster work opens its submitted detail and preserves hierarchy',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final groups = InMemoryGroupRepository();
      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(groups.dispose);
      addTearDown(assignments.dispose);
      final group = await groups.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSIT-4A',
      );
      final invite = await groups.getActiveGroupInvite(groupId: group.id);
      final membership = await groups.requestGroupJoin(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        code: invite!.normalizedCode,
      );
      await groups.approveMembership(
        membershipId: membership.id,
        teacherId: 'teacher-1',
      );
      final toReviewMembership = await groups.requestGroupJoin(
        traineeId: 'trainee-2',
        traineeDisplayName: 'Katherine Johnson',
        code: invite.normalizedCode,
      );
      await groups.approveMembership(
        membershipId: toReviewMembership.id,
        teacherId: 'teacher-1',
      );
      final assignment = await assignments.createOfficialAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: group,
        officialMovementName: 'Normal Grip',
      );
      final checkedAttempt = AssignmentAttempt(
        id: 'checked-submission',
        traineeId: membership.traineeId,
        teacherId: 'teacher-1',
        groupId: group.id,
        assignmentId: assignment.id,
        movementId: assignment.movementId,
        revisionId: assignment.revisionId,
        origin: MovementOrigin.officialElixr,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.checked,
        submittedAt: DateTime.utc(2026, 9, 1, 10),
        checkedAt: DateTime.utc(2026, 9, 2, 10),
        reviewUpdatedAt: DateTime.utc(2026, 9, 2, 10),
        reviewRevision: 1,
        gradeScore: 92,
        gradeMaxScore: 100,
        videoStoragePath: 'assignment_submissions/checked-submission.mp4',
        videoContentType: 'video/mp4',
        videoSizeBytes: 2048,
        videoDurationMs: 4000,
      );
      assignments.seedAttempt(checkedAttempt);
      final toReviewAttempt = AssignmentAttempt(
        id: 'to-review-submission',
        traineeId: toReviewMembership.traineeId,
        teacherId: 'teacher-1',
        groupId: group.id,
        assignmentId: assignment.id,
        movementId: assignment.movementId,
        revisionId: assignment.revisionId,
        origin: MovementOrigin.officialElixr,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.submitted,
        submittedAt: DateTime.utc(2026, 9, 3, 10),
        videoStoragePath: 'assignment_submissions/to-review-submission.mp4',
        videoContentType: 'video/mp4',
        videoSizeBytes: 2048,
        videoDurationMs: 4000,
      );
      assignments.seedAttempt(toReviewAttempt);
      final groupController = TeacherGroupsController(
        repository: groups,
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        ensureTeacherAuthorization: () async => true,
        assignmentRepository: assignments,
        watchAssignmentSummaries: false,
      );
      addTearDown(groupController.dispose);
      await groupController.startForGroup(group.id);
      final classworkControllers = <TeacherClassworkController>[];
      final openedClassworkUris = <Uri>[];
      TeacherClassworkController? reviewController;
      TeacherClassworkController createClassworkController(
        GoRouterState state,
      ) {
        openedClassworkUris.add(state.uri);
        final controller = TeacherClassworkController(
          teacherId: 'teacher-1',
          teacherDisplayName: 'Grace Hopper',
          groupId: group.id,
          groupRepository: groups,
          assignmentRepository: assignments,
          initialAssignmentId: state.pathParameters['assignmentId'],
          initialTraineeId: state.uri.queryParameters['traineeId'],
          approvedMembershipsProvider: () =>
              groupController.approvedMemberships,
          approvedMembershipsListenable: groupController,
        );
        classworkControllers.add(controller);
        if (state.uri.queryParameters['traineeId'] != null) {
          reviewController = controller;
        }
        controller.start();
        return controller;
      }

      addTearDown(() {
        for (final controller in classworkControllers) {
          controller.dispose();
        }
      });

      Widget detail(GoRouterState state) => Provider<GroupRepository>.value(
        value: groups,
        child: TeacherGroupDetailScreen(
          groupId: group.id,
          controller: groupController,
          classworkController: createClassworkController(state),
        ),
      );

      final router = GoRouter(
        initialLocation: AppRoutePaths.teacherGroupClasswork(
          group.id,
          assignment.id,
        ),
        routes: [
          GoRoute(
            path: AppRoutePaths.teacherGroups,
            builder: (context, state) => const Text('groups home'),
            routes: [
              GoRoute(
                path: ':groupId',
                builder: (context, state) => detail(state),
              ),
            ],
          ),
          GoRoute(
            path: '/teacher/groups/:groupId/classwork/:assignmentId',
            builder: (context, state) => detail(state),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      );
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(const Key('teacher_group_back')), findsNothing);
      expect(find.byKey(const Key('teacher_classwork_back')), findsOneWidget);
      expect(
        find.byKey(const Key('teacher_classwork_back_to_roster')),
        findsNothing,
      );

      await tester.tap(
        find.byKey(const Key('teacher_classwork_student_trainee-1')),
      );
      await tester.pump();
      // The in-memory repository uses non-replaying broadcast streams. Emit the
      // existing records once for the newly pushed production-style controller.
      assignments.seedAssignment(assignment);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const Key('teacher_classwork_attempts_loading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_classwork_not_turned_in')),
        findsNothing,
      );
      assignments.seedAttempt(checkedAttempt);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        openedClassworkUris,
        contains(
          Uri.parse(
            AppRoutePaths.teacherGroupClasswork(
              group.id,
              assignment.id,
              traineeId: membership.traineeId,
            ),
          ),
        ),
      );
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(reviewController?.selectedAssignmentId, assignment.id);
      expect(reviewController?.selectedTraineeId, membership.traineeId);
      expect(reviewController?.selectedAssignment?.id, assignment.id);
      expect(
        find.byKey(const Key('teacher_classwork_submission_workspace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_classwork_submission_detail')),
        findsOneWidget,
      );
      expect(find.text('Score: 92/100 • 92%'), findsOneWidget);
      expect(
        find.byKey(const Key('teacher_classwork_not_turned_in')),
        findsNothing,
      );
      expect(find.byKey(const Key('teacher_group_back')), findsNothing);
      expect(find.byKey(const Key('teacher_classwork_back')), findsNothing);
      expect(
        find.byKey(const Key('teacher_classwork_back_to_roster')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('teacher_classwork_back_to_roster')),
      );
      await tester.pump();
      assignments.seedAssignment(assignment);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('teacher_classwork_back')), findsOneWidget);
      expect(find.byKey(const Key('teacher_group_back')), findsNothing);

      await tester.tap(
        find.byKey(const Key('teacher_classwork_student_trainee-2')),
      );
      await tester.pump();
      assignments.seedAssignment(assignment);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      assignments.seedAttempt(toReviewAttempt);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const Key('teacher_classwork_submission_workspace')),
        findsOneWidget,
      );
      expect(find.text('Katherine Johnson'), findsOneWidget);
      expect(find.text('To Review'), findsWidgets);

      await tester.tap(
        find.byKey(const Key('teacher_classwork_back_to_roster')),
      );
      await tester.pump();
      assignments.seedAssignment(assignment);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('teacher_classwork_back')), findsOneWidget);

      await tester.tap(find.byKey(const Key('teacher_classwork_back')));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('teacher_group_back')), findsOneWidget);
      expect(find.byKey(const Key('teacher_classwork_back')), findsNothing);

      final directRouter = GoRouter(
        initialLocation: AppRoutePaths.teacherGroupClasswork(
          group.id,
          assignment.id,
          traineeId: membership.traineeId,
        ),
        routes: [
          GoRoute(
            path: AppRoutePaths.teacherGroups,
            builder: (context, state) => const Text('groups home'),
            routes: [
              GoRoute(
                path: ':groupId',
                builder: (context, state) => detail(state),
              ),
            ],
          ),
          GoRoute(
            path: '/teacher/groups/:groupId/classwork/:assignmentId',
            builder: (context, state) => detail(state),
          ),
        ],
      );
      addTearDown(directRouter.dispose);
      await tester.pumpWidget(
        FluentApp.router(theme: AppTheme.dark, routerConfig: directRouter),
      );
      await tester.pump();
      assignments.seedAssignment(assignment);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      assignments.seedAttempt(checkedAttempt);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const Key('teacher_classwork_submission_workspace')),
        findsOneWidget,
      );
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Score: 92/100 • 92%'), findsOneWidget);
      expect(
        find.byKey(const Key('teacher_classwork_not_turned_in')),
        findsNothing,
      );

      // The direct route resolves through the same query-parameter path as
      // a roster drill-down, without depending on its existing router stack.
      expect(
        openedClassworkUris,
        contains(
          Uri.parse(
            AppRoutePaths.teacherGroupClasswork(
              group.id,
              assignment.id,
              traineeId: membership.traineeId,
            ),
          ),
        ),
      );
    },
  );
}
