import 'dart:async';
import 'dart:io';

import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
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

class _GatedRecordSocket extends WebSocketService {
  int startCalls = 0;
  int stopCalls = 0;
  Completer<CommandAck> startAck = Completer<CommandAck>();
  Completer<CommandAck> stopAck = Completer<CommandAck>();

  @override
  Future<CommandAck> sendStartSubmissionRecord({String? sessionId}) {
    startCalls += 1;
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
}
