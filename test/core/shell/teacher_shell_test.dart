import 'package:elixr_application/core/router/app_router.dart';
import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/shell/teacher_shell.dart';
import 'package:elixr_application/core/widgets/app_shell.dart';
import 'package:elixr_application/data/repositories/assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/data/repositories/teacher_movement_repository.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/join_link_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _ShellTestAuthRepository implements AuthRepositoryBase {
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
    String? teacherAccessCode,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email, String? continueUrl}) async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {}

  @override
  Future<void> requestDeleteAccountEmailVerification({
    String confirmationCode = '',
    String? continueUrl,
  }) async {}

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

void main() {
  testWidgets('teacher shell renders six destinations', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth =
        AuthService(
          repository: _ShellTestAuthRepository(),
          awaitInitialAuthState: () async {},
        )..seedAuthenticatedUser(
          User(
            id: 'teacher-1',
            firstName: 'Tea',
            lastName: 'Cher',
            email: 'teacher@example.com',
            role: User.roleTeacher,
          ),
        );
    final tutorials = TutorialProgressService();
    final joinLinks = JoinLinkService();
    final router = AppRouter.create(auth, tutorials, joinLinks);

    addTearDown(router.dispose);
    addTearDown(auth.dispose);
    addTearDown(tutorials.dispose);
    addTearDown(joinLinks.dispose);

    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(movements.dispose);
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    final submissions = InMemoryAssignmentSubmissionRepository(
      classroom: assignments,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groups),
          Provider<TeacherMovementRepository>.value(value: movements),
          Provider<ClassroomAssignmentRepository>.value(value: assignments),
          Provider<AssignmentSubmissionRepository>.value(value: submissions),
        ],
        child: FluentApp.router(routerConfig: router, theme: FluentThemeData()),
      ),
    );
    router.go(AppRoutePaths.teacherDashboard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('Leaderboard'), findsWidgets);
    expect(find.text('Movements'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Your classroom is ready'), findsOneWidget);
    expect(find.byType(TeacherShell), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);

    router.go(AppRoutePaths.teacherLeaderboard);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Global'), findsWidgets);
    expect(find.text('My Students'), findsOneWidget);
    expect(
      find.text('Available in a later ELIXR Teacher phase.'),
      findsNothing,
    );

    router.go(AppRoutePaths.teacherMovements);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Official ELIXR'), findsWidgets);
    expect(
      find.text('Available in a later ELIXR Teacher phase.'),
      findsNothing,
    );
  });
}
