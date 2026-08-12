import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/achievement_claim.dart';
import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/user_cosmetics.dart';
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
  int updatePictureCallCount = 0;
  int isCurrentEmailVerifiedCallCount = 0;
  int requestCurrentEmailVerificationCallCount = 0;
  int requestEmailChangeCallCount = 0;
  EmailChangeRequestResult requestEmailChangeResult =
      EmailChangeRequestResult.verificationSent;
  String? lastFirstName;
  String? lastMiddleName;
  String? lastLastName;
  ProfilePictureUpdate? lastPictureUpdate;
  Map<String, dynamic>? lastUpdateFields;

  void seedUser(User user) => _user = user;

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
    lastPictureUpdate = profilePictureUpdate;
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
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    updatePictureCallCount++;
    lastPictureUpdate = profilePictureUpdate;
    _user = User(
      id: userId,
      firstName: _user?.firstName ?? 'Test',
      middleName: _user?.middleName,
      lastName: _user?.lastName ?? 'User',
      email: _user?.email ?? 'user@example.com',
      profilePictureUrl: profilePictureUpdate.url,
      profilePictureStoragePath: profilePictureUpdate.storagePath,
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

class _TrackingProfileImageRepository implements ProfileImageRepositoryBase {
  int uploadCallCount = 0;
  int deleteCallCount = 0;
  final deletedPaths = <String>[];
  Uint8List? lastBytes;
  String? lastContentType;
  Object? uploadError;
  Completer<void>? uploadGate;

  @override
  Future<void> deleteProfileImage({
    required String authenticatedUid,
    required String storagePath,
  }) async {
    deleteCallCount++;
    deletedPaths.add(storagePath);
  }

  @override
  Future<ProfileImageUploadResult> uploadProfileImage({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploadCallCount++;
    lastBytes = bytes;
    lastContentType = contentType;
    final gate = uploadGate;
    if (gate != null) {
      await gate.future;
    }
    if (uploadError != null) {
      throw uploadError!;
    }
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
            watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
            equipBorder: ({required userId, required borderId}) async =>
                const EquipBorderResult.alreadyEquipped(),
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
            watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
            equipBorder: ({required userId, required borderId}) async =>
                const EquipBorderResult.alreadyEquipped(),
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
            watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
            equipBorder: ({required userId, required borderId}) async =>
                const EquipBorderResult.alreadyEquipped(),
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

  group('AccountProfileSection immediate profile picture upload', () {
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
      ValueChanged<bool>? onDirtyChanged,
    }) async {
      await tester.pumpWidget(
        wrap(
          AccountProfileSection(
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
            watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
            equipBorder: ({required userId, required borderId}) async =>
                const EquipBorderResult.alreadyEquipped(),
            pickProfileImage: pickProfileImage,
            cropProfileImage: cropProfileImage,
            onDirtyChanged: onDirtyChanged,
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

    Finder saveChangesButton() {
      return find.descendant(
        of: find.byType(AccountProfileSection),
        matching: find.widgetWithText(FilledButton, 'Save changes'),
      );
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
      expect(
        tester.widget<FilledButton>(saveChangesButton()).onPressed,
        isNull,
      );
    });

    testWidgets('applying a crop uploads once without requiring Save changes', (
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
      await _pumpFrames(tester);

      expect(imageRepository.uploadCallCount, 1);
      expect(imageRepository.lastContentType, 'image/png');
      expect(imageRepository.lastBytes, croppedBytes);
      expect(authRepository.updatePictureCallCount, 1);
      expect(authRepository.updateCallCount, 0);
      expect(
        find.text('Profile picture updated successfully.'),
        findsOneWidget,
      );

      final state = tester.state<AccountProfileSectionState>(
        find.byType(AccountProfileSection),
      );
      expect(state.isDirty, isFalse);
      expect(
        tester.widget<FilledButton>(saveChangesButton()).onPressed,
        isNull,
      );
      expect(
        authService.currentUser?.profilePictureUrl,
        'https://storage.example/avatar_1.png',
      );

      final avatar = tester.widget<ProfileAvatarWidget>(
        find.byType(ProfileAvatarWidget),
      );
      expect(avatar.memoryPreviewBytes, isNull);
    });

    testWidgets('successful upload leaves existing dirty name edits unsaved', (
      tester,
    ) async {
      await _setSurface(tester);
      final croppedBytes = Uint8List.fromList(<int>[2, 4, 6, 8]);

      await pumpSection(
        tester,
        pickProfileImage: () async => memoryPickFile(),
        cropProfileImage: (context, bytes) async {
          return PendingProfileCrop(bytes: croppedBytes);
        },
      );

      await tester.enterText(_accountField('First Name'), 'Edited');
      await tester.pump();

      final stateBefore = tester.state<AccountProfileSectionState>(
        find.byType(AccountProfileSection),
      );
      expect(stateBefore.isDirty, isTrue);

      await tapAvatar(tester);
      await _pumpFrames(tester);

      expect(imageRepository.uploadCallCount, 1);
      expect(authRepository.updatePictureCallCount, 1);
      expect(authRepository.updateCallCount, 0);
      expect(authRepository.requestEmailChangeCallCount, 0);
      expect(authRepository.lastFirstName, isNull);

      final stateAfter = tester.state<AccountProfileSectionState>(
        find.byType(AccountProfileSection),
      );
      expect(stateAfter.isDirty, isTrue);
      expect(
        tester.widget<FilledButton>(saveChangesButton()).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<TextBox>(_accountField('First Name')).controller?.text,
        'Edited',
      );
    });

    testWidgets(
      'dirty email edits do not trigger email-change during image upload',
      (tester) async {
        await _setSurface(tester);
        final croppedBytes = Uint8List.fromList(<int>[3, 3, 3, 3]);

        await pumpSection(
          tester,
          pickProfileImage: () async => memoryPickFile(),
          cropProfileImage: (context, bytes) async {
            return PendingProfileCrop(bytes: croppedBytes);
          },
        );

        await tester.enterText(_accountField('Email'), 'new@example.com');
        await tester.pump();
        expect(
          tester
              .state<AccountProfileSectionState>(
                find.byType(AccountProfileSection),
              )
              .isDirty,
          isTrue,
        );

        await tapAvatar(tester);
        await _pumpFrames(tester);

        expect(imageRepository.uploadCallCount, 1);
        expect(authRepository.requestEmailChangeCallCount, 0);
        expect(authRepository.updateCallCount, 0);
        expect(
          tester
              .state<AccountProfileSectionState>(
                find.byType(AccountProfileSection),
              )
              .isDirty,
          isTrue,
        );
      },
    );

    testWidgets(
      'upload failure restores old avatar and preserves dirty form state',
      (tester) async {
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
        imageRepository.uploadError = Exception('Upload failed');

        await pumpSection(
          tester,
          pickProfileImage: () async => memoryPickFile(),
          cropProfileImage: (context, bytes) async {
            return PendingProfileCrop(bytes: Uint8List.fromList(<int>[9, 9]));
          },
        );

        await tester.enterText(_accountField('Last Name'), 'Dirty');
        await tester.pump();

        await tapAvatar(tester);
        await _pumpFrames(tester);

        expect(find.textContaining('Upload failed'), findsOneWidget);
        expect(
          authService.currentUser?.profilePictureUrl,
          'https://storage.example/saved.jpg',
        );

        final avatar = tester.widget<ProfileAvatarWidget>(
          find.byType(ProfileAvatarWidget),
        );
        expect(avatar.memoryPreviewBytes, isNull);
        expect(avatar.networkImageUrl, 'https://storage.example/saved.jpg');

        final state = tester.state<AccountProfileSectionState>(
          find.byType(AccountProfileSection),
        );
        expect(state.isDirty, isTrue);
        expect(authRepository.updateCallCount, 0);
      },
    );

    testWidgets(
      'remove photo requires confirmation and preserves dirty edits',
      (tester) async {
        await _setSurface(tester);
        final user = User(
          id: 'u1',
          firstName: 'Test',
          lastName: 'User',
          email: 'user@example.com',
          profilePictureUrl: 'https://storage.example/saved.jpg',
          profilePictureStoragePath: 'users/u1/profile/avatar_1.jpg',
        );
        authRepository.seedUser(user);
        authService.seedAuthenticatedUser(user);

        await pumpSection(tester);
        await tester.enterText(_accountField('Last Name'), 'Dirty');
        await tester.pump();
        expect(
          find.byKey(const Key('account_profile_remove_photo')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('account_profile_remove_photo')));
        await tester.pump();
        expect(find.text('Remove profile photo?'), findsOneWidget);
        expect(
          find.textContaining('your initials will be shown instead'),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancel').last);
        await tester.pump();
        expect(authRepository.updatePictureCallCount, 0);
        expect(
          find.byKey(const Key('account_profile_remove_photo')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('account_profile_remove_photo')));
        await tester.pump();
        await tester.tap(find.text('Remove photo').last);
        await _pumpFrames(tester, count: 20);

        expect(authRepository.updatePictureCallCount, 1);
        expect(authRepository.lastPictureUpdate?.isRemoval, isTrue);
        expect(authService.currentUser?.profilePictureUrl, isNull);
        expect(imageRepository.deletedPaths, ['users/u1/profile/avatar_1.jpg']);
        expect(
          tester
              .state<AccountProfileSectionState>(
                find.byType(AccountProfileSection),
              )
              .isDirty,
          isTrue,
        );
        expect(find.text('Profile photo removed.'), findsOneWidget);
      },
    );

    testWidgets('no saved photo shows Add photo without Remove photo', (
      tester,
    ) async {
      await _setSurface(tester);
      await pumpSection(tester);

      expect(
        find.byKey(const Key('account_profile_change_photo')),
        findsOneWidget,
      );
      expect(find.text('Add photo'), findsOneWidget);
      expect(
        find.byKey(const Key('account_profile_remove_photo')),
        findsNothing,
      );
    });

    testWidgets(
      'avatar tap while upload is active cannot produce duplicate uploads',
      (tester) async {
        await _setSurface(tester);
        imageRepository.uploadGate = Completer<void>();
        var pickCount = 0;

        await pumpSection(
          tester,
          pickProfileImage: () async {
            pickCount++;
            return memoryPickFile();
          },
          cropProfileImage: (context, bytes) async {
            return PendingProfileCrop(
              bytes: Uint8List.fromList(<int>[1, 2, 3]),
            );
          },
        );

        await tester.tap(find.byKey(const Key('account_profile_avatar_tap')));
        await tester.pump();
        await _pumpFrames(tester, count: 10);

        expect(imageRepository.uploadCallCount, 1);

        await tester.tap(find.byKey(const Key('account_profile_avatar_tap')));
        await tester.pump();
        await _pumpFrames(tester, count: 5);

        expect(pickCount, 1);
        expect(imageRepository.uploadCallCount, 1);

        imageRepository.uploadGate!.complete();
        await _pumpFrames(tester, count: 30);
        expect(imageRepository.uploadCallCount, 1);
      },
    );

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

    testWidgets('memory crop preview is shown while upload is in flight', (
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
      imageRepository.uploadGate = Completer<void>();
      final croppedBytes = _testPngBytes();

      await pumpSection(
        tester,
        pickProfileImage: () async => memoryPickFile(),
        cropProfileImage: (context, bytes) async {
          return PendingProfileCrop(bytes: croppedBytes);
        },
      );

      await tester.tap(find.byKey(const Key('account_profile_avatar_tap')));
      await tester.pump();
      await _pumpFrames(tester, count: 10);

      final avatar = tester.widget<ProfileAvatarWidget>(
        find.byType(ProfileAvatarWidget),
      );
      expect(avatar.memoryPreviewBytes, croppedBytes);
      expect(avatar.networkImageUrl, 'https://storage.example/saved.jpg');
      expect(find.byType(ProgressRing), findsWidgets);

      imageRepository.uploadGate!.complete();
      await _pumpFrames(tester, count: 30);

      final after = tester.widget<ProfileAvatarWidget>(
        find.byType(ProfileAvatarWidget),
      );
      expect(after.memoryPreviewBytes, isNull);
    });

    testWidgets(
      'closing Settings after only a successful image update skips discard',
      (tester) async {
        await _setSurface(tester);
        final croppedBytes = Uint8List.fromList(<int>[5, 5, 5, 5]);

        await tester.pumpWidget(
          wrap(
            SettingsScreen(
              initialSection: SettingsSection.accountProfile,
              watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
              watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
              equipBorder: ({required userId, required borderId}) async =>
                  const EquipBorderResult.alreadyEquipped(),
              pickProfileImage: () async => memoryPickFile(),
              cropProfileImage: (context, bytes) async {
                return PendingProfileCrop(bytes: croppedBytes);
              },
            ),
          ),
        );
        await _pumpFrames(tester);

        await tester.tap(find.byKey(const Key('account_profile_avatar_tap')));
        await _pumpFrames(tester, count: 40);

        expect(imageRepository.uploadCallCount, 1);
        expect(
          find.text('Profile picture updated successfully.'),
          findsOneWidget,
        );

        // Dismiss success dialog if still open.
        final okButton = find.text('OK');
        if (okButton.evaluate().isNotEmpty) {
          await tester.tap(okButton.last);
          await tester.pump();
          await _pumpFrames(tester);
        }

        await tester.tap(
          find
              .descendant(
                of: find.byType(SettingsScreen),
                matching: find.byIcon(FluentIcons.cancel),
              )
              .first,
        );
        await _pumpFrames(tester);

        expect(find.text('Discard unsaved changes?'), findsNothing);
      },
    );

    testWidgets('name-only Save changes performs no profile-image upload', (
      tester,
    ) async {
      await _setSurface(tester);
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            initialSection: SettingsSection.accountProfile,
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
            watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
            equipBorder: ({required userId, required borderId}) async =>
                const EquipBorderResult.alreadyEquipped(),
          ),
        ),
      );
      await _pumpFrames(tester);

      await tester.enterText(_accountField('First Name'), 'Updated');
      await tester.enterText(_accountField('Last Name'), 'Name');
      await _tapSaveChanges(tester);

      expect(imageRepository.uploadCallCount, 0);
      expect(authRepository.updatePictureCallCount, 0);
      expect(authRepository.updateCallCount, 1);
      expect(authRepository.lastPictureUpdate, isNull);
    });

    testWidgets('email-change Save changes performs no profile-image upload', (
      tester,
    ) async {
      await _setSurface(tester);
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            initialSection: SettingsSection.accountProfile,
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
            watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
            equipBorder: ({required userId, required borderId}) async =>
                const EquipBorderResult.alreadyEquipped(),
          ),
        ),
      );
      await _pumpFrames(tester);

      await tester.enterText(_accountField('Email'), 'changed@example.com');
      await _tapSaveChanges(tester);
      await _pumpFrames(tester);

      // Password prompt appears for email change; cancel it.
      final cancel = find.text('Cancel');
      if (cancel.evaluate().isNotEmpty) {
        await tester.tap(cancel.last);
        await _pumpFrames(tester);
      }

      expect(imageRepository.uploadCallCount, 0);
      expect(authRepository.updatePictureCallCount, 0);
    });

    testWidgets('Practice Save practice preferences button remains available', (
      tester,
    ) async {
      await _setSurface(tester);

      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            initialSection: SettingsSection.practice,
            watchPlayer: (_) => Stream<LeaderboardEntry?>.value(null),
            watchUserCosmetics: (_) => Stream<UserCosmetics?>.value(null),
            equipBorder: ({required userId, required borderId}) async =>
                const EquipBorderResult.alreadyEquipped(),
          ),
        ),
      );
      await _pumpFrames(tester);

      expect(find.text('Save practice preferences'), findsOneWidget);
    });
  });
}
