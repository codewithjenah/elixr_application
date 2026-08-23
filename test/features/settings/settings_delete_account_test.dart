import 'dart:io';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/achievement_claim.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_application/data/models/user_cosmetics.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/profile_image_repository.dart';
import 'package:elixr_application/features/settings/sections/security_section.dart';
import 'package:elixr_application/features/settings/settings_screen.dart';
import 'package:elixr_application/features/settings/settings_section.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _StubAuthRepository implements AuthRepositoryBase {
  _StubAuthRepository(this._user);

  User? _user;
  Object? deleteError;
  int deleteAccountCallCount = 0;
  String? lastDeletePassword;
  bool verificationRequested = false;

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<void> requestCurrentEmailVerification() async {
    verificationRequested = true;
  }

  @override
  Future<void> requestDeleteAccountEmailVerification({
    String confirmationCode = '',
  }) async {
    verificationRequested = true;
  }

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.verificationSent;

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async => _user!;

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async => _user!;

  @override
  Future<void> clearCurrentUser() async => _user = null;

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<User?> loadPersistedUser() async => _user;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    String defaultRole = User.roleTrainee,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User?> refreshAuthenticatedUser() async => _user;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> deleteAccount({required String password}) async {
    deleteAccountCallCount++;
    lastDeletePassword = password;
    if (deleteError != null) throw deleteError!;
    _user = null;
  }
}

class _NoopImages implements ProfileImageRepositoryBase {
  @override
  Future<void> deleteProfileImage({
    required String authenticatedUid,
    required String storagePath,
  }) async {}

  @override
  Future<ProfileImageUploadResult> uploadProfileImage({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SettingsService settingsService;
  late AuthService authService;
  late _StubAuthRepository repository;
  late CameraDeviceService cameraDeviceService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_settings_delete_');
    settingsService = SettingsService(
      settingsFile: File('${tempDir.path}/settings.json'),
    );
    await settingsService.initialize();
    cameraDeviceService = CameraDeviceService(
      httpGet: (_) async => '{"devices":[]}',
    );
    repository = _StubAuthRepository(
      User(
        id: 'u1',
        firstName: 'Test',
        lastName: 'User',
        email: 'user@example.com',
      ),
    );
    authService = AuthService(
      repository: repository,
      leaderboardRepository: null,
      profileImageRepository: _NoopImages(),
      generateDeleteVerificationCode: () => '123456',
    );
    authService.seedAuthenticatedUser(
      User(
        id: 'u1',
        firstName: 'Test',
        lastName: 'User',
        email: 'user@example.com',
      ),
    );
  });

  tearDown(() async {
    authService.dispose();
    cameraDeviceService.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Widget buildHarness({required Widget child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<CameraDeviceService>.value(
          value: cameraDeviceService,
        ),
      ],
      child: child,
    );
  }

  testWidgets('Security section shows destructive Delete account affordance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildHarness(
        child: FluentApp(
          theme: AppTheme.dark,
          home: ScaffoldPage(
            content: SettingsScreen(
              initialSection: SettingsSection.security,
              watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
              watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
              equipBorder: ({required userId, required borderId}) async =>
                  const EquipBorderResult.alreadyEquipped(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SecuritySection), findsOneWidget);
    expect(find.text('Delete account'), findsWidgets);
    expect(find.text('Change password'), findsOneWidget);
  });

  testWidgets('Delete account dialog requires password and confirm gate', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => buildHarness(
            child: FluentTheme(
              data: AppTheme.dark,
              child: const ScaffoldPage(content: SecuritySection()),
            ),
          ),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const ScaffoldPage(content: Text('Login')),
        ),
      ],
    );

    await tester.pumpWidget(
      FluentApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pump();

    await tester.tap(find.text('Delete account').last);
    await tester.pumpAndSettle();

    expect(repository.verificationRequested, isTrue);
    expect(
      find.textContaining('We sent a verification message to user@example.com'),
      findsOneWidget,
    );
    expect(find.text('Delete account permanently?'), findsOneWidget);
    expect(
      find.textContaining('Practice sessions and feedback'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextBox && widget.placeholder == '6-digit code',
      ),
      '123456',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextBox && widget.placeholder == 'Enter your password',
      ),
      'secret',
    );
    await tester.pump();

    final confirmLabel = find.text(
      'I understand this permanently deletes my account and data',
    );
    await tester.ensureVisible(confirmLabel);
    await tester.tap(confirmLabel);
    await tester.pump();

    final deleteAction = find.widgetWithText(FilledButton, 'Delete account');
    await tester.ensureVisible(deleteAction.last);
    await tester.tap(deleteAction.last);
    await tester.pumpAndSettle();

    expect(repository.deleteAccountCallCount, 1);
    expect(repository.lastDeletePassword, 'secret');
    expect(authService.isAuthenticated, isFalse);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('wrong confirmation code keeps the account', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildHarness(
        child: FluentApp(
          theme: AppTheme.dark,
          home: ScaffoldPage(content: const SecuritySection()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Delete account').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextBox && widget.placeholder == '6-digit code',
      ),
      '000000',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextBox && widget.placeholder == 'Enter your password',
      ),
      'secret',
    );
    await tester.pump();

    final confirmLabel = find.text(
      'I understand this permanently deletes my account and data',
    );
    await tester.ensureVisible(confirmLabel);
    await tester.tap(confirmLabel);
    await tester.pump();

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Delete account').last,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Delete account').last);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('confirmation code is incorrect'),
      findsOneWidget,
    );
    expect(find.text('Delete account permanently?'), findsOneWidget);
    expect(repository.deleteAccountCallCount, 0);
    expect(authService.isAuthenticated, isTrue);
  });
}
