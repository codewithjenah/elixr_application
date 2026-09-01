import 'dart:async';
import 'dart:io';

import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/assignment_submission_repository.dart';
import 'package:elixr_application/features/practice/submission_recording_controller.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _assignment = GroupAssignment(
  id: 'asg1',
  teacherId: 'teacher-1',
  groupId: 'g1',
  movementId: 'tm1',
  revisionId: 'rev1',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Tin Balance',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'BSHM 4A',
  allowedProp: TrainingProp.bottle,
);

const _activityAssessment = TeacherActivityAssessmentConfig(
  readiness: TeacherActivityReadinessSpec(
    hands: ActivityHandRequirement.twoHands,
    body: ActivityBodyRequirement.upperBody,
  ),
  rubric: TeacherActivityRubric(
    template: TeacherActivityRubricTemplate.beginnerFundamentals,
    maximumScore: 30,
    criteria: [
      TeacherActivityRubricCriterion(
        id: 'setup',
        label: 'Setup',
        description: 'Start prepared.',
        maximumPoints: 10,
      ),
      TeacherActivityRubricCriterion(
        id: 'control',
        label: 'Control',
        description: 'Keep the bottle controlled.',
        maximumPoints: 10,
      ),
      TeacherActivityRubricCriterion(
        id: 'finish',
        label: 'Finish',
        description: 'Finish safely.',
        maximumPoints: 10,
      ),
    ],
  ),
  recordingDurationSeconds: 45,
);

const _activityAssignment = GroupAssignment(
  id: 'activity-1',
  teacherId: 'teacher-1',
  groupId: 'g1',
  movementId: 'tm1',
  revisionId: 'rev1',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Bottle Control Activity',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'BSHM 4A',
  allowedProp: TrainingProp.bottle,
  maxScore: 30,
  activityAssessment: _activityAssessment,
  attemptPolicy: AssignmentAttemptPolicy.finite(2),
);

class _GatedRecordSocket extends WebSocketService {
  int startCalls = 0;
  int stopCalls = 0;
  int? startDurationSeconds;
  Completer<CommandAck> startAck = Completer<CommandAck>();
  Completer<CommandAck> stopAck = Completer<CommandAck>();

  @override
  Future<CommandAck> sendStartSubmissionRecord({
    String? sessionId,
    int durationSeconds = 30,
  }) {
    startCalls += 1;
    startDurationSeconds = durationSeconds;
    return startAck.future;
  }

  @override
  Future<CommandAck> sendStopSubmissionRecord({String? sessionId}) {
    stopCalls += 1;
    return stopAck.future;
  }

  @override
  Future<CommandAck> sendCancelSubmissionRecord({String? sessionId}) async {
    return const CommandAck(
      protocolVersion: 1,
      requestId: 'cancel',
      action: 'cancel_submission_record',
      accepted: true,
    );
  }
}

class _StaleSnapshotClassroomRepository
    extends InMemoryClassroomAssignmentRepository {
  _StaleSnapshotClassroomRepository(this.staleAttempts);

  final List<AssignmentAttempt> staleAttempts;

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  }) {
    return Stream<List<AssignmentAttempt>>.value(staleAttempts);
  }
}

class _RecordingSubmissionRepository
    extends InMemoryAssignmentSubmissionRepository {
  _RecordingSubmissionRepository({
    required super.classroom,
    required this.submittedAttempt,
    this.submitError,
  });

  final AssignmentAttempt submittedAttempt;
  final Object? submitError;
  AssignmentAttempt? playbackAttempt;

  @override
  Future<AssignmentAttempt> saveCanonicalLocalClipDraft({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
  }) async {
    if (submitError != null) throw submitError!;
    return submittedAttempt;
  }

  @override
  Future<SubmissionPlaybackFile?> openLocalPlayback(
    AssignmentAttempt attempt,
  ) async {
    playbackAttempt = attempt;
    return null;
  }
}

CommandAck _acceptedStart() {
  return const CommandAck(
    protocolVersion: 1,
    requestId: 'start',
    action: 'start_submission_record',
    accepted: true,
    sessionId: 'sess-1',
  );
}

CommandAck _acceptedStop() {
  return const CommandAck(
    protocolVersion: 1,
    requestId: 'stop',
    action: 'stop_submission_record',
    accepted: true,
    sessionId: 'sess-1',
    localFilePath: r'C:\Temp\elixr_submissions\clip.mp4',
    videoDurationMs: 1500,
    videoSizeBytes: 2048,
    contentType: 'video/mp4',
  );
}

AssignmentAttempt _canonicalAttempt(AssignmentAttemptStatus status) {
  return AssignmentAttempt(
    id: assignmentAttemptIdForCanonicalTeacherReviewSubmission(
      assignmentId: _assignment.id,
      traineeId: 'trainee-1',
    ),
    traineeId: 'trainee-1',
    teacherId: _assignment.teacherId,
    groupId: _assignment.groupId,
    assignmentId: _assignment.id,
    movementId: _assignment.movementId,
    revisionId: _assignment.revisionId,
    origin: _assignment.origin,
    assessmentMode: _assignment.assessmentMode,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: status,
    createdAt: DateTime.utc(2026, 8, 30),
  );
}

AssignmentAttempt _submittedAttempt() {
  return _canonicalAttempt(AssignmentAttemptStatus.submitted).copyWith(
    videoStoragePath:
        'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_asg1_trainee-1.mp4',
    videoContentType: 'video/mp4',
    videoSizeBytes: 2048,
    videoDurationMs: 1500,
    submittedAt: DateTime.utc(2026, 8, 30),
    videoExpiresAt: DateTime.utc(2026, 9, 29),
  );
}

void main() {
  late InMemoryClassroomAssignmentRepository classroom;
  late InMemoryAssignmentSubmissionRepository submissions;

  setUp(() {
    classroom = InMemoryClassroomAssignmentRepository();
    submissions = InMemoryAssignmentSubmissionRepository(classroom: classroom);
  });

  tearDown(() {
    classroom.dispose();
  });

  SubmissionRecordingController controllerFor(_GatedRecordSocket socket) {
    final controller = SubmissionRecordingController(
      websocket: socket,
      classroom: classroom,
      submissions: submissions,
      assignment: _assignment,
      traineeId: 'trainee-1',
      recordingCountdown: Duration.zero,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('two Start taps issue one start_submission_record', () async {
    final socket = _GatedRecordSocket();
    final controller = controllerFor(socket);
    controller.requestConsent();
    final first = controller.beginRecording();
    final second = controller.beginRecording();
    expect(controller.recordCommandInFlight, isTrue);
    socket.startAck.complete(_acceptedStart());
    await Future.wait([first, second]);
    expect(socket.startCalls, 1);
    expect(controller.phase, SubmissionRecordingPhase.recording);
  });

  test('Activity recording sends its configured duration', () async {
    final socket = _GatedRecordSocket();
    final controller = SubmissionRecordingController(
      websocket: socket,
      classroom: classroom,
      submissions: submissions,
      assignment: _activityAssignment,
      traineeId: 'trainee-1',
      recordingCountdown: Duration.zero,
    );
    addTearDown(controller.dispose);

    final reserved = await classroom.reserveTeacherActivityAttempt(
      traineeId: 'trainee-1',
      assignment: _activityAssignment,
      requestId: 'activity-test-reservation',
    );
    await controller.refreshLatestSubmission();

    final starting = controller.beginRecording();
    socket.startAck.complete(_acceptedStart());
    await starting;

    expect(controller.isTeacherActivity, isTrue);
    expect(controller.recordingDurationSeconds, 45);
    expect(socket.startDurationSeconds, 45);
    expect(controller.errorMessage, isNull);
    expect(classroom.consumedTeacherActivityAttemptIds, contains(reserved.id));
  });

  test(
    'Activity recording submits the reserved attempt automatically',
    () async {
      final socket = _GatedRecordSocket();
      final controller = SubmissionRecordingController(
        websocket: socket,
        classroom: classroom,
        submissions: submissions,
        assignment: _activityAssignment,
        traineeId: 'trainee-1',
        recordingCountdown: Duration.zero,
      );
      addTearDown(controller.dispose);
      classroom.assignments[_activityAssignment.id] = _activityAssignment;
      final reserved = await classroom.reserveTeacherActivityAttempt(
        traineeId: 'trainee-1',
        assignment: _activityAssignment,
        requestId: 'activity-submit-reservation',
      );
      await controller.refreshLatestSubmission();

      final starting = controller.beginRecording();
      socket.startAck.complete(_acceptedStart());
      await starting;
      final stopping = controller.stopRecording();
      socket.stopAck.complete(_acceptedStop());
      await stopping;

      expect(controller.phase, SubmissionRecordingPhase.submitted);
      expect(controller.latestSubmission?.id, reserved.id);
      expect(controller.latestSubmission?.isReviewFacingSubmission, isTrue);
    },
  );

  test('two Stop taps issue one stop_submission_record', () async {
    final socket = _GatedRecordSocket();
    final controller = controllerFor(socket);
    controller.requestConsent();
    final starting = controller.beginRecording();
    socket.startAck.complete(_acceptedStart());
    await starting;
    final first = controller.stopRecording();
    final second = controller.stopRecording();
    socket.stopAck.complete(_acceptedStop());
    await Future.wait([first, second]);
    expect(socket.stopCalls, 1);
    expect(controller.phase, SubmissionRecordingPhase.preview);
  });

  test('automatic stop racing manual stop keeps one clip', () async {
    final socket = _GatedRecordSocket();
    final controller = controllerFor(socket);
    controller.requestConsent();
    final starting = controller.beginRecording();
    socket.startAck.complete(_acceptedStart());
    await starting;
    final automatic = controller.stopRecording();
    final manual = controller.stopRecording();
    socket.stopAck.complete(_acceptedStop());
    await Future.wait([automatic, manual]);
    expect(socket.stopCalls, 1);
    expect(controller.phase, SubmissionRecordingPhase.preview);
    expect(controller.clip, isNotNull);
    expect(controller.errorMessage, isNull);
  });

  test('retake cannot race stop finalization', () async {
    final socket = _GatedRecordSocket();
    final controller = controllerFor(socket);
    controller.requestConsent();
    final starting = controller.beginRecording();
    socket.startAck.complete(_acceptedStart());
    await starting;
    final stopping = controller.stopRecording();
    await controller.retake();
    expect(controller.phase, SubmissionRecordingPhase.recording);
    socket.stopAck.complete(_acceptedStop());
    await stopping;
    expect(controller.phase, SubmissionRecordingPhase.preview);
    expect(socket.stopCalls, 1);
  });

  test('retake waits for playback release before deleting the clip', () async {
    final dir = await Directory.systemTemp.createTemp('elixr_clip');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/clip.mp4');
    await file.writeAsBytes(const [1, 2, 3, 4]);
    var released = false;
    await deleteLocalClipAfterPlaybackRelease(
      path: file.path,
      releasePlayback: () async {
        expect(file.existsSync(), isTrue);
        released = true;
      },
    );
    expect(released, isTrue);
    expect(file.existsSync(), isFalse);
  });

  test('retake retries delete after residual Windows file lock', () async {
    var deletes = 0;
    final delays = <Duration>[];
    await deleteLocalClipAfterPlaybackRelease(
      path: r'C:\Temp\elixr_submissions\clip.mp4',
      releasePlayback: () async {},
      delay: (duration) async {
        delays.add(duration);
      },
      deleteFile: (path) async {
        deletes += 1;
        if (deletes < 3) {
          throw FileSystemException(
            'The process cannot access the file',
            r'C:\Temp\elixr_submissions\clip.mp4',
            const OSError('Sharing violation', 32),
          );
        }
      },
    );
    expect(deletes, 3);
    expect(delays, isNotEmpty);
  });

  test(
    'submission uses the confirmed attempt when the next snapshot is stale',
    () async {
      final stale = _canonicalAttempt(AssignmentAttemptStatus.inProgress);
      final classroom = _StaleSnapshotClassroomRepository([stale]);
      addTearDown(classroom.dispose);
      final submitted = _submittedAttempt();
      final submissions = _RecordingSubmissionRepository(
        classroom: classroom,
        submittedAttempt: submitted,
      );
      final controller = SubmissionRecordingController(
        websocket: _GatedRecordSocket(),
        classroom: classroom,
        submissions: submissions,
        assignment: _assignment,
        traineeId: 'trainee-1',
      );
      addTearDown(controller.dispose);
      controller.clip = SubmissionRecordResult.fromAck(_acceptedStop());
      controller.phase = SubmissionRecordingPhase.preview;

      await controller.refreshLatestSubmission();
      expect(controller.latestSubmission, same(stale));

      await controller.saveDraft();

      expect(controller.latestSubmission, same(submitted));
      expect(controller.latestSubmission!.hasPlayableVideo, isTrue);
      expect(controller.phase, SubmissionRecordingPhase.attached);
      expect(submissions.playbackAttempt, same(submitted));
    },
  );

  test(
    'submission failure enters failed state without playable metadata',
    () async {
      final stale = _canonicalAttempt(AssignmentAttemptStatus.inProgress);
      final classroom = _StaleSnapshotClassroomRepository([stale]);
      addTearDown(classroom.dispose);
      final submissions = _RecordingSubmissionRepository(
        classroom: classroom,
        submittedAttempt: _submittedAttempt(),
        submitError: StateError('upload failed'),
      );
      final controller = SubmissionRecordingController(
        websocket: _GatedRecordSocket(),
        classroom: classroom,
        submissions: submissions,
        assignment: _assignment,
        traineeId: 'trainee-1',
      );
      addTearDown(controller.dispose);
      controller.clip = SubmissionRecordResult.fromAck(_acceptedStop());
      controller.phase = SubmissionRecordingPhase.preview;

      await controller.saveDraft();

      expect(controller.phase, SubmissionRecordingPhase.failed);
      expect(controller.latestSubmission, same(stale));
      expect(controller.latestSubmission!.hasPlayableVideo, isFalse);
      expect(submissions.playbackAttempt, isNull);
    },
  );

  test('refresh loads a persisted submitted attempt when reopening', () async {
    final submitted = _submittedAttempt();
    final classroom = _StaleSnapshotClassroomRepository([submitted]);
    addTearDown(classroom.dispose);
    final submissions = InMemoryAssignmentSubmissionRepository(
      classroom: classroom,
    );
    final controller = SubmissionRecordingController(
      websocket: _GatedRecordSocket(),
      classroom: classroom,
      submissions: submissions,
      assignment: _assignment,
      traineeId: 'trainee-1',
    );
    addTearDown(controller.dispose);

    await controller.refreshLatestSubmission();

    expect(controller.latestSubmission, same(submitted));
    expect(controller.latestSubmission!.hasPlayableVideo, isTrue);
    expect(controller.phase, SubmissionRecordingPhase.submitted);
  });

  test(
    'refresh accepts a newer unsubmitting state for the same attempt',
    () async {
      final submitted = _submittedAttempt();
      final unsubmitting = submitted.copyWith(
        status: AssignmentAttemptStatus.unsubmitting,
      );
      final classroom = _StaleSnapshotClassroomRepository([unsubmitting]);
      addTearDown(classroom.dispose);
      final controller = SubmissionRecordingController(
        websocket: _GatedRecordSocket(),
        classroom: classroom,
        submissions: InMemoryAssignmentSubmissionRepository(
          classroom: classroom,
        ),
        assignment: _assignment,
        traineeId: 'trainee-1',
      );
      addTearDown(controller.dispose);
      controller.latestSubmission = submitted;

      await controller.refreshLatestSubmission();

      expect(controller.latestSubmission, same(unsubmitting));
    },
  );

  test(
    'refresh does not replace a confirmed submission with stale in progress',
    () async {
      final submitted = _submittedAttempt();
      final stale = _canonicalAttempt(AssignmentAttemptStatus.inProgress);
      final classroom = _StaleSnapshotClassroomRepository([stale]);
      addTearDown(classroom.dispose);
      final controller = SubmissionRecordingController(
        websocket: _GatedRecordSocket(),
        classroom: classroom,
        submissions: InMemoryAssignmentSubmissionRepository(
          classroom: classroom,
        ),
        assignment: _assignment,
        traineeId: 'trainee-1',
      );
      addTearDown(controller.dispose);
      controller.latestSubmission = submitted;

      await controller.refreshLatestSubmission();

      expect(controller.latestSubmission, same(submitted));
    },
  );
}
