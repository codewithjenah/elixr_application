import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/profile_image_repository.dart';
import 'package:elixr_application/features/profile/profile_settings_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _TrackingAuthRepository implements AuthRepositoryBase {
  _TrackingAuthRepository({User? initialUser}) : _user = initialUser;

  User? _user;
  int updateCallCount = 0;
  int isCurrentEmailVerifiedCallCount = 0;
  int requestCurrentEmailVerificationCallCount = 0;
  int requestEmailChangeCallCount = 0;
  EmailChangeRequestResult requestEmailChangeResult =
      EmailChangeRequestResult.verificationSent;
  String? lastFirstName;
  String? lastMiddleName;
  String? lastLastName;
  Map<String, dynamic>? lastUpdateFields;

  @override
  Future<bool> isCurrentEmailVerified() async {
    isCurrentEmailVerifiedCallCount++;
    return false;
  }

  @override
  Future<void> requestCurrentEmailVerification() async {
    requestCurrentEmailVerificationCallCount++;
  }

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    requestEmailChangeCallCount++;
    return requestEmailChangeResult;
  }

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async {
    updateCallCount++;
    lastFirstName = firstName;
    lastMiddleName = middleName;
    lastLastName = lastName;
    lastUpdateFields = {
      'first_name': firstName,
      'middle_name': middleName ?? FieldValue.delete(),
      'last_name': lastName,
    };
    _user = User(
      id: userId,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: _user?.email ?? 'user@example.com',
      profilePictureUrl: profilePictureUpdate?.url ?? _user?.profilePictureUrl,
      profilePictureStoragePath:
          profilePictureUpdate?.storagePath ?? _user?.profilePictureStoragePath,
    );
    return _user!;
  }

  @override
  Future<void> clearCurrentUser() async {
    _user = null;
  }

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
  Future<User?> loadPersistedUser() async => _user;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
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
}

class _NoopProfileImageRepository implements ProfileImageRepositoryBase {
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

User _testUser() {
  return User(
    id: 'u1',
    firstName: 'Test',
    lastName: 'User',
    email: 'user@example.com',
  );
}

Future<void> _setSurface(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Future<void> _tapSaveChanges(WidgetTester tester) async {
  final saveButton = find.text('Save changes');
  await tester.scrollUntilVisible(
    saveButton,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(saveButton);
  await tester.pumpAndSettle();
}

Finder _profileTextBoxAt(int index) {
  return find
      .descendant(
        of: find.byType(ProfileSettingsScreen),
        matching: find.byType(TextBox),
      )
      .at(index);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File settingsFile;
  late _TrackingAuthRepository authRepository;
  late AuthService authService;
  late SettingsService settingsService;
  late CameraDeviceService cameraDeviceService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_profile_save_');
    settingsFile = File('${tempDir.path}/settings.json');
    authRepository = _TrackingAuthRepository(initialUser: _testUser());
    settingsService = SettingsService(settingsFile: settingsFile);
    await settingsService.initialize();
    cameraDeviceService = CameraDeviceService(
      httpGet: (_) async => '{"devices":[]}',
    );
    authService = AuthService(
      repository: authRepository,
      leaderboardRepository: null,
      profileImageRepository: _NoopProfileImageRepository(),
    );
    authService.seedAuthenticatedUser(_testUser());
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

  group('ProfileSettingsScreen save profile', () {
    testWidgets('name-only save does not trigger current-email verification', (
      tester,
    ) async {
      await _setSurface(tester);
      await tester.pumpWidget(
        wrap(
          ProfileSettingsScreen(
            initialSection: ProfileSettingsSection.profile,
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(_profileTextBoxAt(0), 'Updated');
      await tester.enterText(_profileTextBoxAt(1), 'Name');
      await _tapSaveChanges(tester);

      expect(authRepository.isCurrentEmailVerifiedCallCount, 0);
      expect(authRepository.requestCurrentEmailVerificationCallCount, 0);
      expect(authRepository.requestEmailChangeCallCount, 0);
      expect(authRepository.updateCallCount, 1);
      expect(authRepository.lastFirstName, 'Updated');
      expect(authRepository.lastLastName, 'Name');
      expect(find.text('Profile updated successfully.'), findsOneWidget);
    });

    testWidgets('profile save updates all name components', (tester) async {
      authService.seedAuthenticatedUser(
        User(
          id: 'u1',
          firstName: 'Ada',
          middleName: 'Augusta',
          lastName: 'Lovelace',
          email: 'user@example.com',
        ),
      );

      await _setSurface(tester);
      await tester.pumpWidget(
        wrap(
          ProfileSettingsScreen(
            initialSection: ProfileSettingsSection.profile,
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(_profileTextBoxAt(0), 'Grace');
      await tester.enterText(_profileTextBoxAt(1), 'Hopper');
      await tester.enterText(_profileTextBoxAt(2), 'Marie');
      await _tapSaveChanges(tester);

      expect(authRepository.lastFirstName, 'Grace');
      expect(authRepository.lastMiddleName, 'Marie');
      expect(authRepository.lastLastName, 'Hopper');
      expect(authService.currentUser?.fullName, 'Grace Marie Hopper');
    });

    testWidgets('clearing middle name passes null middle name to repository', (
      tester,
    ) async {
      authService.seedAuthenticatedUser(
        User(
          id: 'u1',
          firstName: 'Ada',
          middleName: 'Augusta',
          lastName: 'Lovelace',
          email: 'user@example.com',
        ),
      );

      await _setSurface(tester);
      await tester.pumpWidget(
        wrap(
          ProfileSettingsScreen(
            initialSection: ProfileSettingsSection.profile,
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(_profileTextBoxAt(2), '');
      await _tapSaveChanges(tester);

      expect(authRepository.lastMiddleName, isNull);
      expect(authService.currentUser?.middleName, isNull);
      expect(authService.currentUser?.fullName, 'Ada Lovelace');
    });

    test('changed email request still invokes email-change flow', () async {
      final sent = await authService.requestEmailChange(
        newEmail: 'new@example.com',
        currentPassword: 'secret-password',
      );

      expect(sent, isTrue);
      expect(authRepository.requestEmailChangeCallCount, 1);
      expect(authRepository.isCurrentEmailVerifiedCallCount, 0);
      expect(authRepository.requestCurrentEmailVerificationCallCount, 0);
      expect(authService.hasPendingEmailChange, isTrue);
    });
  });
}
