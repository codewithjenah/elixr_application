import 'package:elixr_application/data/repositories/profile_image_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure/static behavior only — no FirebaseStorage instance is touched, so
/// this does not require Firebase initialization or network access.
void main() {
  group('ProfileImageRepository.isAllowedContentType', () {
    test('accepts jpeg, png, and webp', () {
      expect(ProfileImageRepository.isAllowedContentType('image/jpeg'), isTrue);
      expect(ProfileImageRepository.isAllowedContentType('image/png'), isTrue);
      expect(ProfileImageRepository.isAllowedContentType('image/webp'), isTrue);
    });

    test('rejects other content types', () {
      expect(ProfileImageRepository.isAllowedContentType('image/gif'), isFalse);
      expect(
        ProfileImageRepository.isAllowedContentType('application/pdf'),
        isFalse,
      );
      expect(ProfileImageRepository.isAllowedContentType(''), isFalse);
    });

    test('is case-insensitive', () {
      expect(ProfileImageRepository.isAllowedContentType('IMAGE/JPEG'), isTrue);
    });
  });

  group('ProfileImageRepository.belongsToUserProfile', () {
    test('accepts a path scoped to the authenticated user', () {
      expect(
        ProfileImageRepository.belongsToUserProfile(
          storagePath: 'users/u1/profile/avatar_123.jpg',
          userId: 'u1',
        ),
        isTrue,
      );
    });

    test('rejects a path scoped to a different user', () {
      expect(
        ProfileImageRepository.belongsToUserProfile(
          storagePath: 'users/u2/profile/avatar_123.jpg',
          userId: 'u1',
        ),
        isFalse,
      );
    });

    test('rejects a path outside the profile prefix entirely', () {
      expect(
        ProfileImageRepository.belongsToUserProfile(
          storagePath: 'users/u1/other/avatar_123.jpg',
          userId: 'u1',
        ),
        isFalse,
      );
      expect(
        ProfileImageRepository.belongsToUserProfile(
          storagePath: 'some/unrelated/path.jpg',
          userId: 'u1',
        ),
        isFalse,
      );
    });

    test('rejects an empty authenticated uid', () {
      expect(
        ProfileImageRepository.belongsToUserProfile(
          storagePath: 'users/u1/profile/avatar_123.jpg',
          userId: '',
        ),
        isFalse,
      );
    });

    test('rejects a crafted path using another user id as a prefix trick', () {
      // "users/u1-evil/profile/..." must not be treated as belonging to "u1".
      expect(
        ProfileImageRepository.belongsToUserProfile(
          storagePath: 'users/u1-evil/profile/avatar_123.jpg',
          userId: 'u1',
        ),
        isFalse,
      );
    });
  });
}
