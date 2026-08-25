import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/profile/profile_menu.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

User _teacher() {
  return const User(
    id: 'teacher-1',
    firstName: 'Tea',
    lastName: 'Cher',
    email: 'teacher@example.com',
    role: User.roleTeacher,
  );
}

User _trainee() {
  return const User(
    id: 'trainee-1',
    firstName: 'Train',
    lastName: 'Ee',
    email: 'trainee@example.com',
    role: User.roleTrainee,
  );
}

class _StubAuthRepository implements AuthRepositoryBase {
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
    required RegistrationLegalConsent legalConsent,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {}

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
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  }) async {}

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();
}

AuthService _authWith(User user) {
  return AuthService(
    repository: _StubAuthRepository(),
    awaitInitialAuthState: () async {},
  )..seedAuthenticatedUser(user);
}

void main() {
  test('Teacher profile menu path stays on the teacher profile host', () {
    final teacher = _teacher();
    expect(
      ProfileMenu.profilePathFor(teacher),
      AppRoutePaths.teacherProfile(teacher.id ?? ''),
    );
  });

  test('Trainee profile menu path stays on the trainee profile route', () {
    final trainee = _trainee();
    expect(ProfileMenu.profilePathFor(trainee), '/profile/${trainee.id}');
  });

  testWidgets('Teacher settings item does not navigate to /teacher/settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = _authWith(_teacher());
    addTearDown(auth.dispose);

    var settingsOpened = false;
    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherDashboard,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherDashboard,
          builder: (context, state) {
            return Button(
              onPressed: () => ProfileMenu.show(
                context,
                onLogout: () {},
                onOpenSettings: () => settingsOpened = true,
              ),
              child: const Text('Open menu'),
            );
          },
        ),
        GoRoute(
          path: AppRoutePaths.teacherSettings,
          builder: (context, state) => const Text('Teacher settings host'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(settingsOpened, isTrue);
    expect(router.state.uri.path, AppRoutePaths.teacherDashboard);
    expect(find.text('Teacher settings host'), findsNothing);
  });
}
