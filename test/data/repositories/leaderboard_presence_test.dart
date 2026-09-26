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

    test('permits presence only for the current auth owner', () {
      expect(
        LeaderboardPresencePolicy.isAuthenticatedOwner(
          requestedUserId: 'user-a',
          currentAuthUid: 'user-a',
        ),
        isTrue,
      );
      expect(
        LeaderboardPresencePolicy.isAuthenticatedOwner(
          requestedUserId: 'user-a',
          currentAuthUid: 'user-b',
        ),
        isFalse,
      );
      expect(
        LeaderboardPresencePolicy.isAuthenticatedOwner(
          requestedUserId: 'user-a',
          currentAuthUid: null,
        ),
        isFalse,
      );
    });
  });
}
