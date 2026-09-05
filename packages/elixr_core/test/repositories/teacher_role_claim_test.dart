import 'dart:io';

import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'an existing Teacher token is accepted without a forced refresh',
    () async {
      final calls = <String>[];

      await finalizeTeacherRoleClaim(
        readBearerToken: () async {
          calls.add('bearer');
          return 'current-teacher-token';
        },
        invokeFinalizer: (token) async {
          calls.add('verify:$token');
          return HttpStatus.ok;
        },
        forceRefreshBearerToken: () async {
          calls.add('force-refresh');
          return 'unexpected-refresh';
        },
      );

      expect(calls, <String>['bearer', 'verify:current-teacher-token']);
    },
  );

  test(
    'a refresh-required response forces one token refresh and verifies it',
    () async {
      final calls = <String>[];
      var verificationCount = 0;

      await finalizeTeacherRoleClaim(
        readBearerToken: () async {
          calls.add('bearer');
          return 'token-before-claim';
        },
        invokeFinalizer: (token) async {
          calls.add('verify:$token');
          verificationCount++;
          return verificationCount == 1 ? HttpStatus.accepted : HttpStatus.ok;
        },
        forceRefreshBearerToken: () async {
          calls.add('force-refresh');
          return 'refreshed-token';
        },
      );

      expect(calls, <String>[
        'bearer',
        'verify:token-before-claim',
        'force-refresh',
        'verify:refreshed-token',
      ]);
    },
  );

  test('invalid server evidence fails without refreshing the token', () async {
    var refreshCalls = 0;

    await expectLater(
      finalizeTeacherRoleClaim(
        readBearerToken: () async => 'token',
        invokeFinalizer: (_) async => HttpStatus.forbidden,
        forceRefreshBearerToken: () async {
          refreshCalls++;
          return 'refreshed-token';
        },
      ),
      throwsA(
        isA<TeacherRoleClaimException>().having(
          (error) => error.kind,
          'kind',
          TeacherRoleClaimFailureKind.invalidEvidence,
        ),
      ),
    );
    expect(refreshCalls, 0);
  });

  test(
    'invalid evidence on the verification request remains fail-closed',
    () async {
      var verificationCount = 0;

      await expectLater(
        finalizeTeacherRoleClaim(
          readBearerToken: () async => 'token-before-claim',
          invokeFinalizer: (_) async {
            verificationCount++;
            return verificationCount == 1
                ? HttpStatus.accepted
                : HttpStatus.forbidden;
          },
          forceRefreshBearerToken: () async => 'refreshed-token',
        ),
        throwsA(
          isA<TeacherRoleClaimException>().having(
            (error) => error.kind,
            'kind',
            TeacherRoleClaimFailureKind.invalidEvidence,
          ),
        ),
      );
    },
  );

  test(
    'a refreshed token without a server-verified claim fails boundedly',
    () async {
      var verificationCount = 0;
      var refreshCalls = 0;

      await expectLater(
        finalizeTeacherRoleClaim(
          readBearerToken: () async => 'token-before-claim',
          invokeFinalizer: (_) async {
            verificationCount++;
            return HttpStatus.accepted;
          },
          forceRefreshBearerToken: () async {
            refreshCalls++;
            return 'refreshed-token';
          },
        ),
        throwsA(
          isA<TeacherRoleClaimException>().having(
            (error) => error.kind,
            'kind',
            TeacherRoleClaimFailureKind.missingClaim,
          ),
        ),
      );

      expect(verificationCount, 2);
      expect(refreshCalls, 1);
    },
  );

  test('an unavailable raw token fails without invoking the server', () async {
    var verifyCalls = 0;

    await expectLater(
      finalizeTeacherRoleClaim(
        readBearerToken: () async => null,
        invokeFinalizer: (_) async {
          verifyCalls++;
          return HttpStatus.ok;
        },
        forceRefreshBearerToken: () async => 'unused',
      ),
      throwsA(
        isA<TeacherRoleClaimException>().having(
          (error) => error.kind,
          'kind',
          TeacherRoleClaimFailureKind.unavailable,
        ),
      ),
    );
    expect(verifyCalls, 0);
  });
}
