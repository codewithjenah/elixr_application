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

  test(
    'Teacher erasure removes owned movements, revisions, and assignments',
    () async {
      final movementRef = firestore
          .collection(FirestoreCollections.teacherMovements)
          .doc('tm1');
      await movementRef.set({
        'teacher_id': 'teacher-1',
        'title': 'Tin Balance',
        'status': 'active',
        'current_revision_id': 'rev1',
      });
      await movementRef
          .collection(FirestoreCollections.teacherMovementRevisions)
          .doc('rev1')
          .set({'teacher_id': 'teacher-1', 'movement_id': 'tm1'});
      await firestore
          .collection(FirestoreCollections.teacherMovements)
          .doc('tm-other')
          .set({'teacher_id': 'teacher-2', 'title': 'Keep'});
      await firestore
          .collection(FirestoreCollections.groupAssignments)
          .doc('asg1')
          .set({'teacher_id': 'teacher-1', 'group_id': 'g1'});
      await firestore
          .collection(FirestoreCollections.groupAssignments)
          .doc('asg2')
          .set({'teacher_id': 'teacher-2', 'group_id': 'g2'});

      await purgePhase5ClassroomOwnedDataForAccountErasure(
        firestore: firestore,
        uid: 'teacher-1',
        commitDeletes: (refs) => _commitDeletes(firestore, refs),
      );

      expect((await movementRef.get()).exists, isFalse);
      expect(
        (await movementRef
                .collection(FirestoreCollections.teacherMovementRevisions)
                .doc('rev1')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.teacherMovements)
                .doc('tm-other')
                .get())
            .exists,
        isTrue,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.groupAssignments)
                .doc('asg1')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.groupAssignments)
                .doc('asg2')
                .get())
            .exists,
        isTrue,
      );
    },
  );

  test(
    'attempt erasure removes trainee and teacher classroom pointers',
    () async {
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('a1')
          .set({'trainee_id': 'trainee-1', 'teacher_id': 'teacher-2'});
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('a2')
          .set({'trainee_id': 'trainee-2', 'teacher_id': 'teacher-1'});
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('a3')
          .set({'trainee_id': 'other', 'teacher_id': 'other-teacher'});

      await purgePhase5AssignmentAttemptsForAccountErasure(
        firestore: firestore,
        uid: 'teacher-1',
        commitDeletes: (refs) => _commitDeletes(firestore, refs),
      );

      expect(
        (await firestore
                .collection(FirestoreCollections.assignmentAttempts)
                .doc('a2')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.assignmentAttempts)
                .doc('a1')
                .get())
            .exists,
        isTrue,
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.assignmentAttempts)
                .doc('a3')
                .get())
            .exists,
        isTrue,
      );
    },
  );

  test(
    'account erasure removes private assignment recipient projections',
    () async {
      final assignment = firestore
          .collection(FirestoreCollections.groupAssignments)
          .doc('asg1');
      Future<void> seedRecipient(
        String docId,
        String teacherId,
        String traineeId,
      ) {
        return assignment
            .collection(FirestoreCollections.assignmentRecipients)
            .doc(docId)
            .set({
              'assignment_id': 'asg1',
              'group_id': 'g1',
              'teacher_id': teacherId,
              'trainee_id': traineeId,
              'audience_type': 'selected_students',
              'schema_version': 1,
              'created_at': Timestamp.now(),
            });
      }

      await seedRecipient('trainee-1', 'teacher-2', 'trainee-1');
      await seedRecipient('trainee-2', 'teacher-1', 'trainee-2');
      await seedRecipient('trainee-3', 'teacher-2', 'trainee-3');

      await purgeAssignmentRecipientsForAccountErasure(
        firestore: firestore,
        uid: 'trainee-1',
        commitDeletes: (refs) => _commitDeletes(firestore, refs),
      );
      expect(
        (await assignment
                .collection(FirestoreCollections.assignmentRecipients)
                .doc('trainee-1')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await assignment
                .collection(FirestoreCollections.assignmentRecipients)
                .doc('trainee-2')
                .get())
            .exists,
        isTrue,
      );

      await purgeAssignmentRecipientsForAccountErasure(
        firestore: firestore,
        uid: 'teacher-1',
        commitDeletes: (refs) => _commitDeletes(firestore, refs),
      );
      expect(
        (await assignment
                .collection(FirestoreCollections.assignmentRecipients)
                .doc('trainee-2')
                .get())
            .exists,
        isFalse,
      );
      expect(
        (await assignment
                .collection(FirestoreCollections.assignmentRecipients)
                .doc('trainee-3')
                .get())
            .exists,
        isTrue,
      );
    },
  );
}
