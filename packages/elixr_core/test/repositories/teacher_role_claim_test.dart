import 'dart:io';

import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'finalizer grants then force-refreshes before accepting Teacher',
    () async {
      final calls = <String>[];

      await finalizeTeacherRoleClaim(
        readCurrentClaims: () async {
          calls.add('current');
          return <Object?, Object?>{'billingPlan': 'faculty'};
        },
        readBearerToken: () async {
          calls.add('bearer');
          return 'token-before-claim';
        },
        invokeFinalizer: (token) async {
          calls.add('grant:$token');
          return HttpStatus.ok;
        },
        forceRefreshClaims: () async {
          calls.add('force-refresh');
          return <Object?, Object?>{
            'role': 'Teacher',
            'billingPlan': 'faculty',
          };
        },
      );

      expect(calls, <String>[
        'current',
        'bearer',
        'grant:token-before-claim',
        'force-refresh',
      ]);
    },
  );

  test(
    'existing canonical claim is idempotent and performs no grant',
    () async {
      var grantCalls = 0;
      var refreshCalls = 0;

      await finalizeTeacherRoleClaim(
        readCurrentClaims: () async => <Object?, Object?>{'role': 'Teacher'},
        readBearerToken: () async => 'unused',
        invokeFinalizer: (_) async {
          grantCalls++;
          return HttpStatus.ok;
        },
        forceRefreshClaims: () async {
          refreshCalls++;
          return <Object?, Object?>{'role': 'Teacher'};
        },
      );

      expect(grantCalls, 0);
      expect(refreshCalls, 0);
    },
  );

  test('invalid server evidence fails without refreshing the token', () async {
    var refreshCalls = 0;

    await expectLater(
      finalizeTeacherRoleClaim(
        readCurrentClaims: () async => <Object?, Object?>{},
        readBearerToken: () async => 'token',
        invokeFinalizer: (_) async => HttpStatus.forbidden,
        forceRefreshClaims: () async {
          refreshCalls++;
          return <Object?, Object?>{'role': 'Teacher'};
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

  test('successful grant without refreshed claim fails closed', () async {
    await expectLater(
      finalizeTeacherRoleClaim(
        readCurrentClaims: () async => <Object?, Object?>{},
        readBearerToken: () async => 'token',
        invokeFinalizer: (_) async => HttpStatus.ok,
        forceRefreshClaims: () async => <Object?, Object?>{},
      ),
      throwsA(
        isA<TeacherRoleClaimException>().having(
          (error) => error.kind,
          'kind',
          TeacherRoleClaimFailureKind.missingClaim,
        ),
      ),
    );
  });
}
