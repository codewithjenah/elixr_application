import 'dart:io';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/activity_learning_material.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/activity_learning_material_repository.dart';
import 'package:elixr_application/features/assigned_movements/assignment_detail_controller.dart';
import 'package:elixr_application/features/assigned_movements/assignment_detail_screen.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _MaterialRepository implements ActivityLearningMaterialRepository {
  _MaterialRepository(this.materials);
  final List<ActivityLearningMaterial> materials;
  final List<ActivityLearningMaterial> openCalls = [];

  @override
  Future<ActivityLearningMaterial> addLink({
    required String assignmentId,
    required String displayName,
    required Uri url,
  }) => throw UnimplementedError();
  @override
  Future<ActivityMaterialUpload> beginUpload({
    required String assignmentId,
    required ActivityLearningMaterialType type,
    required String displayName,
    required String declaredContentType,
    required int sizeBytes,
  }) => throw UnimplementedError();
  @override
  Future<ActivityMaterialUploadStatus> getUploadStatus({
    required String uploadId,
  }) => throw UnimplementedError();
  @override
  Future<List<ActivityLearningMaterial>> list({
    required String assignmentId,
  }) async => materials;
  @override
  Future<File> openFile(ActivityLearningMaterial material) {
    openCalls.add(material);
    return Future.error(StateError('missing'));
  }

  @override
  Future<void> remove({
    required String assignmentId,
    required String materialId,
  }) => throw UnimplementedError();
  @override
  Future<void> uploadStagedFile({
    required ActivityMaterialUpload upload,
    required File file,
  }) => throw UnimplementedError();
}

void main() {
  testWidgets(
    'opening learning material does not create or start an Activity attempt',
    (tester) async {
      final groups = InMemoryGroupRepository();
      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(groups.dispose);
      addTearDown(assignments.dispose);
      const material = ActivityLearningMaterial(
        id: 'material-1',
        assignmentId: 'asg-a',
        type: ActivityLearningMaterialType.pdf,
        displayName: 'Safety.pdf',
        storagePath: 'protected/path',
      );
      final materials = _MaterialRepository(const [material]);
      final controller =
          AssignmentDetailController(
              assignmentId: 'asg-a',
              traineeId: 'trainee-1',
              groupRepository: groups,
              assignmentRepository: assignments,
            )
            ..assignment = const GroupAssignment(
              id: 'asg-a',
              teacherId: 'teacher-1',
              groupId: 'group-1',
              movementId: 'official_hand_stall',
              revisionId: 'official_hand_stall_v1',
              origin: MovementOrigin.officialElixr,
              assessmentMode: AssessmentMode.officialGuided,
              status: GroupAssignmentStatus.active,
              displayTitle: 'Hand Stall',
              teacherDisplayName: 'Grace Hopper',
              groupName: 'BSHM 4A',
              officialMovementName: 'Hand Stall',
            )
            ..authorized = true;
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        Provider<ActivityLearningMaterialRepository>.value(
          value: materials,
          child: FluentApp(
            theme: AppTheme.dark,
            home: AssignmentDetailScreen(
              assignmentId: 'asg-a',
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pump();

      expect(materials.openCalls, [material]);
      expect(controller.attempts, isEmpty);
      expect(
        find.text(
          'This material is no longer available or could not be opened.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'assignment detail uses current teacher public avatar with initials fallback',
    (tester) async {
      final groups = InMemoryGroupRepository();
      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(groups.dispose);
      addTearDown(assignments.dispose);
      final controller =
          AssignmentDetailController(
              assignmentId: 'asg-a',
              traineeId: 'trainee-1',
              groupRepository: groups,
              assignmentRepository: assignments,
            )
            ..assignment = const GroupAssignment(
              id: 'asg-a',
              teacherId: 'teacher-1',
              groupId: 'group-1',
              movementId: 'official_hand_stall',
              revisionId: 'official_hand_stall_v1',
              origin: MovementOrigin.officialElixr,
              assessmentMode: AssessmentMode.officialGuided,
              status: GroupAssignmentStatus.active,
              displayTitle: 'Hand Stall',
              teacherDisplayName: 'Grace Hopper',
              groupName: 'BSHM 4A',
              officialMovementName: 'Hand Stall',
            )
            ..authorized = true
            ..teacherProfile = const PublicProfile(
              userId: 'teacher-1',
              displayName: 'Grace Hopper',
              visibility: ProfileVisibility.public,
              profilePictureUrl: 'https://example.test/grace.png',
            );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: AssignmentDetailScreen(
            assignmentId: 'asg-a',
            controller: controller,
          ),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<ProfileAvatarWidget>(
        find.byKey(const Key('assignment_detail_teacher_avatar')),
      );
      expect(avatar.networkImageUrl, 'https://example.test/grace.png');
      expect(avatar.initials, 'GH');

      controller.teacherProfile = const PublicProfile(
        userId: 'teacher-1',
        displayName: 'Grace Hopper',
        visibility: ProfileVisibility.public,
      );
      controller.notifyListeners();
      await tester.pump();
      final fallback = tester.widget<ProfileAvatarWidget>(
        find.byKey(const Key('assignment_detail_teacher_avatar')),
      );
      expect(fallback.networkImageUrl, isNull);
      expect(fallback.initials, 'GH');
    },
  );

  testWidgets('assignment detail back uses the classroom work fallback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final groups = InMemoryGroupRepository();
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(groups.dispose);
    addTearDown(assignments.dispose);
    final controller =
        AssignmentDetailController(
            assignmentId: 'asg-a',
            traineeId: 'trainee-1',
            groupRepository: groups,
            assignmentRepository: assignments,
          )
          ..assignment = const GroupAssignment(
            id: 'asg-a',
            teacherId: 'teacher-1',
            groupId: 'group-1',
            movementId: 'official_hand_stall',
            revisionId: 'official_hand_stall_v1',
            origin: MovementOrigin.officialElixr,
            assessmentMode: AssessmentMode.officialGuided,
            status: GroupAssignmentStatus.active,
            displayTitle: 'Hand Stall',
            teacherDisplayName: 'Grace Hopper',
            groupName: 'BSHM 4A',
            officialMovementName: 'Hand Stall',
          )
          ..authorized = true;
    addTearDown(controller.dispose);

    final router = GoRouter(
      initialLocation: AppRoutePaths.assignmentDetail('asg-a'),
      routes: [
        GoRoute(
          path: '${AppRoutePaths.assignedMovements}/:assignmentId',
          builder: (context, state) => AssignmentDetailScreen(
            assignmentId: state.pathParameters['assignmentId']!,
            controller: controller,
          ),
        ),
        GoRoute(
          path: '${AppRoutePaths.teacherAccess}/:groupId/work',
          builder: (context, state) =>
              Text('classroom work:${state.pathParameters['groupId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      FluentApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('assignment_detail_back')));
    await tester.pumpAndSettle();

    expect(find.text('classroom work:group-1'), findsOneWidget);
  });

  testWidgets(
    'Teacher Activity history shows the selected checked submission criteria',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final groups = InMemoryGroupRepository();
      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(groups.dispose);
      addTearDown(assignments.dispose);
      final assessment = TeacherActivityAssessmentConfig.newActivityDefaults();
      final scores = {
        for (final criterion in assessment.rubric.criteria)
          criterion.id: criterion.maximumPoints,
      };
      final controller =
          AssignmentDetailController(
              assignmentId: 'activity',
              traineeId: 'trainee-1',
              groupRepository: groups,
              assignmentRepository: assignments,
            )
            ..assignment = GroupAssignment(
              id: 'activity',
              teacherId: 'teacher-1',
              groupId: 'group-1',
              movementId: 'movement-1',
              revisionId: 'revision-1',
              origin: MovementOrigin.teacherCreated,
              assessmentMode: AssessmentMode.teacherReviewed,
              status: GroupAssignmentStatus.active,
              displayTitle: 'Bottle control',
              teacherDisplayName: 'Grace Hopper',
              groupName: 'BSHM 4A',
              activityAssessment: assessment,
            )
            ..authorized = true
            ..attempts = [
              AssignmentAttempt(
                id: 'new-submission',
                traineeId: 'trainee-1',
                teacherId: 'teacher-1',
                groupId: 'group-1',
                assignmentId: 'activity',
                movementId: 'movement-1',
                revisionId: 'revision-1',
                origin: MovementOrigin.teacherCreated,
                assessmentMode: AssessmentMode.teacherReviewed,
                attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
                status: AssignmentAttemptStatus.submitted,
                submittedAt: DateTime.utc(2026, 9, 2),
                activityAssessmentSnapshot: assessment,
                assignmentConfigurationRevision: 1,
              ),
              AssignmentAttempt(
                id: 'checked-submission',
                traineeId: 'trainee-1',
                teacherId: 'teacher-1',
                groupId: 'group-1',
                assignmentId: 'activity',
                movementId: 'movement-1',
                revisionId: 'revision-1',
                origin: MovementOrigin.teacherCreated,
                assessmentMode: AssessmentMode.teacherReviewed,
                attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
                status: AssignmentAttemptStatus.checked,
                submittedAt: DateTime.utc(2026, 9, 1),
                checkedAt: DateTime.utc(2026, 9, 2),
                gradeScore: assessment.rubric.maximumScore,
                gradeMaxScore: assessment.rubric.maximumScore,
                reviewFeedback: 'Good work.',
                activityAssessmentSnapshot: assessment,
                assignmentConfigurationRevision: 1,
                criterionScores: scores,
              ),
            ];
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: AssignmentDetailScreen(
            assignmentId: 'activity',
            controller: controller,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Scoring criteria'), findsNothing);
      expect(find.text('Checked'), findsOneWidget);

      await tester.tap(find.text('Checked'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Scoring criteria'), findsOneWidget);
      expect(find.byKey(const Key('scoring_criteria_total')), findsOneWidget);
      expect(find.text('Good work.'), findsOneWidget);
      expect(find.text('No tries remaining'), findsNothing);
      // One label is the selected card's status and one is its history row.
      // There is no third standalone action/status pill below the card.
      expect(find.text('Checked'), findsNWidgets(2));
    },
  );
}
