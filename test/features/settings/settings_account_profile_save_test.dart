import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/profile_image_repository.dart';
import 'package:elixr_application/features/settings/models/pending_profile_crop.dart';
import 'package:elixr_application/features/settings/sections/account_profile_section.dart';
import 'package:elixr_application/features/settings/settings_screen.dart';
import 'package:elixr_application/features/settings/settings_section.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
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

class _TrackingProfileImageRepository implements ProfileImageRepositoryBase {
  int uploadCallCount = 0;
  Uint8List? lastBytes;
  String? lastContentType;

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
    uploadCallCount++;
    lastBytes = bytes;
    lastContentType = contentType;
    return ProfileImageUploadResult(
      downloadUrl: 'https://storage.example/avatar_$uploadCallCount.png',
      storagePath: 'users/$userId/profile/avatar_$uploadCallCount.png',
    );
  }
}

/// Minimal valid 1×1 PNG.
Uint8List _testPngBytes() {
  return Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x02,
    0x00,
    0x00,
    0x00,
    0x90,
    0x77,
    0x53,
    0xDE,
    0x00,
    0x00,
    0x00,
    0x0C,
    0x49,
    0x44,
    0x41,
    0x54,
    0x08,
    0xD7,
    0x63,
    0xF8,
    0xCF,
    0xC0,
    0x00,
    0x00,
    0x00,
    0x03,
    0x00,
    0x01,
    0x00,
    0x05,
    0xFE,
    0xD4,
    0xEF,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
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
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapSaveChanges(WidgetTester tester) async {
  final saveButton = find.descendant(
    of: find.byType(AccountProfileSection),
    matching: find.text('Save changes'),
  );
  await tester.ensureVisible(saveButton);
  await tester.tap(saveButton);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 20}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Finds the TextBox under a SettingsFormField label within Account & Profile.
Finder _accountField(String label) {
  final labelFinder = find.descendant(
    of: find.byType(AccountProfileSection),
    matching: find.text(label),
  );
  // Nearest Column ancestor is the SettingsFormField root (one TextBox).
  final fieldColumn = find
      .ancestor(of: labelFinder, matching: find.byType(Column))
      .first;
  return find.descendant(of: fieldColumn, matching: find.byType(TextBox));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File settingsFile;
  late _TrackingAuthRepository authRepository;
  late _TrackingProfileImageRepository imageRepository;
  late AuthService authService;
  late SettingsService settingsService;
  late CameraDeviceService cameraDeviceService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('elixr_profile_save_');
    settingsFile = File('${tempDir.path}/settings.json');
    authRepository = _TrackingAuthRepository(initialUser: _testUser());
    imageRepository = _TrackingProfileImageRepository();
    settingsService = SettingsService(settingsFile: settingsFile);
    await settingsService.initialize();
    cameraDeviceService = CameraDeviceService(
      httpGet: (_) async => '{"devices":[]}',
    );
    authService = AuthService(
      repository: authRepository,
      leaderboardRepository: null,
      profileImageRepository: imageRepository,
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

  group('SettingsScreen account profile save', () {
    testWidgets('name-only save does not trigger current-email verification', (
      tester,
    ) async {
      await _setSurface(tester);
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            initialSection: SettingsSection.accountProfile,
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          ),
        ),
      );
      await _pumpFrames(tester);

      await tester.enterText(_accountField('First Name'), 'Updated');
      await tester.enterText(_accountField('Last Name'), 'Name');
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
          SettingsScreen(
            initialSection: SettingsSection.accountProfile,
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          ),
        ),
      );
      await _pumpFrames(tester);

      await tester.enterText(_accountField('First Name'), 'Grace');
      await tester.enterText(_accountField('Last Name'), 'Hopper');
      await tester.enterText(_accountField('Middle Name (Optional)'), 'Marie');
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
          SettingsScreen(
            initialSection: SettingsSection.accountProfile,
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final middleField = _accountField('Middle Name (Optional)');
      await tester.tap(middleField);
      await tester.pump();
      // Fluent TextBox: replace then clear so the controller notifies listeners.
      await tester.enterText(middleField, 'temp');
      await tester.pump();
      await tester.enterText(middleField, '');
      await tester.pump();
      expect(tester.widget<TextBox>(middleField).controller?.text ?? '', '');

      await _tapSaveChanges(tester);

      expect(authRepository.updateCallCount, 1);
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

  group('AccountProfileSection crop staging', () {
    XFile memoryPickFile() {
      return XFile.fromData(
        _testPngBytes(),
        name: 'picked.png',
        mimeType: 'image/png',
      );
    }

    Future<void> pumpSection(
      WidgetTester tester, {
      AccountProfileImagePicker? pickProfileImage,
      AccountProfileImageCropper? cropProfileImage,
    }) async {
      await tester.pumpWidget(
        wrap(
          AccountProfileSection(
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
            pickProfileImage: pickProfileImage,
            cropProfileImage: cropProfileImage,
          ),
        ),
      );
      await _pumpFrames(tester);
    }

    Future<void> tapAvatar(WidgetTester tester) async {
      final target = find.byKey(const Key('account_profile_avatar_tap'));
      expect(target, findsOneWidget);
      await tester.tap(target);
      await tester.pump();
      await _pumpFrames(tester, count: 30);
    }

    testWidgets('selecting an image and cancelling crop keeps section clean', (
      tester,
    ) async {
      await _setSurface(tester);

      await pumpSection(
        tester,
        pickProfileImage: () async => memoryPickFile(),
        cropProfileImage: (context, bytes) async => null,
      );

      await tapAvatar(tester);

      final state = tester.state<AccountProfileSectionState>(
        find.byType(AccountProfileSection),
      );
      expect(state.isDirty, isFalse);
      expect(imageRepository.uploadCallCount, 0);
    });

    testWidgets('applying a crop marks the section dirty', (tester) async {
      await _setSurface(tester);
      final croppedBytes = Uint8List.fromList(<int>[9, 8, 7, 6]);

      await pumpSection(
        tester,
        pickProfileImage: () async => memoryPickFile(),
        cropProfileImage: (context, bytes) async {
          return PendingProfileCrop(bytes: croppedBytes);
        },
      );

      await tapAvatar(tester);

      final state = tester.state<AccountProfileSectionState>(
        find.byType(AccountProfileSection),
      );
      expect(state.isDirty, isTrue);

      final avatar = tester.widget<ProfileAvatarWidget>(
        find.byType(ProfileAvatarWidget),
      );
      expect(avatar.memoryPreviewBytes, croppedBytes);
    });

    testWidgets('discard changes removes the crop preview', (tester) async {
      await _setSurface(tester);
      authService.seedAuthenticatedUser(
        User(
          id: 'u1',
          firstName: 'Test',
          lastName: 'User',
          email: 'user@example.com',
          profilePictureUrl: 'https://storage.example/saved.jpg',
        ),
      );
      final croppedBytes = Uint8List.fromList(<int>[1, 1, 1, 1]);

      await pumpSection(
        tester,
        pickProfileImage: () async => memoryPickFile(),
        cropProfileImage: (context, bytes) async {
          return PendingProfileCrop(bytes: croppedBytes);
        },
      );

      await tapAvatar(tester);

      final state = tester.state<AccountProfileSectionState>(
        find.byType(AccountProfileSection),
      );
      expect(state.isDirty, isTrue);
      state.discardChanges();
      await tester.pump();

      expect(state.isDirty, isFalse);
      final avatar = tester.widget<ProfileAvatarWidget>(
        find.byType(ProfileAvatarWidget),
      );
      expect(avatar.memoryPreviewBytes, isNull);
      expect(avatar.networkImageUrl, 'https://storage.example/saved.jpg');
    });

    testWidgets('save uploads exactly the cropped PNG bytes once', (
      tester,
    ) async {
      await _setSurface(tester);
      final croppedBytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

      await pumpSection(
        tester,
        pickProfileImage: () async => memoryPickFile(),
        cropProfileImage: (context, bytes) async {
          return PendingProfileCrop(bytes: croppedBytes);
        },
      );

      await tapAvatar(tester);
      await _tapSaveChanges(tester);
      await _pumpFrames(tester);

      expect(imageRepository.uploadCallCount, 1);
      expect(imageRepository.lastContentType, 'image/png');
      expect(imageRepository.lastBytes, croppedBytes);
      expect(authRepository.updateCallCount, 1);
      expect(find.text('Profile updated successfully.'), findsOneWidget);

      final state = tester.state<AccountProfileSectionState>(
        find.byType(AccountProfileSection),
      );
      expect(state.isDirty, isFalse);
    });

    testWidgets('crop failure shows error and does not mark dirty', (
      tester,
    ) async {
      await _setSurface(tester);

      await pumpSection(
        tester,
        pickProfileImage: () async => memoryPickFile(),
        cropProfileImage: (context, bytes) async {
          throw Exception('Crop pipeline failed');
        },
      );

      await tapAvatar(tester);
      await _pumpFrames(tester);

      expect(find.text('Error'), findsOneWidget);
      expect(find.textContaining('Crop pipeline failed'), findsOneWidget);

      final state = tester.state<AccountProfileSectionState>(
        find.byType(AccountProfileSection),
      );
      expect(state.isDirty, isFalse);
      expect(imageRepository.uploadCallCount, 0);
    });

    testWidgets('memory crop preview is preferred over saved network avatar', (
      tester,
    ) async {
      await _setSurface(tester);
      authService.seedAuthenticatedUser(
        User(
          id: 'u1',
          firstName: 'Test',
          lastName: 'User',
          email: 'user@example.com',
          profilePictureUrl: 'https://storage.example/saved.jpg',
        ),
      );
      final croppedBytes = _testPngBytes();

      await pumpSection(
        tester,
        pickProfileImage: () async => memoryPickFile(),
        cropProfileImage: (context, bytes) async {
          return PendingProfileCrop(bytes: croppedBytes);
        },
      );

      await tapAvatar(tester);

      final avatar = tester.widget<ProfileAvatarWidget>(
        find.byType(ProfileAvatarWidget),
      );
      expect(avatar.memoryPreviewBytes, croppedBytes);
      expect(avatar.networkImageUrl, 'https://storage.example/saved.jpg');

      final memoryImages = tester
          .widgetList<Image>(find.byType(Image))
          .where((image) => image.image is MemoryImage);
      expect(memoryImages, isNotEmpty);
    });
  });
}
