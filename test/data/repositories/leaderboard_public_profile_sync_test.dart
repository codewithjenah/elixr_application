import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaderboardRepository.publicProfileNeedsUpdate', () {
    test('returns false when display_name and picture already match', () {
      expect(
        LeaderboardRepository.publicProfileNeedsUpdate(
          existing: {
            'display_name': 'Ada',
            'profile_picture_url': 'https://example.com/a.jpg',
            'total_xp': 100,
          },
          displayName: ' Ada ',
          profilePictureUrl: ' https://example.com/a.jpg ',
        ),
        isFalse,
      );
    });

    test('returns true when display_name differs', () {
      expect(
        LeaderboardRepository.publicProfileNeedsUpdate(
          existing: {
            'display_name': 'Ada',
            'profile_picture_url': 'https://example.com/a.jpg',
          },
          displayName: 'Ada Lovelace',
          profilePictureUrl: 'https://example.com/a.jpg',
        ),
        isTrue,
      );
    });

    test('returns true when profile picture URL differs', () {
      expect(
        LeaderboardRepository.publicProfileNeedsUpdate(
          existing: {
            'display_name': 'Ada',
            'profile_picture_url': 'https://example.com/old.jpg',
          },
          displayName: 'Ada',
          profilePictureUrl: 'https://example.com/new.jpg',
        ),
        isTrue,
      );
    });

    test('returns true when picture is newly provided and missing on doc', () {
      expect(
        LeaderboardRepository.publicProfileNeedsUpdate(
          existing: {'display_name': 'Ada'},
          displayName: 'Ada',
          profilePictureUrl: 'https://example.com/a.jpg',
        ),
        isTrue,
      );
    });

    test(
      'empty incoming picture does not force update when name already matches',
      () {
        expect(
          LeaderboardRepository.publicProfileNeedsUpdate(
            existing: {
              'display_name': 'Ada',
              'profile_picture_url': 'https://example.com/a.jpg',
            },
            displayName: 'Ada',
            profilePictureUrl: null,
          ),
          isFalse,
        );
        expect(
          LeaderboardRepository.publicProfileNeedsUpdate(
            existing: {
              'display_name': 'Ada',
              'profile_picture_url': 'https://example.com/a.jpg',
            },
            displayName: 'Ada',
            profilePictureUrl: '   ',
          ),
          isFalse,
        );
      },
    );

    test('trims existing Firestore string fields before comparing', () {
      expect(
        LeaderboardRepository.publicProfileNeedsUpdate(
          existing: {
            'display_name': ' Ada ',
            'profile_picture_url': ' https://example.com/a.jpg ',
          },
          displayName: 'Ada',
          profilePictureUrl: 'https://example.com/a.jpg',
        ),
        isFalse,
      );
    });

    test('returns false when desired fields are empty', () {
      expect(
        LeaderboardRepository.publicProfileNeedsUpdate(
          existing: {'display_name': 'Ada'},
          displayName: '   ',
          profilePictureUrl: null,
        ),
        isFalse,
      );
    });

    test('clears an existing profile URL explicitly', () {
      expect(
        LeaderboardRepository.publicProfileNeedsUpdate(
          existing: {
            'display_name': 'Ada',
            'profile_picture_url': 'https://example.com/a.jpg',
          },
          displayName: 'Ada',
          clearProfilePicture: true,
        ),
        isTrue,
      );
      expect(
        LeaderboardRepository.publicProfileNeedsUpdate(
          existing: {'display_name': 'Ada'},
          displayName: 'Ada',
          clearProfilePicture: true,
        ),
        isFalse,
      );
      expect(
        LeaderboardRepository.buildPublicProfileFields(
          displayName: 'Ada',
          clearProfilePicture: true,
        ).containsKey('profile_picture_url'),
        isTrue,
      );
    });
  });
}
