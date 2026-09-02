import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _commitDeletes(
  FakeFirebaseFirestore firestore,
  List<DocumentReference> refs,
) async {
  for (final ref in refs) {
    await firestore.doc(ref.path).delete();
  }
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  test('deleting a Trainee removes their group memberships only', () async {
    await firestore
        .collection(FirestoreCollections.groupMemberships)
        .doc('g1_trainee')
        .set({
          'group_id': 'g1',
          'teacher_id': 'teacher-1',
          'trainee_id': 'trainee-1',
          'status': 'approved',
        });
    await firestore
        .collection(FirestoreCollections.groupMemberships)
        .doc('g1_other')
        .set({
          'group_id': 'g1',
          'teacher_id': 'teacher-1',
          'trainee_id': 'other-trainee',
          'status': 'approved',
        });
    await firestore.collection(FirestoreCollections.groups).doc('g1').set({
      'teacher_id': 'teacher-1',
      'invite_code': '7KPMXR4DQ2WT',
    });

    await purgePhase2GroupDataForAccountErasure(
      firestore: firestore,
      uid: 'trainee-1',
      commitDeletes: (refs) => _commitDeletes(firestore, refs),
    );

    expect(
      (await firestore
              .collection(FirestoreCollections.groupMemberships)
              .doc('g1_trainee')
              .get())
          .exists,
      isFalse,
    );
    expect(
      (await firestore
              .collection(FirestoreCollections.groupMemberships)
              .doc('g1_other')
              .get())
          .exists,
      isTrue,
    );
    expect(
      (await firestore.collection(FirestoreCollections.groups).doc('g1').get())
          .exists,
      isTrue,
    );
  });

  test(
    'deleting a Teacher removes owned groups, invites, and memberships',
    () async {
      await firestore.collection(FirestoreCollections.groups).doc('g1').set({
        'teacher_id': 'teacher-1',
        'invite_code': '7KPMXR4DQ2WT',
      });
      await firestore
          .collection(FirestoreCollections.groups)
          .doc('g1')
          .collection('lifecycle')
          .doc('status')
          .set({'status': 'active'});
      await firestore
          .collection(FirestoreCollections.groupInvites)
          .doc('7KPMXR4DQ2WT')
          .set({'group_id': 'g1', 'teacher_id': 'teacher-1'});
      await firestore
          .collection(FirestoreCollections.groupMemberships)
          .doc('g1_trainee')
          .set({
            'group_id': 'g1',
            'teacher_id': 'teacher-1',
            'trainee_id': 'trainee-1',
            'status': 'approved',
          });
      await firestore
          .collection(FirestoreCollections.groups)
          .doc('g1')
          .collection(FirestoreCollections.classroomAnnouncements)
          .doc('announcement-1')
          .set({
            'group_id': 'g1',
            'teacher_id': 'teacher-1',
            'title': 'Reminder',
            'body': 'Practice Hand Stall.',
          });
      await firestore.collection(FirestoreCollections.groups).doc('g2').set({
        'teacher_id': 'teacher-2',
        'invite_code': 'ABCD2345EFGH',
      });
      await firestore
          .collection(FirestoreCollections.groupInvites)
          .doc('ABCD2345EFGH')
          .set({'group_id': 'g2', 'teacher_id': 'teacher-2'});

      await purgePhase2GroupDataForAccountErasure(
        firestore: firestore,
        uid: 'teacher-1',
        commitDeletes: (refs) => _commitDeletes(firestore, refs),
      );

      expect(
        (await firestore
                .collection(FirestoreCollections.groups)
                .doc('g1')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.groups)
                .doc('g1')
                .collection('lifecycle')
                .doc('status')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.groupInvites)
                .doc('7KPMXR4DQ2WT')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.groupMemberships)
                .doc('g1_trainee')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.groups)
                .doc('g1')
                .collection(FirestoreCollections.classroomAnnouncements)
                .doc('announcement-1')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.groups)
                .doc('g2')
                .get())
            .exists,
        isTrue,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.groupInvites)
                .doc('ABCD2345EFGH')
                .get())
            .exists,
        isTrue,
      );
    },
  );

  test(
    'account erasure removes classroom access contexts for either participant',
    () async {
      final contexts = firestore.collection(
        FirestoreCollections.classroomTeacherAccess,
      );
      await contexts.doc('teacher-1_trainee-1').set({
        'teacher_id': 'teacher-1',
        'trainee_id': 'trainee-1',
        'group_id': 'g1',
        'schema_version': 1,
        'updated_at': DateTime.utc(2026, 8, 16),
      });
      await contexts.doc('teacher-2_trainee-1').set({
        'teacher_id': 'teacher-2',
        'trainee_id': 'trainee-1',
        'group_id': 'g2',
        'schema_version': 1,
        'updated_at': DateTime.utc(2026, 8, 16),
      });
      await contexts.doc('teacher-2_trainee-2').set({
        'teacher_id': 'teacher-2',
        'trainee_id': 'trainee-2',
        'group_id': 'g2',
        'schema_version': 1,
        'updated_at': DateTime.utc(2026, 8, 16),
      });

      await purgeClassroomTeacherAccessForAccountErasure(
        firestore: firestore,
        uid: 'trainee-1',
        commitDeletes: (refs) => _commitDeletes(firestore, refs),
      );

      expect((await contexts.doc('teacher-1_trainee-1').get()).exists, isFalse);
      expect((await contexts.doc('teacher-2_trainee-1').get()).exists, isFalse);
      expect((await contexts.doc('teacher-2_trainee-2').get()).exists, isTrue);
    },
  );

  test('purge failure still prevents Auth deletion', () async {
    var authDeleteCalls = 0;

    await expectLater(
      () => finishAccountDeletionAfterPurge(
        purgeUserData: () async {
          throw AccountPurgeStageException(
            stage: 'group data purge',
            cause: StateError('simulated failure'),
          );
        },
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
  });
}
