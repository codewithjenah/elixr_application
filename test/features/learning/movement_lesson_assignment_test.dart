import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/learning/movement_lesson.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _UnusedAuth extends Fake implements AuthRepositoryBase {}

class _ReadyTutorials extends TutorialProgressService {
  @override
  bool get isInitialized => true;

  @override
  bool hasCompletedLesson(String movement, TrainingProp prop) => true;
}

void main() {
  test('assigned lesson paths keep assignmentId out of a return URL', () {
    final lesson = AppRoutePaths.movementLesson(
      movement: 'Claw Grip',
      difficulty: 'Easy',
      prop: 'bottle',
      assignmentId: 'asg1',
    );
    expect(lesson, contains('/learn/movement/'));
    expect(lesson, contains('assignmentId=asg1'));
    expect(lesson.contains('returnUrl='), isFalse);
    expect(AppRoutePaths.assignedPractice('asg1'), '/assigned-practice/asg1');
    expect(
      AppRoutePaths.assignmentIdFromAssignedPractice('/assigned-practice/asg1'),
      'asg1',
    );
  });

  testWidgets('assignment lesson preserves assignmentId in the lesson UI', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth =
        AuthService(
          repository: _UnusedAuth(),
          awaitInitialAuthState: () async {},
        )..seedAuthenticatedUser(
          const User(
            id: 'trainee-1',
            firstName: 'Ada',
            lastName: 'Lovelace',
            email: 'ada@example.com',
            role: User.roleTrainee,
          ),
        );
    addTearDown(auth.dispose);

    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(
      const GroupAssignment(
        id: 'asg1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        movementId: 'official_claw_grip',
        revisionId: 'official_claw_grip_v1',
        origin: MovementOrigin.officialElixr,
        assessmentMode: AssessmentMode.officialGuided,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Claw Grip',
        teacherDisplayName: 'Coach',
        groupName: 'Class',
        officialMovementName: 'Claw Grip',
        allowedProp: TrainingProp.bottle,
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<ClassroomAssignmentRepository>.value(value: assignments),
          ChangeNotifierProvider<TutorialProgressService>(
            create: (_) => _ReadyTutorials(),
          ),
        ],
        child: FluentApp(
          theme: AppTheme.dark,
          home: const MovementLessonScreen(
            movement: 'Claw Grip',
            difficulty: 'Easy',
            prop: TrainingProp.bottle,
            assignmentId: 'asg1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Back to assignment'), findsOneWidget);
    expect(find.text('Back to tutorials'), findsNothing);
    expect(find.text('Start guided practice'), findsOneWidget);
  });

  testWidgets('bare assignmentId without grant is rejected', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: const MovementLessonScreen(
          movement: 'Claw Grip',
          difficulty: 'Easy',
          prop: TrainingProp.bottle,
          assignmentId: 'asg-forged',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('This assignment lesson is not available.'), findsOneWidget);
    expect(find.text('Start guided practice'), findsNothing);
  });

  testWidgets(
    'teacher-created assignment cannot unlock a mismatched catalog lesson',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auth =
          AuthService(
            repository: _UnusedAuth(),
            awaitInitialAuthState: () async {},
          )..seedAuthenticatedUser(
            const User(
              id: 'trainee-1',
              firstName: 'Ada',
              lastName: 'Lovelace',
              email: 'ada@example.com',
              role: User.roleTrainee,
            ),
          );
      addTearDown(auth.dispose);

      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(assignments.dispose);
      assignments.seedAssignment(
        const GroupAssignment(
          id: 'asg-teacher',
          teacherId: 'teacher-1',
          groupId: 'g1',
          movementId: 'tm1',
          revisionId: 'tm1_v1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          status: GroupAssignmentStatus.active,
          displayTitle: 'Tin Balance',
          teacherDisplayName: 'Coach',
          groupName: 'Class',
          allowedProp: TrainingProp.shaker,
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<ClassroomAssignmentRepository>.value(value: assignments),
          ],
          child: FluentApp(
            theme: AppTheme.dark,
            home: const MovementLessonScreen(
              movement: 'Claw Grip',
              difficulty: 'Easy',
              prop: TrainingProp.bottle,
              assignmentId: 'asg-teacher',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('This assignment lesson is not available.'),
        findsOneWidget,
      );
      expect(find.text('Start guided practice'), findsNothing);
    },
  );
}
