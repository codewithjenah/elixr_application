import 'dart:typed_data';

import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_submission_limits.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/debug/assignment_put_data_probe.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

const _target = AssignmentPutDataProbeTarget(
  teacherId: 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1',
  groupId: 'i0CaSM4nEA9sNuKSRagO',
  assignmentId: 'ENvAezoRemcyihux3wpP',
  traineeId: 'OeflNaVfBkZ93BLOsGhRyOv6WAD3',
  movementId: 'CYdQM78YMPbLTCTblERB',
  revisionId: 'DNLnQUFnxmwUP0y5uIM9',
);

GroupAssignment _assignment() => const GroupAssignment(
  id: 'ENvAezoRemcyihux3wpP',
  teacherId: 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1',
  groupId: 'i0CaSM4nEA9sNuKSRagO',
  movementId: 'CYdQM78YMPbLTCTblERB',
  revisionId: 'DNLnQUFnxmwUP0y5uIM9',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Diagnostic assignment',
  teacherDisplayName: 'Teacher',
  groupName: 'Group',
);

class _SpyClassroom extends InMemoryClassroomAssignmentRepository {
  _SpyClassroom({super.now});

  int submittedCalls = 0;
  int sessionCalls = 0;
  int xpCalls = 0;
  int profileCalls = 0;
  bool corruptNextRead = false;

  @override
  Future<AssignmentAttempt> markTeacherReviewSubmitted({
    required String traineeId,
    required AssignmentAttempt attempt,
    required String videoStoragePath,
    required String videoContentType,
    required int videoSizeBytes,
    required int videoDurationMs,
    required DateTime submittedAt,
    required DateTime videoExpiresAt,
  }) async {
    submittedCalls += 1;
    return super.markTeacherReviewSubmitted(
      traineeId: traineeId,
      attempt: attempt,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
    );
  }

  @override
  Future<AssignmentAttempt?> getAttempt({required String attemptId}) async {
    final attempt = await super.getAttempt(attemptId: attemptId);
    if (!corruptNextRead || attempt == null) return attempt;
    return attempt.copyWith(status: AssignmentAttemptStatus.submitted);
  }
}

void main() {
  late _SpyClassroom classroom;

  setUp(() {
    classroom = _SpyClassroom(now: () => DateTime.utc(2026, 8, 21, 8));
    classroom.assignments[_assignment().id] = _assignment();
  });

  tearDown(() {
    classroom.dispose();
  });

  test('release mode cannot invoke the production probe path', () async {
    var putDataCalls = 0;
    var deleteCalls = 0;
    final logs = <String>[];

    final result = await runAssignmentPutDataProbe(
      debugMode: false,
      uid: _target.traineeId,
      bucket: 'elixr-app-2026.firebasestorage.app',
      target: _target,
      payload: assignmentPutDataProbeBytes,
      classroom: classroom,
      now: DateTime.utc(2026, 8, 21, 8),
      log: logs.add,
      putData:
          ({
            required bytes,
            required storagePath,
            required contentType,
            required customMetadata,
          }) async {
            putDataCalls += 1;
          },
      deleteRemote: (_) async {
        deleteCalls += 1;
      },
    );

    expect(result.invoked, isFalse);
    expect(putDataCalls, 0);
    expect(deleteCalls, 0);
    expect(logs, isEmpty);
    expect(classroom.attempts, isEmpty);
    expect(classroom.submittedCalls, 0);
  });

  test(
    'live dart-define seam is a no-op when debug or define is off',
    () async {
      var liveRuns = 0;
      expect(
        await maybeRunLiveAssignmentPutDataProbe(
          debugMode: false,
          dartDefineEnabled: true,
          runLive: () async {
            liveRuns += 1;
            throw StateError('must not run');
          },
        ),
        isNull,
      );
      expect(
        await maybeRunLiveAssignmentPutDataProbe(
          debugMode: true,
          dartDefineEnabled: false,
          runLive: () async {
            liveRuns += 1;
            throw StateError('must not run');
          },
        ),
        isNull,
      );
      expect(liveRuns, 0);
    },
  );

  test('null current user fails closed without upload or draft', () async {
    var putDataCalls = 0;
    final result = await runAssignmentPutDataProbe(
      debugMode: true,
      uid: null,
      bucket: 'elixr-app-2026.firebasestorage.app',
      target: _target,
      payload: assignmentPutDataProbeBytes,
      classroom: classroom,
      now: DateTime.utc(2026, 8, 21, 8),
      log: (_) {},
      putData:
          ({
            required bytes,
            required storagePath,
            required contentType,
            required customMetadata,
          }) async {
            putDataCalls += 1;
          },
      deleteRemote: (_) async {},
    );

    expect(result.invoked, isFalse);
    expect(result.errorType, 'Unauthenticated');
    expect(putDataCalls, 0);
    expect(classroom.attempts, isEmpty);
    expect(classroom.submittedCalls, 0);
  });

  test(
    'wrong authenticated UID fails before upload and draft creation',
    () async {
      var putDataCalls = 0;
      final result = await runAssignmentPutDataProbe(
        debugMode: true,
        uid: 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1',
        bucket: 'elixr-app-2026.firebasestorage.app',
        target: _target,
        payload: assignmentPutDataProbeBytes,
        classroom: classroom,
        now: DateTime.utc(2026, 8, 21, 8),
        log: (_) {},
        putData:
            ({
              required bytes,
              required storagePath,
              required contentType,
              required customMetadata,
            }) async {
              putDataCalls += 1;
            },
        deleteRemote: (_) async {},
      );

      expect(result.invoked, isFalse);
      expect(result.errorType, 'TraineeMismatch');
      expect(putDataCalls, 0);
      expect(classroom.attempts, isEmpty);
      expect(classroom.submittedCalls, 0);
    },
  );

  test('invalid durable anchor fails before upload and is abandoned', () async {
    classroom.corruptNextRead = true;
    var putDataCalls = 0;
    var deleteCalls = 0;

    final result = await runAssignmentPutDataProbe(
      debugMode: true,
      uid: _target.traineeId,
      bucket: 'elixr-app-2026.firebasestorage.app',
      target: _target,
      payload: assignmentPutDataProbeBytes,
      classroom: classroom,
      now: DateTime.utc(2026, 8, 21, 8),
      log: (_) {},
      putData:
          ({
            required bytes,
            required storagePath,
            required contentType,
            required customMetadata,
          }) async {
            putDataCalls += 1;
          },
      deleteRemote: (_) async {
        deleteCalls += 1;
      },
    );

    expect(result.errorType, 'InvalidAnchor');
    expect(result.anchorValidBeforeUpload, isFalse);
    expect(putDataCalls, 0);
    expect(deleteCalls, 0);
    expect(
      result.remoteCleanup,
      AssignmentPutDataProbeRemoteCleanup.notCreated,
    );
    expect(result.anchorCleanup, AssignmentPutDataProbeAnchorCleanup.abandoned);
    expect(classroom.attempts.values.single.abandonedAt, isNotNull);
    expect(classroom.submittedCalls, 0);
  });

  test(
    'successful upload uses canonical path, seven metadata keys, putData once, then cleanup',
    () async {
      final events = <String>[];
      Map<String, String>? capturedMetadata;
      String? capturedPath;
      String? capturedContentType;
      Uint8List? capturedBytes;

      final result = await runAssignmentPutDataProbe(
        debugMode: true,
        uid: _target.traineeId,
        bucket: 'elixr-app-2026.firebasestorage.app',
        target: _target,
        payload: assignmentPutDataProbeBytes,
        classroom: classroom,
        now: DateTime.utc(2026, 8, 21, 8),
        log: events.add,
        putData:
            ({
              required bytes,
              required storagePath,
              required contentType,
              required customMetadata,
            }) async {
              capturedBytes = bytes;
              capturedPath = storagePath;
              capturedContentType = contentType;
              capturedMetadata = Map<String, String>.from(customMetadata);
              events.add('putData:$storagePath');
            },
        deleteRemote: (storagePath) async {
          events.add('deleteRemote:$storagePath');
        },
      );

      final attempt = classroom.attempts.values.single;
      final expectedPath = assignmentSubmissionStoragePath(
        teacherId: _target.teacherId,
        groupId: _target.groupId,
        assignmentId: _target.assignmentId,
        traineeId: _target.traineeId,
        attemptId: attempt.id,
      );
      final expectedMetadata = assignmentSubmissionCustomMetadata(
        teacherId: _target.teacherId,
        groupId: _target.groupId,
        assignmentId: _target.assignmentId,
        traineeId: _target.traineeId,
        attemptId: attempt.id,
        movementId: _target.movementId,
        revisionId: _target.revisionId,
      );

      expect(result.invoked, isTrue);
      expect(result.uploadSucceeded, isTrue);
      expect(result.anchorValidBeforeUpload, isTrue);
      expect(result.pathCorrect, isTrue);
      expect(result.metadataCorrect, isTrue);
      expect(capturedPath, expectedPath);
      expect(capturedContentType, AssignmentSubmissionLimits.contentType);
      expect(capturedContentType, 'video/mp4');
      expect(capturedMetadata, expectedMetadata);
      expect(capturedMetadata!.keys.toSet(), {
        'teacher_id',
        'group_id',
        'assignment_id',
        'trainee_id',
        'attempt_id',
        'movement_id',
        'revision_id',
      });
      expect(capturedBytes, assignmentPutDataProbeBytes);
      expect(events.where((line) => line.startsWith('putData:')), hasLength(1));
      expect(
        events.where((line) => line.startsWith('deleteRemote:')),
        hasLength(1),
      );
      expect(
        events.indexWhere((line) => line.startsWith('putData:')),
        lessThan(events.indexWhere((line) => line.startsWith('deleteRemote:'))),
      );
      expect(result.remoteCleanup, AssignmentPutDataProbeRemoteCleanup.success);
      expect(
        result.anchorCleanup,
        AssignmentPutDataProbeAnchorCleanup.abandoned,
      );
      expect(attempt.status, AssignmentAttemptStatus.draft);
      expect(attempt.abandonedAt, isNotNull);
      expect(attempt.submittedAt, isNull);
      expect(attempt.videoStoragePath, isNull);
      expect(attempt.sourceSessionId, isNull);
      expect(classroom.submittedCalls, 0);
      expect(classroom.sessionCalls, 0);
      expect(classroom.xpCalls, 0);
      expect(classroom.profileCalls, 0);
      expect(
        events,
        contains('[AssignmentPutDataProbe] result=success bytes=128'),
      );
      expect(
        events,
        contains('[AssignmentPutDataProbe] remote_cleanup=success'),
      );
      expect(
        events,
        contains('[AssignmentPutDataProbe] anchor_cleanup=abandoned'),
      );
    },
  );

  test(
    'failed upload does not attempt remote cleanup and abandons draft',
    () async {
      var deleteCalls = 0;
      final logs = <String>[];

      final result = await runAssignmentPutDataProbe(
        debugMode: true,
        uid: _target.traineeId,
        bucket: 'elixr-app-2026.firebasestorage.app',
        target: _target,
        payload: assignmentPutDataProbeBytes,
        classroom: classroom,
        now: DateTime.utc(2026, 8, 21, 8),
        log: logs.add,
        putData:
            ({
              required bytes,
              required storagePath,
              required contentType,
              required customMetadata,
            }) async {
              throw FirebaseException(
                plugin: 'firebase_storage',
                code: 'unauthorized',
                message:
                    'User does not have permission. id_token=abc.secret '
                    'trainee@example.com https://firebasestorage.googleapis.com/v0/b/x',
              );
            },
        deleteRemote: (_) async {
          deleteCalls += 1;
        },
      );

      expect(result.uploadSucceeded, isFalse);
      expect(result.plugin, 'firebase_storage');
      expect(result.code, 'unauthorized');
      expect(deleteCalls, 0);
      expect(
        result.remoteCleanup,
        AssignmentPutDataProbeRemoteCleanup.notCreated,
      );
      expect(
        result.anchorCleanup,
        AssignmentPutDataProbeAnchorCleanup.abandoned,
      );
      expect(classroom.attempts.values.single.abandonedAt, isNotNull);
      expect(classroom.submittedCalls, 0);
      final joined = logs.join('\n');
      expect(joined, contains('result=failure'));
      expect(joined, contains('error_type=FirebaseException'));
      expect(joined, contains('plugin=firebase_storage'));
      expect(joined, contains('code=unauthorized'));
      expect(joined, contains('remote_cleanup=not_created'));
      expect(joined, isNot(contains('abc.secret')));
      expect(joined, isNot(contains('trainee@example.com')));
      expect(joined, isNot(contains('https://firebasestorage')));
    },
  );

  test(
    'remote-cleanup failure still attempts safe anchor abandonment',
    () async {
      final logs = <String>[];
      final result = await runAssignmentPutDataProbe(
        debugMode: true,
        uid: _target.traineeId,
        bucket: 'elixr-app-2026.firebasestorage.app',
        target: _target,
        payload: assignmentPutDataProbeBytes,
        classroom: classroom,
        now: DateTime.utc(2026, 8, 21, 8),
        log: logs.add,
        putData:
            ({
              required bytes,
              required storagePath,
              required contentType,
              required customMetadata,
            }) async {},
        deleteRemote: (_) async {
          throw FirebaseException(
            plugin: 'firebase_storage',
            code: 'unknown',
            message: 'delete failed',
          );
        },
      );

      expect(result.uploadSucceeded, isTrue);
      expect(result.remoteCleanup, AssignmentPutDataProbeRemoteCleanup.failure);
      expect(
        result.anchorCleanup,
        AssignmentPutDataProbeAnchorCleanup.abandoned,
      );
      final attempt = classroom.attempts.values.single;
      expect(attempt.abandonedAt, isNotNull);
      expect(attempt.deletionFailed, isTrue);
      expect(attempt.status, AssignmentAttemptStatus.draft);
      expect(classroom.submittedCalls, 0);
      expect(logs, contains('[AssignmentPutDataProbe] remote_cleanup=failure'));
      expect(
        logs,
        contains('[AssignmentPutDataProbe] anchor_cleanup=abandoned'),
      );
    },
  );

  test('probe payload is a tiny non-empty diagnostic blob', () {
    expect(assignmentPutDataProbeBytes.length, inInclusiveRange(64, 256));
    expect(assignmentPutDataProbeBytes, isNotEmpty);
  });
}
