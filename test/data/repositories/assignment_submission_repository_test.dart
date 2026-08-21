import 'dart:io';
import 'dart:typed_data';

import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_submission_limits.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/phase6_submission_diagnostics.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('submitLocalClip never awards XP and uses a new attempt', () async {
    final assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 8, 20),
      generateId: () => 'asg1',
    );
    addTearDown(assignments.dispose);
    final movements = InMemoryTeacherMovementRepository(
      now: () => DateTime.utc(2026, 8, 20),
      generateId: () => 'tm1',
    );
    addTearDown(movements.dispose);
    final movement = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Hold the tin.',
      requiredProp: TrainingProp.bottle,
    );
    final revision = (await movements.getRevision(
      movementId: movement.id,
      revisionId: movement.currentRevisionId,
    ))!;
    final assignment = await assignments.createTeacherCreatedAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher-1',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
      movement: movement,
      revision: revision,
    );
    final deleted = <String>{};
    final submissions = InMemoryAssignmentSubmissionRepository(
      classroom: assignments,
      now: () => DateTime.utc(2026, 8, 20),
      deletedPaths: deleted,
    );

    final submitted = await submissions.submitLocalClip(
      traineeId: 'trainee-1',
      assignment: assignment,
      clip: const SubmissionRecordResult(
        localPath: r'C:\Temp\elixr_submissions\clip.mp4',
        durationMs: 3500,
        sizeBytes: 2048,
        contentType: 'video/mp4',
      ),
    );

    expect(
      submitted.attemptKind,
      AssignmentAttemptKind.teacherReviewSubmission,
    );
    expect(submitted.status, AssignmentAttemptStatus.submitted);
    expect(submitted.awardsGlobalXp, isFalse);
    expect(submitted.sourceSessionId, isNull);
    expect(
      submitted.videoStoragePath,
      assignmentSubmissionStoragePath(
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: assignment.id,
        traineeId: 'trainee-1',
        attemptId: submitted.id,
      ),
    );
    expect(submitted.id, startsWith('review_sub_'));
    expect(deleted, isEmpty);
  });

  Future<GroupAssignment> teacherAssignment(
    InMemoryClassroomAssignmentRepository assignments,
  ) async {
    final movements = InMemoryTeacherMovementRepository(
      now: () => DateTime.utc(2026, 8, 20),
      generateId: () => 'tm1',
    );
    addTearDown(movements.dispose);
    final movement = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Hold the tin.',
      requiredProp: TrainingProp.bottle,
    );
    final revision = (await movements.getRevision(
      movementId: movement.id,
      revisionId: movement.currentRevisionId,
    ))!;
    return assignments.createTeacherCreatedAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher-1',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
      movement: movement,
      revision: revision,
    );
  }

  test(
    'upload failure before an object exists marks the draft abandoned',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'asg1',
      );
      addTearDown(assignments.dispose);
      final assignment = await teacherAssignment(assignments);
      final deleted = <String>{};
      final submissions = InMemoryAssignmentSubmissionRepository(
        classroom: assignments,
        now: () => DateTime.utc(2026, 8, 20),
        failNextUpload: true,
        deletedPaths: deleted,
      );
      await expectLater(
        submissions.submitLocalClip(
          traineeId: 'trainee-1',
          assignment: assignment,
          clip: const SubmissionRecordResult(
            localPath: r'C:\Temp\elixr_submissions\clip.mp4',
            durationMs: 3500,
            sizeBytes: 2048,
            contentType: 'video/mp4',
          ),
        ),
        throwsA(isA<AssignmentSubmissionException>()),
      );
      final leftover = assignments.attempts.values.singleWhere(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      );
      expect(leftover.status, AssignmentAttemptStatus.draft);
      expect(leftover.isAbandonedTeacherReviewDraft, isTrue);
      expect(leftover.isReviewFacingSubmission, isFalse);
      expect(leftover.videoStoragePath, isNull);
      expect(leftover.awardsGlobalXp, isFalse);
      expect(leftover.sourceSessionId, isNull);
      expect(deleted, hasLength(1));
      expect(
        deleted.single,
        assignmentSubmissionStoragePath(
          teacherId: leftover.teacherId,
          groupId: leftover.groupId,
          assignmentId: leftover.assignmentId,
          traineeId: leftover.traineeId,
          attemptId: leftover.id,
        ),
      );
      expect(leftover.videoDeletedAt, DateTime.utc(2026, 8, 20));
    },
  );

  test(
    'submit metadata failure deletes the object then marks the draft abandoned',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'asg1',
      );
      addTearDown(assignments.dispose);
      assignments.failNextSubmitTransition = true;
      final assignment = await teacherAssignment(assignments);
      final deleted = <String>{};
      final submissions = InMemoryAssignmentSubmissionRepository(
        classroom: assignments,
        now: () => DateTime.utc(2026, 8, 20),
        deletedPaths: deleted,
      );
      await expectLater(
        submissions.submitLocalClip(
          traineeId: 'trainee-1',
          assignment: assignment,
          clip: const SubmissionRecordResult(
            localPath: r'C:\Temp\elixr_submissions\clip.mp4',
            durationMs: 3500,
            sizeBytes: 2048,
            contentType: 'video/mp4',
          ),
        ),
        throwsA(isA<Exception>()),
      );
      expect(deleted, isNotEmpty);
      final leftover = assignments.attempts.values.singleWhere(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      );
      expect(leftover.isAbandonedTeacherReviewDraft, isTrue);
      expect(leftover.videoDeletedAt, isNotNull);
      expect(leftover.status, AssignmentAttemptStatus.draft);
    },
  );

  test(
    'object delete failure keeps the abandoned authorization anchor',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'asg1',
      );
      addTearDown(assignments.dispose);
      assignments.failNextSubmitTransition = true;
      final assignment = await teacherAssignment(assignments);
      final submissions = InMemoryAssignmentSubmissionRepository(
        classroom: assignments,
        now: () => DateTime.utc(2026, 8, 20),
        failNextDelete: true,
      );
      await expectLater(
        submissions.submitLocalClip(
          traineeId: 'trainee-1',
          assignment: assignment,
          clip: const SubmissionRecordResult(
            localPath: r'C:\Temp\elixr_submissions\clip.mp4',
            durationMs: 3500,
            sizeBytes: 2048,
            contentType: 'video/mp4',
          ),
        ),
        throwsA(isA<Exception>()),
      );
      final leftover = assignments.attempts.values.singleWhere(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      );
      expect(leftover.status, AssignmentAttemptStatus.draft);
      expect(leftover.isAbandonedTeacherReviewDraft, isTrue);
      expect(leftover.deletionFailed, isTrue);
      expect(leftover.isReviewFacingSubmission, isFalse);
    },
  );

  test('local playback is a file URI and never a download URL', () async {
    final cache = await Directory.systemTemp.createTemp('elixr_review_cache');
    addTearDown(() => cache.delete(recursive: true));
    var downloadedPath = '';
    final playback = await materializeAuthenticatedSubmissionClip(
      attempt: AssignmentAttempt(
        id: 'review_sub_play',
        traineeId: 'trainee-1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: 'asg1',
        movementId: 'tm1',
        revisionId: 'rev1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.submitted,
        videoStoragePath:
            'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_play.mp4',
        videoContentType: 'video/mp4',
        videoSizeBytes: 4,
        videoDurationMs: 1000,
        submittedAt: DateTime.utc(2026, 8, 20),
        videoExpiresAt: DateTime.utc(2026, 9, 19),
      ),
      cacheDirectory: cache,
      downloadBytes: (path, {required maxSize}) async {
        downloadedPath = path;
        expect(path.contains('http'), isFalse);
        expect(maxSize, AssignmentSubmissionLimits.maxPlaybackDownloadBytes);
        return Uint8List.fromList(const [0, 0, 0, 1]);
      },
    );
    expect(downloadedPath, startsWith('assignment_submissions/'));
    expect(playback.uri.isScheme('file'), isTrue);
    expect(playback.uri.toString().contains('token='), isFalse);
    expect(File(playback.localPath).existsSync(), isTrue);
    await releaseSubmissionPlaybackFile(playback);
    expect(File(playback.localPath).existsSync(), isFalse);
  });

  test('failed playback download deletes the partial cache file', () async {
    final cache = await Directory.systemTemp.createTemp('elixr_review_cache');
    addTearDown(() => cache.delete(recursive: true));
    await expectLater(
      materializeAuthenticatedSubmissionClip(
        attempt: AssignmentAttempt(
          id: 'review_sub_fail',
          traineeId: 'trainee-1',
          teacherId: 'teacher-1',
          groupId: 'g1',
          assignmentId: 'asg1',
          movementId: 'tm1',
          revisionId: 'rev1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.submitted,
          videoStoragePath:
              'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_fail.mp4',
          videoContentType: 'video/mp4',
          videoSizeBytes: 4,
          videoDurationMs: 1000,
          submittedAt: DateTime.utc(2026, 8, 20),
          videoExpiresAt: DateTime.utc(2026, 9, 19),
        ),
        cacheDirectory: cache,
        downloadBytes: (path, {required maxSize}) async {
          throw const AssignmentSubmissionException('download failed');
        },
      ),
      throwsA(isA<AssignmentSubmissionException>()),
    );
    expect(cache.listSync(), isEmpty);
  });

  test('firebase submission repository does not mint download URLs', () {
    final source = File(
      'lib/data/repositories/firebase_assignment_submission_repository.dart',
    ).readAsStringSync();
    expect(source.contains('getDownloadURL'), isFalse);
    expect(source.contains('getData'), isTrue);
  });

  test('object-not-found reconcile is not fatal', () async {
    final assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 9, 20),
    );
    addTearDown(assignments.dispose);
    const path =
        'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_old.mp4';
    assignments.seedAttempt(
      AssignmentAttempt(
        id: 'review_sub_old',
        traineeId: 'trainee-1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: 'asg1',
        movementId: 'tm1',
        revisionId: 'rev1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.approved,
        videoStoragePath: path,
        videoContentType: 'video/mp4',
        videoSizeBytes: 100,
        videoDurationMs: 1000,
        submittedAt: DateTime.utc(2026, 8, 1),
        reviewedAt: DateTime.utc(2026, 8, 2),
        reviewVerdict: AssignmentReviewVerdict.approved,
        videoExpiresAt: DateTime.utc(2026, 8, 16),
      ),
    );
    final submissions = InMemoryAssignmentSubmissionRepository(
      classroom: assignments,
      now: () => DateTime.utc(2026, 9, 20),
      missingPaths: {path},
    );
    await submissions.reconcileExpiredVideos(
      actorId: 'teacher-1',
      attempts: assignments.attempts.values.toList(),
    );
    final updated = assignments.attempts['review_sub_old']!;
    expect(updated.videoStoragePath, isNull);
    expect(updated.reviewVerdict, AssignmentReviewVerdict.approved);
    expect(updated.status, AssignmentAttemptStatus.approved);
    expect(updated.deletionFailed, isFalse);
  });

  test(
    'abandoned draft cleanup derives the canonical path without video_storage_path',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 21),
      );
      addTearDown(assignments.dispose);
      const path =
          'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_abandoned.mp4';
      assignments.seedAttempt(
        AssignmentAttempt(
          id: 'review_sub_abandoned',
          traineeId: 'trainee-1',
          teacherId: 'teacher-1',
          groupId: 'g1',
          assignmentId: 'asg1',
          movementId: 'tm1',
          revisionId: 'rev1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.draft,
          abandonedAt: DateTime.utc(2026, 8, 20),
          deletionFailed: true,
          deletionFailedAt: DateTime.utc(2026, 8, 20),
        ),
      );
      final deleted = <String>{};
      final submissions = InMemoryAssignmentSubmissionRepository(
        classroom: assignments,
        now: () => DateTime.utc(2026, 8, 21),
        deletedPaths: deleted,
      );
      await submissions.reconcileExpiredVideos(
        actorId: 'trainee-1',
        attempts: assignments.attempts.values.toList(),
      );
      expect(deleted, {path});
      final updated = assignments.attempts['review_sub_abandoned']!;
      expect(updated.isAbandonedTeacherReviewDraft, isTrue);
      expect(updated.videoDeletedAt, isNotNull);
      expect(updated.deletionFailed, isFalse);
      expect(updated.isReviewFacingSubmission, isFalse);
    },
  );

  test(
    'storage upload FirebaseException is rethrown after abandon compensation',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'asg1',
      );
      addTearDown(assignments.dispose);
      final assignment = await teacherAssignment(assignments);
      final logs = <String>[];
      final submissions = InMemoryAssignmentSubmissionRepository(
        classroom: assignments,
        now: () => DateTime.utc(2026, 8, 20),
        diagnosticLog: logs.add,
        uploadException: FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
          message:
              'Bearer ya29.secret token=abc https://example.com/o?token=1 '
              r'C:\Temp\elixr_submissions\clip.mp4 user@example.com',
        ),
      );

      await expectLater(
        submissions.submitLocalClip(
          traineeId: 'trainee-1',
          assignment: assignment,
          clip: const SubmissionRecordResult(
            localPath: r'C:\Temp\elixr_submissions\clip.mp4',
            durationMs: 3500,
            sizeBytes: 2048,
            contentType: 'video/mp4',
          ),
        ),
        throwsA(
          isA<ClassroomException>()
              .having((e) => e.code, 'code', ClassroomError.uploadFailed)
              .having(
                (e) => e.message,
                'message',
                'The submission clip could not be uploaded. Try again.',
              ),
        ),
      );

      expect(
        logs.singleWhere((line) => line.contains('stage=storage_upload')),
        contains('plugin=firebase_storage'),
      );
      expect(logs.join('\n'), isNot(contains('ya29')));
      expect(logs.join('\n'), isNot(contains(r'C:\Temp')));
      expect(logs.join('\n'), isNot(contains('user@example.com')));
      final leftover = assignments.attempts.values.singleWhere(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      );
      expect(leftover.status, AssignmentAttemptStatus.draft);
      expect(leftover.isAbandonedTeacherReviewDraft, isTrue);
      expect(leftover.deletionFailed, isFalse);
      expect(leftover.videoDeletedAt, DateTime.utc(2026, 8, 20));
      expect(leftover.awardsGlobalXp, isFalse);
      expect(leftover.sourceSessionId, isNull);
      expect(
        logs.singleWhere((line) => line.contains('[Phase6StorageAnchor]')),
        contains('attempt_exists=true'),
      );
      expect(
        logs.singleWhere((line) => line.contains('[Phase6StorageAnchor]')),
        contains('abandoned=false'),
      );
    },
  );

  test(
    'Firestore submit failure is distinguished from Storage upload failure',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'asg1',
      );
      addTearDown(assignments.dispose);
      assignments.failNextSubmitTransition = true;
      final assignment = await teacherAssignment(assignments);
      final logs = <String>[];
      final deleted = <String>{};
      final submissions = InMemoryAssignmentSubmissionRepository(
        classroom: assignments,
        now: () => DateTime.utc(2026, 8, 20),
        diagnosticLog: logs.add,
        deletedPaths: deleted,
      );

      await expectLater(
        submissions.submitLocalClip(
          traineeId: 'trainee-1',
          assignment: assignment,
          clip: const SubmissionRecordResult(
            localPath: r'C:\Temp\elixr_submissions\clip.mp4',
            durationMs: 3500,
            sizeBytes: 2048,
            contentType: 'video/mp4',
          ),
        ),
        throwsA(
          isA<ClassroomException>().having(
            (e) => e.message,
            'message',
            'Could not finalize the submission metadata.',
          ),
        ),
      );

      expect(
        logs.where((line) => line.contains('stage=storage_upload')),
        isEmpty,
      );
      expect(
        logs.singleWhere((line) => line.contains('stage=firestore_submit')),
        contains('classroom_code=uploadFailed'),
      );
      expect(deleted, isNotEmpty);
      final leftover = assignments.attempts.values.singleWhere(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      );
      expect(leftover.isAbandonedTeacherReviewDraft, isTrue);
      expect(leftover.videoDeletedAt, isNotNull);
      expect(leftover.awardsGlobalXp, isFalse);
    },
  );

  test('diagnostic formatter redacts tokens and local paths', () {
    final line = formatPhase6SubmissionDiagnostic(
      stage: Phase6SubmissionStage.storageUpload,
      error: FirebaseException(
        plugin: 'firebase_storage',
        code: 'unknown',
        message:
            'Authorization: Bearer ya29.secret token=abc '
            'https://firebasestorage.googleapis.com/v0/b/x/o?token=y '
            r'C:\Users\Jiro\clip.mp4 ada@example.com',
      ),
    );
    expect(line, contains('stage=storage_upload'));
    expect(line, contains('plugin=firebase_storage'));
    expect(line, contains('code=unknown'));
    expect(line, isNot(contains('ya29')));
    expect(line, isNot(contains('Bearer ya29')));
    expect(line, isNot(contains('token=y')));
    expect(line, isNot(contains(r'C:\Users')));
    expect(line, isNot(contains('ada@example.com')));
    expect(line, isNot(contains('https://firebasestorage')));
  });

  test(
    'runPhase6StorageUpload rethrows FirebaseException after logging',
    () async {
      final logs = <String>[];
      await expectLater(
        runPhase6StorageUpload(
          log: logs.add,
          upload: () async {
            throw FirebaseException(
              plugin: 'firebase_storage',
              code: 'canceled',
              message: 'upload canceled',
            );
          },
        ),
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'canceled'),
        ),
      );
      expect(logs.single, contains('stage=storage_upload'));
      expect(logs.single, contains('plugin=firebase_storage'));
      expect(logs.single, contains('code=canceled'));
    },
  );

  test('runPhase6StorageUpload logs success bytes', () async {
    final logs = <String>[];
    final bytes = await runPhase6StorageUpload(
      log: logs.add,
      upload: () async => 2048,
    );
    expect(bytes, 2048);
    expect(
      logs.single,
      '[Phase6Submission] stage=storage_upload result=success bytes=2048',
    );
  });

  const clip = SubmissionRecordResult(
    localPath: r'C:\Temp\elixr_submissions\clip.mp4',
    durationMs: 3500,
    sizeBytes: 2048,
    contentType: 'video/mp4',
  );

  test(
    'COMP-A upload Future throw deletes canonical object once then abandons',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'asg1',
      );
      addTearDown(assignments.dispose);
      final assignment = await teacherAssignment(assignments);
      final deleted = <String>[];
      await expectLater(
        submitLocalClipWithDraftCompensation(
          traineeId: 'trainee-1',
          assignment: assignment,
          clip: clip,
          classroom: assignments,
          now: DateTime.utc(2026, 8, 20),
          uploadObject: ({required draft, required storagePath}) async {
            throw const AssignmentSubmissionException('storage upload failed');
          },
          deleteObject: (path) async {
            deleted.add(path);
          },
          isObjectNotFound: (_) => false,
        ),
        throwsA(isA<AssignmentSubmissionException>()),
      );
      final leftover = assignments.attempts.values.singleWhere(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      );
      expect(deleted, hasLength(1));
      expect(
        deleted.single,
        assignmentSubmissionStoragePath(
          teacherId: leftover.teacherId,
          groupId: leftover.groupId,
          assignmentId: leftover.assignmentId,
          traineeId: leftover.traineeId,
          attemptId: leftover.id,
        ),
      );
      expect(leftover.status, AssignmentAttemptStatus.draft);
      expect(leftover.isAbandonedTeacherReviewDraft, isTrue);
      expect(leftover.videoDeletedAt, DateTime.utc(2026, 8, 20));
      expect(leftover.deletionFailed, isFalse);
      expect(leftover.videoStoragePath, isNull);
      expect(leftover.awardsGlobalXp, isFalse);
      expect(leftover.sourceSessionId, isNull);
    },
  );

  test(
    'COMP-B upload Future throw treats object-not-found delete as clean',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'asg1',
      );
      addTearDown(assignments.dispose);
      final assignment = await teacherAssignment(assignments);
      final deleted = <String>[];
      await expectLater(
        submitLocalClipWithDraftCompensation(
          traineeId: 'trainee-1',
          assignment: assignment,
          clip: clip,
          classroom: assignments,
          now: DateTime.utc(2026, 8, 20),
          uploadObject: ({required draft, required storagePath}) async {
            throw const AssignmentSubmissionException('storage upload failed');
          },
          deleteObject: (path) async {
            deleted.add(path);
            throw const AssignmentSubmissionException('object-not-found');
          },
          isObjectNotFound: (error) =>
              error is AssignmentSubmissionException &&
              error.message == 'object-not-found',
        ),
        throwsA(isA<AssignmentSubmissionException>()),
      );
      final leftover = assignments.attempts.values.singleWhere(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      );
      expect(deleted, hasLength(1));
      expect(leftover.status, AssignmentAttemptStatus.draft);
      expect(leftover.isAbandonedTeacherReviewDraft, isTrue);
      expect(leftover.videoDeletedAt, DateTime.utc(2026, 8, 20));
      expect(leftover.deletionFailed, isFalse);
      expect(leftover.videoStoragePath, isNull);
      expect(leftover.awardsGlobalXp, isFalse);
      expect(leftover.sourceSessionId, isNull);
    },
  );

  test(
    'COMP-C upload Future throw records deletion_failed when delete fails',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'asg1',
      );
      addTearDown(assignments.dispose);
      final assignment = await teacherAssignment(assignments);
      final deleted = <String>[];
      await expectLater(
        submitLocalClipWithDraftCompensation(
          traineeId: 'trainee-1',
          assignment: assignment,
          clip: clip,
          classroom: assignments,
          now: DateTime.utc(2026, 8, 20),
          uploadObject: ({required draft, required storagePath}) async {
            throw const AssignmentSubmissionException('storage upload failed');
          },
          deleteObject: (path) async {
            deleted.add(path);
            throw const AssignmentSubmissionException('permission-denied');
          },
          isObjectNotFound: (_) => false,
        ),
        throwsA(isA<AssignmentSubmissionException>()),
      );
      final leftover = assignments.attempts.values.singleWhere(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      );
      expect(deleted, hasLength(1));
      expect(leftover.status, AssignmentAttemptStatus.draft);
      expect(leftover.isAbandonedTeacherReviewDraft, isTrue);
      expect(leftover.deletionFailed, isTrue);
      expect(leftover.deletionFailedAt, DateTime.utc(2026, 8, 20));
      expect(leftover.videoDeletedAt, isNull);
      expect(leftover.videoStoragePath, isNull);
      expect(leftover.awardsGlobalXp, isFalse);
      expect(leftover.sourceSessionId, isNull);
    },
  );

  test(
    'COMP-D successful upload submits once and does not delete the new object',
    () async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'asg1',
      );
      addTearDown(assignments.dispose);
      final assignment = await teacherAssignment(assignments);
      final deleted = <String>[];
      var uploads = 0;
      final submitted = await submitLocalClipWithDraftCompensation(
        traineeId: 'trainee-1',
        assignment: assignment,
        clip: clip,
        classroom: assignments,
        now: DateTime.utc(2026, 8, 20),
        uploadObject: ({required draft, required storagePath}) async {
          uploads += 1;
        },
        deleteObject: (path) async {
          deleted.add(path);
        },
        isObjectNotFound: (_) => false,
      );
      expect(uploads, 1);
      expect(deleted, isEmpty);
      expect(submitted.status, AssignmentAttemptStatus.submitted);
      expect(submitted.awardsGlobalXp, isFalse);
      expect(submitted.sourceSessionId, isNull);
      expect(
        assignments.attempts.values.where(
          (attempt) =>
              attempt.attemptKind ==
              AssignmentAttemptKind.teacherReviewSubmission,
        ),
        hasLength(1),
      );
      expect(
        assignments.attempts.values.where(
          (attempt) => attempt.status == AssignmentAttemptStatus.submitted,
        ),
        hasLength(1),
      );
    },
  );
}
