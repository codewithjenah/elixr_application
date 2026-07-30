import 'package:elixr_application/data/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

/// Firestore introduced `profile_picture_url` / `profile_picture_storage_path`
/// to replace the Windows-local-path-only `profile_picture_path`. Parsing
/// must prefer the URL while staying backward compatible with documents
/// written before this change.
void main() {
  group('User.fromMap profile picture fields', () {
    test('parses the new Cloud Storage fields when present', () {
      final user = User.fromMap({
        'id': 'u1',
        'full_name': 'Ada Lovelace',
        'email': 'ada@example.com',
        'profile_picture_url': 'https://storage.example/avatar.jpg',
        'profile_picture_storage_path': 'users/u1/profile/avatar_1.jpg',
      });

      expect(user.profilePictureUrl, 'https://storage.example/avatar.jpg');
      expect(user.profilePictureStoragePath, 'users/u1/profile/avatar_1.jpg');
      expect(user.profilePicturePath, isNull);
    });

    test('falls back to legacy profile_picture_path when no URL is stored', () {
      final user = User.fromMap({
        'id': 'u1',
        'full_name': 'Ada Lovelace',
        'email': 'ada@example.com',
        'profile_picture_path': r'C:\Users\ada\Pictures\avatar.png',
      });

      expect(user.profilePictureUrl, isNull);
      expect(user.profilePictureStoragePath, isNull);
      expect(user.profilePicturePath, r'C:\Users\ada\Pictures\avatar.png');
    });

    test('handles a document with no profile picture fields at all', () {
      final user = User.fromMap({
        'id': 'u1',
        'full_name': 'Ada Lovelace',
        'email': 'ada@example.com',
      });

      expect(user.profilePictureUrl, isNull);
      expect(user.profilePictureStoragePath, isNull);
      expect(user.profilePicturePath, isNull);
    });

    test('retains both fields through copyWith', () {
      const user = User(
        fullName: 'Ada',
        email: 'ada@example.com',
        profilePictureUrl: 'https://storage.example/a.jpg',
        profilePictureStoragePath: 'users/u1/profile/a.jpg',
      );

      final renamed = user.copyWith(fullName: 'Ada L.');

      expect(renamed.profilePictureUrl, user.profilePictureUrl);
      expect(renamed.profilePictureStoragePath, user.profilePictureStoragePath);
    });
  });

  group('User.toMap profile picture fields', () {
    test('writes url and storage path, and omits the legacy path', () {
      const user = User(
        id: 'u1',
        fullName: 'Ada',
        email: 'ada@example.com',
        profilePicturePath: r'C:\old\path.png',
        profilePictureUrl: 'https://storage.example/a.jpg',
        profilePictureStoragePath: 'users/u1/profile/a.jpg',
      );

      final map = user.toMap();

      expect(map['profile_picture_url'], 'https://storage.example/a.jpg');
      expect(map['profile_picture_storage_path'], 'users/u1/profile/a.jpg');
      expect(map.containsKey('profile_picture_path'), isFalse);
    });

    test('writes the legacy path only when no URL exists yet', () {
      const user = User(
        id: 'u1',
        fullName: 'Ada',
        email: 'ada@example.com',
        profilePicturePath: r'C:\old\path.png',
      );

      final map = user.toMap();

      expect(map['profile_picture_path'], r'C:\old\path.png');
      expect(map.containsKey('profile_picture_url'), isFalse);
    });
  });
}
