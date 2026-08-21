import 'dart:io';
import 'dart:typed_data';

import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_submission_limits.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_core/models/elixr_group.dart';
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

  test('upload failure before an object exists deletes the draft', () async {
    final assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 8, 20),
      generateId: () => 'asg1',
    );
    addTearDown(assignments.dispose);
    final assignment = await teacherAssignment(assignments);
    final submissions = InMemoryAssignmentSubmissionRepository(
      classroom: assignments,
      now: () => DateTime.utc(2026, 8, 20),
      failNextUpload: true,
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
    expect(
      assignments.attempts.values.where(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      ),
      isEmpty,
    );
  });

  test('submit metadata failure deletes the object then the draft', () async {
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
    expect(
      assignments.attempts.values.where(
        (attempt) =>
            attempt.attemptKind ==
            AssignmentAttemptKind.teacherReviewSubmission,
      ),
      isEmpty,
    );
  });

  test(
    'object delete failure keeps the draft and does not report submitted',
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
}
