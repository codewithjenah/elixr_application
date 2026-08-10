import 'dart:typed_data';

import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/profile_image_repository.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepositoryBase {
  User? user;
  int updateCallCount = 0;
  int updatePictureCallCount = 0;
  ProfilePictureUpdate? lastPictureUpdate;
  Object? updateProfileError;
  Object? updatePictureError;
  String? lastFirstName;
  String? lastMiddleName;
  String? lastLastName;

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
    if (updateProfileError != null) {
      throw updateProfileError!;
    }
    user = User(
      id: userId,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: user?.email ?? 'user@example.com',
      profilePicturePath: profilePictureUpdate == null
          ? user?.profilePicturePath
          : null,
      profilePictureUrl: profilePictureUpdate?.url ?? user?.profilePictureUrl,
      profilePictureStoragePath:
          profilePictureUpdate?.storagePath ?? user?.profilePictureStoragePath,
    );
    return user!;
  }

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    updatePictureCallCount++;
    lastPictureUpdate = profilePictureUpdate;
    if (updatePictureError != null) {
      throw updatePictureError!;
    }
    user = User(
      id: userId,
      firstName: user?.firstName ?? 'Test',
      middleName: user?.middleName,
      lastName: user?.lastName ?? 'User',
      email: user?.email ?? 'user@example.com',
      profilePicturePath: null,
      profilePictureUrl: profilePictureUpdate.url,
      profilePictureStoragePath: profilePictureUpdate.storagePath,
    );
    return user!;
  }

  @override
  Future<void> clearCurrentUser() async {}

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<User?> loadPersistedUser() async => user;

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
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<User?> refreshAuthenticatedUser() async => user;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
  @override
  Future<void> deleteAccount({required String password}) async {}
}

class _FakeProfileImageRepository implements ProfileImageRepositoryBase {
  int uploadCallCount = 0;
  int deleteCallCount = 0;
  final List<String> deletedPaths = [];
  Object? uploadError;
  Object? deleteError;
  ProfileImageUploadResult uploadResult = const ProfileImageUploadResult(
    downloadUrl: 'https://storage.example/new.jpg',
    storagePath: 'users/u1/profile/avatar_2.jpg',
  );

  @override
  Future<ProfileImageUploadResult> uploadProfileImage({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploadCallCount++;
    if (uploadError != null) throw uploadError!;
    return uploadResult;
  }

  @override
  Future<void> deleteProfileImage({
    required String authenticatedUid,
    required String storagePath,
  }) async {
    deleteCallCount++;
    deletedPaths.add(storagePath);
    if (deleteError != null) throw deleteError!;
  }
}

User _testUser({
  String id = 'u1',
  String? profilePictureUrl,
  String? profilePictureStoragePath,
}) {
  return User(
    id: id,
    firstName: 'Test',
    lastName: 'User',
    email: 'user@example.com',
    profilePictureUrl: profilePictureUrl,
    profilePictureStoragePath: profilePictureStoragePath,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAuthRepository authRepository;
  late _FakeProfileImageRepository imageRepository;
  late AuthService authService;

  setUp(() {
    authRepository = _FakeAuthRepository();
    imageRepository = _FakeProfileImageRepository();
    authService = AuthService(
      repository: authRepository,
      leaderboardRepository: null,
      profileImageRepository: imageRepository,
    );
  });

  tearDown(() {
    authService.dispose();
  });

  group('AuthService.updateProfileDetails', () {
    test('name-only update never calls image upload or delete', () async {
      authService.seedAuthenticatedUser(_testUser());

      await authService.updateProfileDetails(
        firstName: 'New',
        lastName: 'Name',
      );

      expect(imageRepository.uploadCallCount, 0);
      expect(imageRepository.deleteCallCount, 0);
      expect(authRepository.lastPictureUpdate, isNull);
      expect(authService.currentUser?.fullName, 'New Name');
    });

    test(
      'successful image update sets url/storage path and notifies listeners',
      () async {
        authService.seedAuthenticatedUser(_testUser());
        var notified = false;
        authService.addListener(() => notified = true);

        await authService.updateProfileDetails(
          firstName: 'Test',
          lastName: 'User',
          newProfileImageBytes: Uint8List.fromList([1, 2, 3]),
          newProfileImageContentType: 'image/jpeg',
        );

        expect(imageRepository.uploadCallCount, 1);
        expect(notified, isTrue);
        expect(
          authService.currentUser?.profilePictureUrl,
          'https://storage.example/new.jpg',
        );
        expect(
          authService.currentUser?.profilePictureStoragePath,
          'users/u1/profile/avatar_2.jpg',
        );
      },
    );

    test(
      'deletes the previous image as best-effort cleanup on success',
      () async {
        authService.seedAuthenticatedUser(
          _testUser(
            profilePictureUrl: 'https://storage.example/old.jpg',
            profilePictureStoragePath: 'users/u1/profile/avatar_1.jpg',
          ),
        );

        await authService.updateProfileDetails(
          firstName: 'Test',
          lastName: 'User',
          newProfileImageBytes: Uint8List.fromList([1, 2, 3]),
          newProfileImageContentType: 'image/jpeg',
        );

        expect(imageRepository.deleteCallCount, 1);
        expect(imageRepository.deletedPaths, ['users/u1/profile/avatar_1.jpg']);
        expect(
          imageRepository.deletedPaths,
          isNot(contains('users/u1/profile/avatar_2.jpg')),
        );
      },
    );

    test('rolls back the newly uploaded image and preserves the previous '
        'profile when Firestore fails', () async {
      final previousUser = _testUser(
        profilePictureUrl: 'https://storage.example/old.jpg',
        profilePictureStoragePath: 'users/u1/profile/avatar_1.jpg',
      );
      authService.seedAuthenticatedUser(previousUser);
      authRepository.user = previousUser;
      authRepository.updateProfileError = Exception('Firestore unavailable');

      await expectLater(
        authService.updateProfileDetails(
          firstName: 'Test',
          lastName: 'User',
          newProfileImageBytes: Uint8List.fromList([1, 2, 3]),
          newProfileImageContentType: 'image/jpeg',
        ),
        throwsA(isA<Exception>()),
      );

      expect(imageRepository.deleteCallCount, 1);
      expect(imageRepository.deletedPaths, ['users/u1/profile/avatar_2.jpg']);
      expect(
        authService.currentUser?.profilePictureUrl,
        'https://storage.example/old.jpg',
      );
    });

    test('upload failure prevents any Firestore write', () async {
      authService.seedAuthenticatedUser(_testUser());
      imageRepository.uploadError = Exception('network error');

      await expectLater(
        authService.updateProfileDetails(
          firstName: 'Test',
          lastName: 'User',
          newProfileImageBytes: Uint8List.fromList([1, 2, 3]),
          newProfileImageContentType: 'image/jpeg',
        ),
        throwsA(isA<Exception>()),
      );

      expect(authRepository.updateCallCount, 0);
      expect(imageRepository.deleteCallCount, 0);
    });
  });

  group('AuthService.updateProfilePicture', () {
    test('uploads image without writing name fields', () async {
      final seeded = _testUser().copyWith(
        firstName: 'Ada',
        lastName: 'Lovelace',
      );
      authRepository.user = seeded;
      authService.seedAuthenticatedUser(seeded);
      var notified = false;
      authService.addListener(() => notified = true);

      await authService.updateProfilePicture(
        bytes: Uint8List.fromList([1, 2, 3]),
        contentType: 'image/png',
      );

      expect(imageRepository.uploadCallCount, 1);
      expect(authRepository.updatePictureCallCount, 1);
      expect(authRepository.updateCallCount, 0);
      expect(authRepository.lastFirstName, isNull);
      expect(notified, isTrue);
      expect(
        authService.currentUser?.profilePictureUrl,
        'https://storage.example/new.jpg',
      );
      expect(authService.currentUser?.firstName, 'Ada');
      expect(authService.currentUser?.lastName, 'Lovelace');
    });

    test(
      'deletes the previous image after a successful picture-only update',
      () async {
        authService.seedAuthenticatedUser(
          _testUser(
            profilePictureUrl: 'https://storage.example/old.jpg',
            profilePictureStoragePath: 'users/u1/profile/avatar_1.jpg',
          ),
        );

        await authService.updateProfilePicture(
          bytes: Uint8List.fromList([1, 2, 3]),
          contentType: 'image/jpeg',
        );

        expect(imageRepository.deleteCallCount, 1);
        expect(imageRepository.deletedPaths, ['users/u1/profile/avatar_1.jpg']);
      },
    );

    test(
      'rolls back the uploaded image when Firestore picture write fails',
      () async {
        final previousUser = _testUser(
          profilePictureUrl: 'https://storage.example/old.jpg',
          profilePictureStoragePath: 'users/u1/profile/avatar_1.jpg',
        );
        authService.seedAuthenticatedUser(previousUser);
        authRepository.user = previousUser;
        authRepository.updatePictureError = Exception('Firestore unavailable');

        await expectLater(
          authService.updateProfilePicture(
            bytes: Uint8List.fromList([1, 2, 3]),
            contentType: 'image/jpeg',
          ),
          throwsA(isA<Exception>()),
        );

        expect(imageRepository.deletedPaths, ['users/u1/profile/avatar_2.jpg']);
        expect(
          authService.currentUser?.profilePictureUrl,
          'https://storage.example/old.jpg',
        );
      },
    );
  });

  group('AuthService.removeProfilePicture', () {
    test('clears the profile and deletes the recorded cloud object', () async {
      final user = _testUser(
        profilePictureUrl: 'https://storage.example/old.jpg',
        profilePictureStoragePath: 'users/u1/profile/avatar_1.jpg',
      );
      authRepository.user = user;
      authService.seedAuthenticatedUser(user);
      var notified = false;
      authService.addListener(() => notified = true);

      await authService.removeProfilePicture();

      expect(notified, isTrue);
      expect(authRepository.lastPictureUpdate?.isRemoval, isTrue);
      expect(authService.currentUser?.profilePictureUrl, isNull);
      expect(authService.currentUser?.profilePictureStoragePath, isNull);
      expect(imageRepository.deletedPaths, ['users/u1/profile/avatar_1.jpg']);
    });

    test('clears a legacy-only profile without deleting a local file', () async {
      final user = User(
        id: 'u1',
        firstName: 'Test',
        lastName: 'User',
        email: 'user@example.com',
        profilePicturePath: r'C:\Users\ada\Pictures\avatar.png',
      );
      authRepository.user = user;
      authService.seedAuthenticatedUser(user);

      await authService.removeProfilePicture();

      expect(authService.currentUser?.profilePicturePath, isNull);
      expect(imageRepository.deleteCallCount, 0);
    });

    test('keeps the profile when there is nothing to remove', () async {
      final user = _testUser();
      authRepository.user = user;
      authService.seedAuthenticatedUser(user);

      await authService.removeProfilePicture();

      expect(authRepository.lastPictureUpdate, isNull);
      expect(authService.currentUser, same(user));
    });
  });

  group('LeaderboardRepository.buildPublicProfileFields', () {
    test('includes display_name and non-empty profile URL', () {
      expect(
        LeaderboardRepository.buildPublicProfileFields(
          displayName: ' Ada ',
          profilePictureUrl: ' https://storage.example/avatar.jpg ',
        ),
        {
          'display_name': 'Ada',
          'profile_picture_url': 'https://storage.example/avatar.jpg',
        },
      );
    });

    test('omits empty or whitespace-only profile URL', () {
      expect(
        LeaderboardRepository.buildPublicProfileFields(
          displayName: 'Ada',
          profilePictureUrl: '   ',
        ),
        {'display_name': 'Ada'},
      );
    });
  });
}
