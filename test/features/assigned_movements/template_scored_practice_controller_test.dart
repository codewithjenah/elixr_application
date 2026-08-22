import 'dart:async';

import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/assigned_movements/template_scored_practice_controller.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingTemplateWebSocket extends WebSocketService {
  _RecordingTemplateWebSocket() : super();

  final prepareCalls = <Map<String, Object?>>[];
  int startCalls = 0;
  WebSocketConnectionState _state = WebSocketConnectionState.connected;
  Completer<CommandAck> prepareAck = Completer<CommandAck>();
  final _feedback = StreamController<PracticeFeedback>.broadcast();

  @override
  Stream<PracticeFeedback> get feedbackStream => _feedback.stream;

  @override
  WebSocketConnectionState get connectionState => _state;

  @override
  bool get isConnected => _state == WebSocketConnectionState.connected;

  @override
  Future<void> connect() async {
    _state = WebSocketConnectionState.connected;
    notifyListeners();
  }

  void emitFeedback(PracticeFeedback feedback) => _feedback.add(feedback);

  void simulateDisconnect() {
    _state = WebSocketConnectionState.disconnected;
    notifyListeners();
  }

  CommandAck _ack(String action, {bool accepted = true}) {
    return CommandAck(
      protocolVersion: 1,
      requestId: 'req-$action',
      action: action,
      accepted: accepted,
      sessionId: currentSessionId,
      sessionState: accepted ? action : 'idle',
    );
  }

  @override
  Future<CommandAck> sendPrepare({
    required String movement,
    required String difficulty,
    TrainingProp prop = TrainingProp.bottle,
    String? cameraDeviceId,
    int? legacyCameraIndex,
    String? sessionId,
    bool allowSubmissionRecording = false,
    WebSocketSessionPurpose sessionPurpose = WebSocketSessionPurpose.official,
    AssessmentSpec? assessmentSpec,
  }) {
    prepareCalls.add({
      'movement': movement,
      'session_purpose': sessionPurpose.wireValue,
      'assessment_spec': assessmentSpec?.toMap(),
      'allow_submission_recording': allowSubmissionRecording,
    });
    return prepareAck.future;
  }

  @override
  Future<CommandAck> sendStart({
    required String movement,
    required String difficulty,
    TrainingProp prop = TrainingProp.bottle,
    String? cameraDeviceId,
    int? legacyCameraIndex,
    String? sessionId,
  }) {
    startCalls += 1;
    return Future.value(_ack('start', accepted: false));
  }

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) {
    return Future.value(_ack('stop'));
  }

  void acceptPrepare() {
    if (!prepareAck.isCompleted) {
      prepareAck.complete(_ack('prepare'));
    }
  }

  @override
  void dispose() {
    _feedback.close();
    super.dispose();
  }
}

class _TrackingAssignments extends InMemoryClassroomAssignmentRepository {
  int createScoreCalls = 0;
  bool failNextWrite = false;

  @override
  Future<AssignmentAttempt> createTemplateScoreAttempt({
    required String traineeId,
    required GroupAssignment assignment,
    required RubricAssessment rubric,
    required int durationSeconds,
    required DateTime completedAt,
  }) async {
    createScoreCalls += 1;
    if (failNextWrite) {
      failNextWrite = false;
      throw const ClassroomException(
        ClassroomError.uploadFailed,
        'Could not save the classroom result.',
      );
    }
    return super.createTemplateScoreAttempt(
      traineeId: traineeId,
      assignment: assignment,
      rubric: rubric,
      durationSeconds: durationSeconds,
      completedAt: completedAt,
    );
  }
}

GroupAssignment _assignment() {
  return const GroupAssignment(
    id: 'asg1',
    teacherId: 'teacher-1',
    groupId: 'g1',
    movementId: 'tm1',
    revisionId: 'rev1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.templateScored,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Classroom Wrist Stall',
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSHM 4A',
    allowedProp: TrainingProp.bottle,
    assessmentSpec: AssessmentSpec(laterality: AssessmentLaterality.left),
  );
}

PracticeFeedback _activeFeedback({
  bool holdConfirmed = false,
  RubricAssessment? assessment,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: kTemplateAssessmentMovement,
    feedback: holdConfirmed ? 'Done' : 'Hold',
    feedbackType: holdConfirmed ? 'positive' : 'warning',
    postureStatus: holdConfirmed ? 'stable' : 'unstable',
    sessionState: 'active',
    holdConfirmed: holdConfirmed,
    holdDurationMs: 3500,
    assessment:
        assessment ??
        const RubricAssessment(
          technique: 3,
          stability: 2,
          completion: 3,
          propPositioning: 2,
        ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingTemplateWebSocket ws;
  late _TrackingAssignments assignments;
  late TemplateScoredPracticeController controller;

  setUp(() {
    ws = _RecordingTemplateWebSocket();
    assignments = _TrackingAssignments();
    controller = TemplateScoredPracticeController(
      assignment: _assignment(),
      traineeId: 'trainee-1',
      assignmentRepository: assignments,
      websocket: ws,
    );
  });

  tearDown(() {
    controller.dispose();
    assignments.dispose();
    ws.dispose();
  });

  test(
    'prepare uses frozen assignment spec and template_scored purpose',
    () async {
      final started = controller.startSession();
      await Future<void>.delayed(Duration.zero);
      expect(ws.prepareCalls, hasLength(1));
      ws.acceptPrepare();
      await started;
      expect(ws.prepareCalls.single['session_purpose'], 'template_scored');
      expect(ws.prepareCalls.single['allow_submission_recording'], isFalse);
      expect(ws.prepareCalls.single['movement'], kTemplateAssessmentMovement);
      expect(ws.prepareCalls.single['assessment_spec'], {
        'schema_version': 1,
        'template_id': 'balance_stall.wrist_v1',
        'prop': 'bottle',
        'target': 'wrist',
        'laterality': 'left',
      });
      expect(ws.startCalls, 0);
    },
  );

  test('confirmed backend result writes exactly one template_score', () async {
    controller.debugForceActive();
    controller.debugApplyFeedback(_activeFeedback(holdConfirmed: true));
    await Future<void>.delayed(Duration.zero);
    expect(assignments.createScoreCalls, 1);
    expect(controller.resultSaved, isTrue);
    expect(assignments.attempts.values.single.awardsGlobalXp, isFalse);
  });

  test('duplicate confirmed frames still write once', () async {
    controller.debugForceActive();
    controller.debugApplyFeedback(_activeFeedback(holdConfirmed: true));
    controller.debugApplyFeedback(_activeFeedback(holdConfirmed: true));
    await Future<void>.delayed(Duration.zero);
    expect(assignments.createScoreCalls, 1);
  });

  test('unconfirmed hold writes nothing', () async {
    controller.debugForceActive();
    controller.debugApplyFeedback(_activeFeedback());
    await Future<void>.delayed(Duration.zero);
    expect(assignments.createScoreCalls, 0);
    expect(controller.resultSaved, isFalse);
  });

  test('disconnect before confirmation writes nothing', () async {
    controller.debugForceActive();
    expect(controller.phase, PracticeRunPhase.active);
    ws.simulateDisconnect();
    await Future<void>.delayed(Duration.zero);
    expect(assignments.createScoreCalls, 0);
  });

  test('Firestore write failure is not shown as saved', () async {
    assignments.failNextWrite = true;
    controller.debugForceActive();
    controller.debugApplyFeedback(_activeFeedback(holdConfirmed: true));
    await Future<void>.delayed(Duration.zero);
    expect(controller.resultSaved, isFalse);
    expect(controller.saveErrorMessage, isNotNull);
    expect(assignments.createScoreCalls, 1);
  });

  test('retry after a new session can write a second attempt', () async {
    controller.debugForceActive();
    controller.debugApplyFeedback(_activeFeedback(holdConfirmed: true));
    await Future<void>.delayed(Duration.zero);
    expect(assignments.createScoreCalls, 1);
    final again = controller.tryAgain();
    await Future<void>.delayed(Duration.zero);
    ws.acceptPrepare();
    await again;
    controller.debugForceActive();
    controller.debugApplyFeedback(_activeFeedback(holdConfirmed: true));
    await Future<void>.delayed(Duration.zero);
    expect(assignments.createScoreCalls, 2);
    expect(assignments.attempts, hasLength(2));
  });
}
