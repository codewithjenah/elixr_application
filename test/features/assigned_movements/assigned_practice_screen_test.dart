import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/assigned_movements/assigned_practice_screen.dart';
import 'package:elixr_application/features/assigned_movements/template_scored_practice_screen.dart';
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('assigned practice fails closed for empty assignmentId', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: const AssignedPracticeScreen(assignmentId: '  '),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('This assignment link is not valid.'), findsOneWidget);
  });

  testWidgets('assigned practice requires approved classroom authorization', (
    tester,
  ) async {
    final auth =
        AuthService(
          repository: _ShellAuth(),
          awaitInitialAuthState: () async {},
        )..seedAuthenticatedUser(
          User(
            id: 'trainee-1',
            firstName: 'Ada',
            lastName: 'Lovelace',
            email: 'ada@example.com',
            role: User.roleTrainee,
          ),
        );
    addTearDown(auth.dispose);

    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    groups.seedGroup(
      const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher-1',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
    );
    groups.seedMembership(
      GroupMembership(
        id: GroupMembership.documentId(groupId: 'g1', traineeId: 'trainee-1'),
        groupId: 'g1',
        teacherId: 'teacher-1',
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        teacherDisplayName: 'Grace Hopper',
        status: GroupMembershipStatus.pending,
      ),
    );

    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(
      const GroupAssignment(
        id: 'asg1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        movementId: 'official_hand_stall',
        revisionId: 'official_hand_stall_v1',
        origin: MovementOrigin.officialElixr,
        assessmentMode: AssessmentMode.officialGuided,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Hand Stall',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        officialMovementName: 'Hand Stall',
      ),
    );

    final router = GoRouter(
      initialLocation: '/assigned-practice/asg1',
      routes: [
        GoRoute(
          path: '/assigned-practice/:assignmentId',
          builder: (context, state) => AssignedPracticeScreen(
            assignmentId: state.pathParameters['assignmentId'] ?? '',
          ),
        ),
        GoRoute(
          path: '/assigned-movements',
          builder: (context, state) => const Text('home'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groups),
          Provider<ClassroomAssignmentRepository>.value(value: assignments),
          ChangeNotifierProvider(create: (_) => TutorialProgressService()),
        ],
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Classroom Authorization'), findsOneWidget);
  });

  testWidgets(
    'incomplete official lesson is sent with assignmentId then revalidated',
    (tester) async {
      final auth =
          AuthService(
            repository: _ShellAuth(),
            awaitInitialAuthState: () async {},
          )..seedAuthenticatedUser(
            User(
              id: 'trainee-1',
              firstName: 'Ada',
              lastName: 'Lovelace',
              email: 'ada@example.com',
              role: User.roleTrainee,
            ),
          );
      addTearDown(auth.dispose);

      final groups = InMemoryGroupRepository();
      addTearDown(groups.dispose);
      groups.seedGroup(
        const ElixrGroup(
          id: 'g1',
          teacherId: 'teacher-1',
          name: 'BSHM 4A',
          status: ElixrGroupStatus.active,
        ),
      );
      groups.seedMembership(
        GroupMembership(
          id: GroupMembership.documentId(groupId: 'g1', traineeId: 'trainee-1'),
          groupId: 'g1',
          teacherId: 'teacher-1',
          traineeId: 'trainee-1',
          traineeDisplayName: 'Ada Lovelace',
          teacherDisplayName: 'Grace Hopper',
          status: GroupMembershipStatus.approved,
        ),
      );

      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(assignments.dispose);
      assignments.seedAssignment(
        const GroupAssignment(
          id: 'asg1',
          teacherId: 'teacher-1',
          groupId: 'g1',
          movementId: 'official_hand_stall',
          revisionId: 'official_hand_stall_v1',
          origin: MovementOrigin.officialElixr,
          assessmentMode: AssessmentMode.officialGuided,
          status: GroupAssignmentStatus.active,
          displayTitle: 'Hand Stall',
          teacherDisplayName: 'Grace Hopper',
          groupName: 'BSHM 4A',
          officialMovementName: 'Hand Stall',
        ),
      );

      String? lastLocation;
      final router = GoRouter(
        initialLocation: '/assigned-practice/asg1',
        routes: [
          GoRoute(
            path: '/assigned-practice/:assignmentId',
            builder: (context, state) => AssignedPracticeScreen(
              assignmentId: state.pathParameters['assignmentId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/learn/movement/:movementName',
            builder: (context, state) {
              lastLocation = state.uri.toString();
              return Text(
                'lesson:${state.uri.queryParameters['assignmentId']}',
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: auth),
            Provider<GroupRepository>.value(value: groups),
            Provider<ClassroomAssignmentRepository>.value(value: assignments),
            ChangeNotifierProvider(create: (_) => TutorialProgressService()),
          ],
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.text('lesson:asg1'), findsOneWidget);
      expect(lastLocation, contains('assignmentId=asg1'));
      expect(lastLocation, contains('Hand%20Stall'));
    },
  );

  testWidgets('template-scored assignment opens template practice', (
    tester,
  ) async {
    final auth =
        AuthService(
          repository: _ShellAuth(),
          awaitInitialAuthState: () async {},
        )..seedAuthenticatedUser(
          User(
            id: 'trainee-1',
            firstName: 'Ada',
            lastName: 'Lovelace',
            email: 'ada@example.com',
            role: User.roleTrainee,
          ),
        );
    addTearDown(auth.dispose);

    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    groups.seedGroup(
      const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher-1',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
    );
    groups.seedMembership(
      GroupMembership(
        id: GroupMembership.documentId(groupId: 'g1', traineeId: 'trainee-1'),
        groupId: 'g1',
        teacherId: 'teacher-1',
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        teacherDisplayName: 'Grace Hopper',
        status: GroupMembershipStatus.approved,
      ),
    );

    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(
      const GroupAssignment(
        id: 'asgTpl',
        teacherId: 'teacher-1',
        groupId: 'g1',
        movementId: 'tm1',
        revisionId: 'rev1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.templateScored,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Classroom Wrist Stall',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        allowedProp: TrainingProp.bottle,
        assessmentSpec: AssessmentSpec(laterality: AssessmentLaterality.either),
      ),
    );

    final settings = SettingsService();
    addTearDown(settings.dispose);

    final router = GoRouter(
      initialLocation: '/assigned-practice/asgTpl',
      routes: [
        GoRoute(
          path: '/assigned-practice/:assignmentId',
          builder: (context, state) => AssignedPracticeScreen(
            assignmentId: state.pathParameters['assignmentId'] ?? '',
          ),
        ),
        GoRoute(
          path: '/assigned-movements',
          builder: (context, state) => const Text('home'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groups),
          Provider<ClassroomAssignmentRepository>.value(value: assignments),
          ChangeNotifierProvider(create: (_) => TutorialProgressService()),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
        ],
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byType(TemplateScoredPracticeScreen), findsOneWidget);
    expect(find.byType(LivePracticeScreen), findsNothing);
  });
}

class _ShellAuth implements AuthRepositoryBase {
  @override
  Future<User?> loadPersistedUser() async => null;

  @override
  Future<void> clearCurrentUser() async {}

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<User?> refreshAuthenticatedUser() async => null;

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> deleteAccount({required String password}) async {}

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();
}
