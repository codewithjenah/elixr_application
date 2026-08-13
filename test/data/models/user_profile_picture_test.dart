import 'package:elixr_application/core/utils/user_name.dart';
import 'package:elixr_core/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

/// Firestore introduced `profile_picture_url` / `profile_picture_storage_path`
/// to replace the Windows-local-path-only `profile_picture_path`. Parsing
/// must prefer the URL while staying backward compatible with documents
/// written before this change.
void main() {
  group('UserName composition and parsing', () {
    test('fullName composes "First Last" when middle name is blank', () {
      const user = User(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
      );

      expect(user.fullName, 'Ada Lovelace');
    });

    test(
      'fullName composes "First Middle Last" when middle name is present',
      () {
        const user = User(
          firstName: 'Mary',
          middleName: 'Ann',
          lastName: 'Evans',
          email: 'mary@example.com',
        );

        expect(user.fullName, 'Mary Ann Evans');
      },
    );

    test('User.fromMap prefers structured fields', () {
      final user = User.fromMap({
        'id': 'u1',
        'first_name': 'Ada',
        'middle_name': 'Augusta',
        'last_name': 'Lovelace',
        'full_name': 'Legacy Name',
        'email': 'ada@example.com',
      });

      expect(user.firstName, 'Ada');
      expect(user.middleName, 'Augusta');
      expect(user.lastName, 'Lovelace');
      expect(user.fullName, 'Ada Augusta Lovelace');
    });

    test(
      'User.fromMap still loads a legacy document containing only full_name',
      () {
        final user = User.fromMap({
          'id': 'u1',
          'full_name': 'Ada Augusta Lovelace',
          'email': 'ada@example.com',
        });

        expect(user.firstName, 'Ada');
        expect(user.middleName, 'Augusta');
        expect(user.lastName, 'Lovelace');
        expect(user.fullName, 'Ada Augusta Lovelace');
      },
    );

    test('legacy one-token full_name keeps last name empty', () {
      final user = User.fromMap({
        'id': 'u1',
        'full_name': 'Trainee',
        'email': 'ada@example.com',
      });

      expect(user.firstName, 'Trainee');
      expect(user.middleName, isNull);
      expect(user.lastName, '');
      expect(user.fullName, 'Trainee');
    });

    test('User.toMap writes structured fields and matching full_name', () {
      const user = User(
        id: 'u1',
        firstName: 'Ada',
        middleName: 'Augusta',
        lastName: 'Lovelace',
        email: 'ada@example.com',
      );

      final map = user.toMap();

      expect(map['first_name'], 'Ada');
      expect(map['middle_name'], 'Augusta');
      expect(map['last_name'], 'Lovelace');
      expect(map['full_name'], 'Ada Augusta Lovelace');
    });

    test('normalizeUserNameParts collapses repeated whitespace', () {
      final normalized = normalizeUserNameParts(
        firstName: '  Ada   Marie  ',
        middleName: '  ',
        lastName: '  Lovelace  ',
      );

      expect(normalized.firstName, 'Ada Marie');
      expect(normalized.middleName, isNull);
      expect(normalized.lastName, 'Lovelace');
      expect(normalized.fullName, 'Ada Marie Lovelace');
    });

    test('validateUserNameParts enforces required names and length', () {
      expect(
        validateUserNameParts(firstName: '', lastName: 'Lovelace'),
        'First name is required.',
      );
      expect(
        validateUserNameParts(firstName: 'Ada', lastName: ''),
        'Last name is required.',
      );
      expect(
        validateUserNameParts(firstName: 'A' * 40, lastName: 'B' * 41),
        'The complete name must be 80 characters or fewer.',
      );
    });
  });

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
        firstName: 'Ada',
        lastName: '',
        email: 'ada@example.com',
        profilePictureUrl: 'https://storage.example/a.jpg',
        profilePictureStoragePath: 'users/u1/profile/a.jpg',
      );

      final renamed = user.copyWith(firstName: 'Ada', lastName: 'L.');

      expect(renamed.profilePictureUrl, user.profilePictureUrl);
      expect(renamed.profilePictureStoragePath, user.profilePictureStoragePath);
    });
  });

  group('User.toMap profile picture fields', () {
    test('writes url and storage path, and omits the legacy path', () {
      const user = User(
        id: 'u1',
        firstName: 'Ada',
        lastName: '',
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
        firstName: 'Ada',
        lastName: '',
        email: 'ada@example.com',
        profilePicturePath: r'C:\old\path.png',
      );

      final map = user.toMap();

      expect(map['profile_picture_path'], r'C:\old\path.png');
      expect(map.containsKey('profile_picture_url'), isFalse);
    });
  });

  group('User role helpers', () {
    test('exposes Trainee, Teacher, and Admin constants', () {
      expect(User.roleTrainee, 'Trainee');
      expect(User.roleTeacher, 'Teacher');
      expect(User.roleAdmin, 'Admin');
    });

    test('isTrainee / isTeacher / isAdmin follow the role field', () {
      const trainee = User(
        firstName: 'A',
        lastName: 'B',
        email: 'a@example.com',
      );
      const teacher = User(
        firstName: 'A',
        lastName: 'B',
        email: 'a@example.com',
        role: User.roleTeacher,
      );
      const admin = User(
        firstName: 'A',
        lastName: 'B',
        email: 'a@example.com',
        role: User.roleAdmin,
      );

      expect(trainee.isTrainee, isTrue);
      expect(trainee.isTeacher, isFalse);
      expect(trainee.isAdmin, isFalse);

      expect(teacher.isTeacher, isTrue);
      expect(teacher.isTrainee, isFalse);
      expect(teacher.isAdmin, isFalse);

      expect(admin.isAdmin, isTrue);
      expect(admin.isTrainee, isFalse);
      expect(admin.isTeacher, isFalse);
    });
  });
}
