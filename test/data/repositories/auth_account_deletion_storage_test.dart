import 'dart:typed_data';

import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/profile_image_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopProfileImages implements ProfileImageRepositoryBase {
  @override
  Future<void> deleteProfileImage({
    required String authenticatedUid,
    required String storagePath,
  }) async {}

  @override
  Future<ProfileImageUploadResult> uploadProfileImage({
    required String userId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  test(
    'non-object-not-found Storage list error propagates from profile storage purge',
    () async {
      await expectLater(
        () => deleteProfileStorageObjects(
          uid: 'uid-1',
          storagePath: null,
          profileImages: _NoopProfileImages(),
          listObjectPaths: (_) async {
            throw FirebaseException(
              plugin: 'firebase_storage',
              code: 'deadline-exceeded',
              message: 'timed out',
            );
          },
        ),
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'deadline-exceeded',
          ),
        ),
      );
    },
  );

  test(
    'object-not-found during Storage list is treated as already clean',
    () async {
      await deleteProfileStorageObjects(
        uid: 'uid-1',
        storagePath: null,
        profileImages: _NoopProfileImages(),
        listObjectPaths: (_) async {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
            message: 'missing',
          );
        },
      );
    },
  );

  test(
    'Storage purge failure prevents Auth.delete from running',
    () async {
      var authDeleteCalls = 0;

      await expectLater(
        () => finishAccountDeletionAfterPurge(
          purgeUserData: () => deleteProfileStorageObjects(
            uid: 'uid-1',
            storagePath: null,
            profileImages: _NoopProfileImages(),
            listObjectPaths: (_) async {
              throw FirebaseException(
                plugin: 'firebase_storage',
                code: 'deadline-exceeded',
                message: 'timed out',
              );
            },
          ),
          deleteAuthUser: () async {
            authDeleteCalls++;
          },
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            equals('Exception: $accountErasurePurgeFailedMessage'),
          ),
        ),
      );

      expect(authDeleteCalls, 0);
    },
  );

  test(
    'purge failure message does not embed raw Firebase plugin details',
    () async {
      await expectLater(
        () => finishAccountDeletionAfterPurge(
          purgeUserData: () async {
            throw AccountPurgeStageException(
              stage: 'daily quest board purge',
              cause: FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
                message: 'Missing or insufficient permissions',
              ),
            );
          },
          deleteAuthUser: () async {},
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(
              equals('Exception: $accountErasurePurgeFailedMessage'),
              isNot(contains('permission-denied')),
              isNot(contains('cloud_firestore')),
            ),
          ),
        ),
      );
    },
  );
}
