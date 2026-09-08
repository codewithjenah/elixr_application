import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(LeaderboardRepository.clearLastActiveTouchForTest);

  group('LeaderboardPresencePolicy', () {
    final now = DateTime.utc(2026, 9, 8, 12);

    test('does not write when the leaderboard document is missing', () {
      expect(
        LeaderboardPresencePolicy.shouldWrite(
          documentExists: false,
          nowUtc: now,
        ),
        isFalse,
      );
    });

    test('rate-limits even when the leaderboard document is missing', () {
      expect(
        LeaderboardPresencePolicy.shouldWrite(
          documentExists: false,
          nowUtc: now,
          lastWriteUtc: now.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('writes the first touch on an existing document', () {
      expect(
        LeaderboardPresencePolicy.shouldWrite(
          documentExists: true,
          nowUtc: now,
        ),
        isTrue,
      );
    });

    test('legacy documents without last_active_at remain eligible', () {
      expect(
        LeaderboardPresencePolicy.shouldWrite(
          documentExists: true,
          nowUtc: now,
          persistedLastActiveAt: null,
        ),
        isTrue,
      );
    });

    test('persisted last_active_at younger than 10 minutes skips update', () {
      expect(
        LeaderboardPresencePolicy.shouldWrite(
          documentExists: true,
          nowUtc: now,
          persistedLastActiveAt: now.subtract(
            const Duration(minutes: 9, seconds: 59),
          ),
        ),
        isFalse,
      );
    });

    test('persisted last_active_at at the minimum interval permits update', () {
      expect(
        LeaderboardPresencePolicy.shouldWrite(
          documentExists: true,
          nowUtc: now,
          persistedLastActiveAt: now.subtract(const Duration(minutes: 10)),
        ),
        isTrue,
      );
    });

    test('suppresses only a permission denial explained by a recent write', () {
      expect(
        LeaderboardPresencePolicy.shouldSuppressPermissionDenied(
          documentExists: true,
          nowUtc: now,
          persistedLastActiveAt: now.subtract(const Duration(minutes: 1)),
        ),
        isTrue,
      );
      expect(
        LeaderboardPresencePolicy.shouldSuppressPermissionDenied(
          documentExists: true,
          nowUtc: now,
          persistedLastActiveAt: now.subtract(const Duration(minutes: 10)),
        ),
        isFalse,
      );
      expect(
        LeaderboardPresencePolicy.shouldSuppressPermissionDenied(
          documentExists: false,
          nowUtc: now,
          persistedLastActiveAt: now.subtract(const Duration(minutes: 1)),
        ),
        isFalse,
      );
    });

    test('rate-limits repeated touches within 10 minutes', () {
      expect(
        LeaderboardPresencePolicy.shouldWrite(
          documentExists: true,
          nowUtc: now,
          lastWriteUtc: now.subtract(const Duration(minutes: 9, seconds: 59)),
        ),
        isFalse,
      );
      expect(
        LeaderboardPresencePolicy.shouldWrite(
          documentExists: true,
          nowUtc: now,
          lastWriteUtc: now.subtract(const Duration(minutes: 10)),
        ),
        isTrue,
      );
    });

    test('update payload only contains last_active_at', () {
      const sentinel = 'server-timestamp';
      expect(LeaderboardPresencePolicy.buildUpdate(sentinel), {
        'last_active_at': sentinel,
      });
    });

    test('missing leaderboard document still does not create a row', () {
      expect(
        LeaderboardPresencePolicy.shouldWrite(
          documentExists: false,
          nowUtc: now,
          persistedLastActiveAt: now.subtract(const Duration(hours: 1)),
        ),
        isFalse,
      );
    });

    test('malformed persisted last_active_at is ignored', () {
      expect(LeaderboardPresencePolicy.persistedLastActiveAt(null), isNull);
      expect(LeaderboardPresencePolicy.persistedLastActiveAt(42), isNull);
      expect(LeaderboardPresencePolicy.persistedLastActiveAt(now), now);
    });
  });
}
