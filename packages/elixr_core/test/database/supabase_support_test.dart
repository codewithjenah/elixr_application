import 'dart:async';
import 'dart:io';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:elixr_core/database/user_profile_store.dart';
import 'package:elixr_core/models/teacher_access_code_exception.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_core/repositories/supabase_teacher_access_code_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart' hide User;

void main() {
  group('row mapping', () {
    test('compactRow drops null columns like absent document fields', () {
      expect(compactRow({'a': 1, 'b': null, 'c': 'x'}), {'a': 1, 'c': 'x'});
    });

    test('asRowMap rejects non-object RPC results', () {
      expect(() => asRowMap([1]), throwsFormatException);
      expect(asRowMap({'id': 'a', 'n': null}), {'id': 'a'});
    });

    test('rowsFrom parses a JSON array of objects', () {
      expect(
        rowsFrom([
          {'id': 'a', 'x': null},
        ]),
        [
          {'id': 'a'},
        ],
      );
      expect(() => rowsFrom({'id': 'a'}), throwsFormatException);
    });

    test('newDocumentId has the persisted 20-character shape', () {
      final ids = {for (var i = 0; i < 50; i++) newDocumentId()};
      expect(ids, hasLength(50));
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[A-Za-z0-9]{20}$')));
      }
    });
  });

  group('error classification', () {
    test('stable RPC codes come from the database error message', () {
      const error = PostgrestException(
        message: 'attempt_exists',
        code: 'P0001',
      );
      expect(backendErrorCode(error), 'attempt_exists');
      expect(isPermissionDeniedError(error), isFalse);
    });

    test('forbidden and RLS failures are permission denials', () {
      expect(
        isPermissionDeniedError(
          const PostgrestException(message: 'forbidden', code: '42501'),
        ),
        isTrue,
      );
      expect(
        isPermissionDeniedError(
          const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
        ),
        isTrue,
      );
      expect(
        isPermissionDeniedError(
          const StorageException('Unauthorized', statusCode: '403'),
        ),
        isTrue,
      );
      expect(isPermissionDeniedError(StateError('x')), isFalse);
    });

    test('missing storage objects are recognized', () {
      expect(
        isStorageObjectNotFound(
          const StorageException('Object not found', statusCode: '404'),
        ),
        isTrue,
      );
      expect(
        isStorageObjectNotFound(
          const StorageException('Payload too large', statusCode: '413'),
        ),
        isFalse,
      );
    });

    test('only transport failures are treated as backend unavailability', () {
      expect(isBackendUnavailableError(const SocketException('down')), isTrue);
      expect(isBackendUnavailableError(TimeoutException('slow')), isTrue);
      expect(
        isBackendUnavailableError(
          const PostgrestException(message: 'forbidden', code: '42501'),
        ),
        isFalse,
      );
    });
  });

  group('storage bucket mapping', () {
    test('persisted object paths map to their private buckets', () {
      expect(
        storageBucketForPath('users/u1/profile/avatar.jpg'),
        'profile-images',
      );
      expect(
        storageBucketForPath('users/u1/session_evidence/s1.jpg'),
        'session-evidence',
      );
      expect(
        storageBucketForPath('users/u1/custom_movement_references/m/r.jpg'),
        'custom-movement-references',
      );
      expect(
        storageBucketForPath('assignment_submissions/t/g/a/u/x.mp4'),
        'assignment-submissions',
      );
      expect(
        storageBucketForPath('teacher_activity_demos/t/x.mp4'),
        'teacher-activity-demos',
      );
      expect(
        storageBucketForPath('activity_material_staging/t/a/u'),
        'activity-learning-materials',
      );
      expect(() => storageBucketForPath('other/x'), throwsArgumentError);
    });
  });

  group('profile creation parameters', () {
    test('require current legal consent', () {
      const user = User(
        id: 'u1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        role: User.roleTrainee,
      );
      final params = SupabaseUserProfileStore.createProfileParams(
        user,
        legalConsent: RegistrationLegalConsent.current(),
      );
      expect(params['p_role'], User.roleTrainee);
      expect(
        params['p_privacy_policy_version'],
        RegistrationLegalConsent.currentPrivacyPolicyVersion,
      );
      // Identity and email are derived from the session server-side.
      expect(params.keys, isNot(contains('p_email')));
      expect(params.keys, isNot(contains('p_user_id')));
    });
  });

  group('server error mapping', () {
    test('Teacher claim evidence failures fail closed with a stable kind', () {
      final invalid = teacherRoleClaimExceptionFor(
        const PostgrestException(
          message: 'teacher_evidence_invalid',
          code: '42501',
        ),
      );
      expect(invalid.kind, TeacherRoleClaimFailureKind.invalidEvidence);
      final unavailable = teacherRoleClaimExceptionFor(
        const SocketException('down'),
      );
      expect(unavailable.kind, TeacherRoleClaimFailureKind.unavailable);
    });

    test('access-code RPC codes map to typed Teacher access errors', () {
      TeacherAccessCodeError? kind(String code) =>
          SupabaseTeacherAccessCodeRepository.exceptionFor(
            PostgrestException(message: code, code: 'P0001'),
          )?.code;
      expect(
        kind('access_code_consumed'),
        TeacherAccessCodeError.alreadyConsumed,
      );
      expect(kind('access_code_not_found'), TeacherAccessCodeError.notFound);
      expect(kind('malformed_code'), TeacherAccessCodeError.malformedCode);
      expect(kind('something_else'), isNull);
    });
  });
}
