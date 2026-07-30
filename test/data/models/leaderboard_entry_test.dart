import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LeaderboardEntry.tryFromMap', () {
    test('parses a complete Firestore map', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada Lovelace',
        'total_xp': 250,
        'sessions_completed': 10,
        'score_sum': 800,
        'average_score': 80,
        'best_score': 95,
        'last_session_at': '2026-07-27T10:00:00.000',
        'updated_at': '2026-07-27T10:00:00.000',
      });

      expect(entry, isNotNull);
      expect(entry!.userId, 'u1');
      expect(entry.displayName, 'Ada Lovelace');
      expect(entry.totalXp, 250);
      expect(entry.sessionsCompleted, 10);
      expect(entry.scoreSum, 800);
      expect(entry.averageScore, 80);
      expect(entry.bestScore, 95);
      expect(entry.level, 2);
      expect(entry.xpIntoLevel, 0);
      expect(entry.profilePictureUrl, isNull);
    });

    test('parses profile_picture_url when present', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada Lovelace',
        'total_xp': 25,
        'profile_picture_url': 'https://storage.example/avatar.jpg',
      });

      expect(entry, isNotNull);
      expect(entry!.profilePictureUrl, 'https://storage.example/avatar.jpg');
    });

    test('treats missing, empty, or invalid profile_picture_url as null', () {
      final missing = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
      });
      expect(missing!.profilePictureUrl, isNull);

      final empty = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
        'profile_picture_url': '   ',
      });
      expect(empty!.profilePictureUrl, isNull);

      final wrongType = LeaderboardEntry.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Ada',
        'total_xp': 25,
        'profile_picture_url': 42,
      });
      expect(wrongType!.profilePictureUrl, isNull);
    });

    test('tolerates missing optional fields and uses document id', () {
      final entry = LeaderboardEntry.tryFromMap({
        'display_name': 'Grace',
        'total_xp': 25,
      }, id: 'u2');

      expect(entry, isNotNull);
      expect(entry!.userId, 'u2');
      expect(entry.sessionsCompleted, 0);
      expect(entry.scoreSum, 0);
      expect(entry.averageScore, 0);
      expect(entry.bestScore, 0);
      expect(entry.lastSessionAt, isNull);
      expect(entry.updatedAt, isNull);
      expect(entry.level, 1);
    });

    test('accepts numeric values as int or double', () {
      final entry = LeaderboardEntry.tryFromMap({
        'user_id': 'u3',
        'display_name': 'Alan',
        'total_xp': 25.0,
        'sessions_completed': 1.0,
        'score_sum': 88,
        'average_score': 88.5,
        'best_score': 88.0,
      });

      expect(entry, isNotNull);
      expect(entry!.totalXp, 25);
      expect(entry.sessionsCompleted, 1);
      expect(entry.scoreSum, 88);
      expect(entry.averageScore, 88.5);
      expect(entry.bestScore, 88);
    });

    test('returns null when identity fields are invalid', () {
      expect(LeaderboardEntry.tryFromMap({'display_name': 'X'}), isNull);
      expect(LeaderboardEntry.tryFromMap({'user_id': 'u1'}), isNull);
      expect(
        LeaderboardEntry.tryFromMap({'user_id': '', 'display_name': 'X'}),
        isNull,
      );
      expect(
        LeaderboardEntry.tryFromMap({'user_id': 'u1', 'display_name': '   '}),
        isNull,
      );
    });
  });
}
