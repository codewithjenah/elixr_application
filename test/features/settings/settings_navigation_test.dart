import 'dart:io';

import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/achievement_claim.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_application/data/models/user_cosmetics.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/profile_image_repository.dart';
import 'package:elixr_application/features/settings/settings_screen.dart';
import 'package:elixr_application/features/settings/settings_section.dart';
import 'package:elixr_application/features/settings/widgets/practice_preferences_controller.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubAuthRepository implements AuthRepositoryBase {
  _StubAuthRepository(this._user);

  User? _user;

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<void> requestDeleteAccountEmailVerification({
    String confirmationCode = '',
  }) async {}

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
  Future<void> deleteAccount({required String password}) async {}
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
  late CameraDeviceService cameraDeviceService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_settings_nav_');
    settingsService = SettingsService(
      settingsFile: File('${tempDir.path}/settings.json'),
    );
    await settingsService.initialize();
    cameraDeviceService = CameraDeviceService(
      httpGet: (_) async => '{"devices":[]}',
    );
    authService = AuthService(
      repository: _StubAuthRepository(
        User(
          id: 'u1',
          firstName: 'Test',
          lastName: 'User',
          email: 'user@example.com',
        ),
      ),
      leaderboardRepository: null,
      profileImageRepository: _NoopImages(),
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

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: authService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<CameraDeviceService>.value(
          value: cameraDeviceService,
        ),
      ],
      child: FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(content: child),
      ),
    );
  }

  Future<void> setSurface(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('wide layout shows sidebar and section content', (tester) async {
    await setSurface(tester, const Size(1400, 900));

    await tester.pumpWidget(
      wrap(
        SettingsScreen(
          initialSection: SettingsSection.appearance,
          watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
          equipBorder: ({required userId, required borderId}) async =>
              const EquipBorderResult.alreadyEquipped(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.byType(ComboBox<SettingsSection>), findsNothing);
    expect(find.text('Account & Profile'), findsOneWidget);
    expect(find.text('Security'), findsWidgets);
    expect(find.text('Practice'), findsOneWidget);
    expect(find.text('Teacher Access'), findsOneWidget);
  });

  testWidgets('compact layout uses ComboBox navigation', (tester) async {
    await setSurface(tester, const Size(720, 600));

    await tester.pumpWidget(
      wrap(
        SettingsScreen(
          initialSection: SettingsSection.appearance,
          watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
          equipBorder: ({required userId, required borderId}) async =>
              const EquipBorderResult.alreadyEquipped(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(ComboBox<SettingsSection>), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
  });

  testWidgets('selecting Security shows password form', (tester) async {
    await setSurface(tester, const Size(1400, 900));

    await tester.pumpWidget(
      wrap(
        SettingsScreen(
          initialSection: SettingsSection.appearance,
          watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
          equipBorder: ({required userId, required borderId}) async =>
              const EquipBorderResult.alreadyEquipped(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Security').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Current password'), findsOneWidget);
    expect(find.text('Update password'), findsOneWidget);
  });

  test('practice controller dirty and save round-trip', () async {
    final controller = PracticePreferencesController(settingsService);
    expect(controller.isDirty, isFalse);

    controller.toggleMovement(movementCatalog.first.name, false);
    // May still be dirty depending on starting setlist size.
    final before = List.of(controller.draft.movementNames);
    controller.setInterval(40);
    expect(controller.isDirty, isTrue);
    expect(
      controller.canSave,
      before.isNotEmpty || controller.draft.movementNames.isNotEmpty,
    );

    // Ensure at least one movement remains.
    if (controller.draft.movementNames.isEmpty) {
      controller.toggleMovement(movementCatalog.first.name, true);
    }

    final outcome = await controller.save();
    expect(outcome, SettingsWriteOutcome.saved);
    expect(controller.isDirty, isFalse);
    expect(settingsService.justDanceIntervalSeconds, 40);
    controller.dispose();
  });
}
