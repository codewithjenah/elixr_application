import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not refresh when the Firebase user is still unverified', () async {
    var refreshed = false;

    await refreshStaleEmailVerifiedIdToken(
      emailVerified: false,
      readClaims: () async => {'email_verified': false},
      forceRefreshIdToken: () async => refreshed = true,
    );

    expect(refreshed, isFalse);
  });

  test(
    'does not refresh when the ID token already has email_verified',
    () async {
      var refreshed = false;

      await refreshStaleEmailVerifiedIdToken(
        emailVerified: true,
        readClaims: () async => {'email_verified': true},
        forceRefreshIdToken: () async => refreshed = true,
      );

      expect(refreshed, isFalse);
    },
  );

  test(
    'refreshes when User.emailVerified is true but the ID token claim is false',
    () async {
      var refreshed = false;

      await refreshStaleEmailVerifiedIdToken(
        emailVerified: true,
        readClaims: () async => {'email_verified': false},
        forceRefreshIdToken: () async => refreshed = true,
      );

      expect(refreshed, isTrue);
    },
  );

  test('refreshes when the ID token omits email_verified', () async {
    var refreshed = false;

    await refreshStaleEmailVerifiedIdToken(
      emailVerified: true,
      readClaims: () async => <String, dynamic>{},
      forceRefreshIdToken: () async => refreshed = true,
    );

    expect(refreshed, isTrue);
  });

  test('refreshes when cached token claims cannot be read', () async {
    var refreshed = false;

    await refreshStaleEmailVerifiedIdToken(
      emailVerified: true,
      readClaims: () async => throw Exception('token unavailable'),
      forceRefreshIdToken: () async => refreshed = true,
    );

    expect(refreshed, isTrue);
  });

  test('propagates a failed forced ID token refresh', () async {
    await expectLater(
      () => refreshStaleEmailVerifiedIdToken(
        emailVerified: true,
        readClaims: () async => {'email_verified': false},
        forceRefreshIdToken: () async => throw Exception('refresh failed'),
      ),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'toString',
          contains('refresh failed'),
        ),
      ),
    );
  });
}
