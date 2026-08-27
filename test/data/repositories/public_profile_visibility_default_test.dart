import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_core/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PublicProfileRootCreation', () {
    test('new-account seed payload uses public visibility', () {
      final fields = PublicProfileRootCreation.fields(
        userId: 'u1',
        displayName: 'Ada Lovelace',
        initialVisibility: ProfileVisibility.public,
        profilePictureUrl: ' https://example.com/a.png ',
        createdAt: 'created',
        updatedAt: 'updated',
      );

      expect(fields['user_id'], 'u1');
      expect(fields['display_name'], 'Ada Lovelace');
      expect(fields['visibility'], 'public');
      expect(fields['schema_version'], 1);
      expect(fields['profile_picture_url'], 'https://example.com/a.png');
      expect(fields['created_at'], 'created');
      expect(fields['updated_at'], 'updated');
    });

    test('repair/backfill payload uses private visibility', () {
      final fields = PublicProfileRootCreation.fields(
        userId: 'u1',
        displayName: 'Ada',
        initialVisibility: ProfileVisibility.private,
        createdAt: 'created',
        updatedAt: 'updated',
      );

      expect(fields['visibility'], 'private');
      expect(fields.containsKey('profile_picture_url'), isFalse);
    });

    test('empty profile picture URL is omitted', () {
      final fields = PublicProfileRootCreation.fields(
        userId: 'u1',
        displayName: 'Ada',
        initialVisibility: ProfileVisibility.public,
        profilePictureUrl: '   ',
        createdAt: 'created',
        updatedAt: 'updated',
      );

      expect(fields.containsKey('profile_picture_url'), isFalse);
    });

    test('includes role when non-empty', () {
      final fields = PublicProfileRootCreation.fields(
        userId: 'u1',
        displayName: 'Ada',
        initialVisibility: ProfileVisibility.public,
        role: ' Teacher ',
        createdAt: 'created',
        updatedAt: 'updated',
      );

      expect(fields['role'], User.roleTeacher);
    });

    test('omits role when empty or missing', () {
      final missing = PublicProfileRootCreation.fields(
        userId: 'u1',
        displayName: 'Ada',
        initialVisibility: ProfileVisibility.public,
        createdAt: 'created',
        updatedAt: 'updated',
      );
      final empty = PublicProfileRootCreation.fields(
        userId: 'u1',
        displayName: 'Ada',
        initialVisibility: ProfileVisibility.public,
        role: '   ',
        createdAt: 'created',
        updatedAt: 'updated',
      );

      expect(missing.containsKey('role'), isFalse);
      expect(empty.containsKey('role'), isFalse);
    });
  });
}
