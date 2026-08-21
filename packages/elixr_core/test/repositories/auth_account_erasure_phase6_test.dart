import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'submission video purge collects trainee and teacher paths before attempts are removed',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('review_sub_a')
          .set({
            'trainee_id': 'trainee-1',
            'teacher_id': 'teacher-2',
            'video_storage_path':
                'assignment_submissions/teacher-2/g1/asg1/trainee-1/review_sub_a.mp4',
          });
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('review_sub_b')
          .set({
            'trainee_id': 'trainee-9',
            'teacher_id': 'teacher-1',
            'video_storage_path':
                'assignment_submissions/teacher-1/g1/asg2/trainee-9/review_sub_b.mp4',
          });
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('review_sub_keep')
          .set({
            'trainee_id': 'other',
            'teacher_id': 'other-teacher',
            'video_storage_path':
                'assignment_submissions/other-teacher/g1/asg3/other/review_sub_keep.mp4',
          });
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('no_video')
          .set({'trainee_id': 'teacher-1', 'teacher_id': 'teacher-1'});

      final deleted = <String>[];
      await purgeAssignmentSubmissionVideosForAccountErasure(
        firestore: firestore,
        uid: 'teacher-1',
        deleteObject: (path) async {
          deleted.add(path);
        },
      );

      expect(
        deleted,
        unorderedEquals([
          'assignment_submissions/teacher-1/g1/asg2/trainee-9/review_sub_b.mp4',
        ]),
      );
      expect(
        (await firestore
                .collection(FirestoreCollections.assignmentAttempts)
                .doc('review_sub_b')
                .get())
            .exists,
        isTrue,
      );
    },
  );

  test('object-not-found is treated as clean during submission purge', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection(FirestoreCollections.assignmentAttempts)
        .doc('review_sub_missing')
        .set({
          'trainee_id': 'trainee-1',
          'teacher_id': 'teacher-1',
          'video_storage_path':
              'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_missing.mp4',
        });

    await purgeAssignmentSubmissionVideosForAccountErasure(
      firestore: firestore,
      uid: 'trainee-1',
      deleteObject: (path) async {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'object-not-found',
        );
      },
    );
  });

  test(
    'submitted teacher_review_submission derives the canonical Storage path',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('review_sub_submitted')
          .set({
            'attempt_kind': 'teacher_review_submission',
            'trainee_id': 'trainee-1',
            'teacher_id': 'teacher-1',
            'group_id': 'g1',
            'assignment_id': 'asg1',
            'status': 'submitted',
            'video_storage_path':
                'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_submitted.mp4',
          });

      final deleted = <String>[];
      await purgeAssignmentSubmissionVideosForAccountErasure(
        firestore: firestore,
        uid: 'trainee-1',
        deleteObject: (path) async {
          deleted.add(path);
        },
      );

      expect(deleted, [
        'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_submitted.mp4',
      ]);
      expect(
        (await firestore
                .collection(FirestoreCollections.assignmentAttempts)
                .doc('review_sub_submitted')
                .get())
            .exists,
        isTrue,
      );
    },
  );

  test(
    'abandoned draft without video_storage_path still purges the canonical object',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('review_sub_abandoned')
          .set({
            'attempt_kind': 'teacher_review_submission',
            'trainee_id': 'trainee-1',
            'teacher_id': 'teacher-1',
            'group_id': 'g1',
            'assignment_id': 'asg1',
            'status': 'draft',
            'abandoned_at': DateTime.utc(2026, 8, 21),
          });

      final deleted = <String>[];
      await purgeAssignmentSubmissionVideosForAccountErasure(
        firestore: firestore,
        uid: 'trainee-1',
        deleteObject: (path) async {
          deleted.add(path);
        },
      );

      expect(deleted, [
        'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_abandoned.mp4',
      ]);
    },
  );

  test(
    'abandoned draft object-not-found is treated as clean during erasure',
    () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection(FirestoreCollections.assignmentAttempts)
          .doc('review_sub_gone')
          .set({
            'attempt_kind': 'teacher_review_submission',
            'trainee_id': 'trainee-1',
            'teacher_id': 'teacher-1',
            'group_id': 'g1',
            'assignment_id': 'asg1',
            'status': 'draft',
          });

      await purgeAssignmentSubmissionVideosForAccountErasure(
        firestore: firestore,
        uid: 'trainee-1',
        deleteObject: (path) async {
          expect(
            path,
            'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_gone.mp4',
          );
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'object-not-found',
          );
        },
      );
    },
  );

  test('non-not-found Storage failure fails account erasure closed', () async {
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection(FirestoreCollections.assignmentAttempts)
        .doc('review_sub_stuck')
        .set({
          'attempt_kind': 'teacher_review_submission',
          'trainee_id': 'trainee-1',
          'teacher_id': 'teacher-1',
          'group_id': 'g1',
          'assignment_id': 'asg1',
          'status': 'draft',
        });

    await expectLater(
      purgeAssignmentSubmissionVideosForAccountErasure(
        firestore: firestore,
        uid: 'trainee-1',
        deleteObject: (path) async {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'retry-limit-exceeded',
          );
        },
      ),
      throwsA(
        isA<FirebaseException>().having(
          (error) => error.code,
          'code',
          'retry-limit-exceeded',
        ),
      ),
    );
  });
}
