import 'dart:async';
import 'dart:typed_data';

import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/features/teacher/movements/teacher_live_test_controller.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movement_builder_draft.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingLiveTestWebSocket extends WebSocketService {
  _RecordingLiveTestWebSocket() : super();

  final actions = <String>[];
  final prepareCalls = <Map<String, Object?>>[];
  int stopCalls = 0;
  int startCalls = 0;
  WebSocketConnectionState _state = WebSocketConnectionState.connected;

  Completer<CommandAck> prepareAck = Completer<CommandAck>();
  Completer<CommandAck> beginReadinessAck = Completer<CommandAck>();
  Completer<CommandAck> confirmReadinessAck = Completer<CommandAck>();
  Completer<CommandAck> activateAck = Completer<CommandAck>();
  Completer<CommandAck> stopAck = Completer<CommandAck>();

  final _feedback = StreamController<PracticeFeedback>.broadcast();
  final _preview = StreamController<PreviewFrame>.broadcast();

  @override
  Stream<PracticeFeedback> get feedbackStream => _feedback.stream;

  @override
  Stream<PreviewFrame> get previewStream => _preview.stream;

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

  void emitPreview(List<int> bytes) {
    _preview.add(PreviewFrame(jpegBytes: Uint8List.fromList(bytes)));
  }

  void simulateDisconnect() {
    _state = WebSocketConnectionState.disconnected;
    notifyListeners();
  }

  CommandAck _ack(String action, {bool accepted = true, String? errorCode}) {
    return CommandAck(
      protocolVersion: 1,
      requestId: 'req-$action',
      action: action,
      accepted: accepted,
      sessionId: currentSessionId,
      sessionState: accepted ? action : 'idle',
      errorCode: errorCode,
      message: errorCode,
    );
  }

  @override
  String beginPracticeAttempt() {
    actions.add('begin');
    return super.beginPracticeAttempt();
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
    actions.add('prepare');
    prepareCalls.add({
      'movement': movement,
      'difficulty': difficulty,
      'prop': prop.protocolValue,
      'camera_device_id': cameraDeviceId,
      'allow_submission_recording': allowSubmissionRecording,
      'session_purpose': sessionPurpose.wireValue,
      'assessment_spec': assessmentSpec?.toMap(),
    });
    return prepareAck.future;
  }

  @override
  Future<CommandAck> sendBeginReadiness({String? sessionId}) {
    actions.add('begin_readiness');
    return beginReadinessAck.future;
  }

  @override
  Future<CommandAck> sendConfirmReadiness({String? sessionId}) {
    actions.add('confirm_readiness');
    return confirmReadinessAck.future;
  }

  @override
  Future<CommandAck> sendActivate({String? sessionId}) {
    actions.add('activate');
    return activateAck.future;
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
    actions.add('start');
    return Future.value(_ack('start', accepted: false));
  }

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) {
    stopCalls += 1;
    actions.add('stop');
    return Future.value(_ack('stop'));
  }

  void acceptPrepare() {
    if (!prepareAck.isCompleted) {
      prepareAck.complete(_ack('prepare'));
    }
  }

  void rejectPrepare({required String errorCode, required String message}) {
    if (!prepareAck.isCompleted) {
      prepareAck.complete(
        CommandAck(
          protocolVersion: 1,
          requestId: 'req-prepare',
          action: 'prepare',
          accepted: false,
          errorCode: errorCode,
          message: message,
        ),
      );
    }
  }

  void acceptBeginReadiness() {
    if (!beginReadinessAck.isCompleted) {
      beginReadinessAck.complete(_ack('begin_readiness'));
    }
  }

  void acceptConfirmReadiness() {
    if (!confirmReadinessAck.isCompleted) {
      confirmReadinessAck.complete(_ack('confirm_readiness'));
    }
  }

  void acceptActivate() {
    if (!activateAck.isCompleted) {
      activateAck.complete(_ack('activate'));
    }
  }

  void acceptStop() {
    if (!stopAck.isCompleted) {
      stopAck.complete(_ack('stop'));
    }
  }

  void resetAcks() {
    prepareAck = Completer<CommandAck>();
    beginReadinessAck = Completer<CommandAck>();
    confirmReadinessAck = Completer<CommandAck>();
    activateAck = Completer<CommandAck>();
    stopAck = Completer<CommandAck>();
  }

  @override
  void dispose() {
    _feedback.close();
    _preview.close();
    super.dispose();
  }
}

TeacherLiveTestDraft _draft({
  AssessmentLaterality laterality = AssessmentLaterality.either,
}) {
  return TeacherLiveTestDraft(
    title: 'Classroom Wrist Stall',
    instructions: 'Balance the bottle on the wrist.',
    safetyGuidance: 'Clear the area.',
    assessmentSpec: AssessmentSpec(laterality: laterality),
  );
}

PracticeFeedback _readinessFeedback({
  required bool stable,
  required bool complete,
  double progress = 1,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: kTemplateAssessmentMovement,
    feedback: 'Checking Wrist Stall setup.',
    feedbackType: 'info',
    postureStatus: 'unknown',
    sessionState: 'readying',
    readinessComplete: complete,
    readinessStable: stable,
    readinessStableProgress: progress,
    readinessItems: const [
      ReadinessItemView(
        code: 'bottle_detected',
        status: ReadinessItemStatus.ready,
        message: 'Bottle visible',
      ),
      ReadinessItemView(
        code: 'pose_visible',
        status: ReadinessItemStatus.ready,
        message: 'Body visible',
      ),
      ReadinessItemView(
        code: 'wrist_visible',
        status: ReadinessItemStatus.ready,
        message: 'Required wrist visible',
      ),
    ],
  );
}

PracticeFeedback _activeFeedback({
  bool holdConfirmed = false,
  double holdProgress = 0.4,
  RubricAssessment? assessment,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: kTemplateAssessmentMovement,
    feedback: holdConfirmed
        ? 'Wrist Stall detected successfully'
        : 'Keep the bottle still on the wrist.',
    feedbackType: holdConfirmed ? 'positive' : 'warning',
    postureStatus: holdConfirmed ? 'stable' : 'unstable',
    sessionState: 'active',
    holdProgress: holdProgress,
    holdConfirmed: holdConfirmed,
    assessment:
        assessment ??
        const RubricAssessment(
          technique: 2,
          stability: 2,
          completion: 1,
          propPositioning: 2,
        ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingLiveTestWebSocket ws;
  late TeacherLiveTestController controller;

  setUp(() {
    ws = _RecordingLiveTestWebSocket();
    controller = TeacherLiveTestController(
      draft: _draft(laterality: AssessmentLaterality.left),
      websocket: ws,
      loadCameraDeviceId: () async => 'win32:teacher-cam',
    );
  });

  tearDown(() {
    controller.dispose();
    ws.dispose();
  });

  Future<void> prepareUntilReadiness() async {
    final started = controller.startSession();
    await Future<void>.delayed(Duration.zero);
    ws.acceptPrepare();
    await started;
    ws.emitPreview([1, 2, 3, 4]);
    await Future<void>.delayed(Duration.zero);
    ws.acceptBeginReadiness();
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'prepare uses live_test, reserved template identity, and typed spec',
    () async {
      final started = controller.startSession();
      await Future<void>.delayed(Duration.zero);
      ws.acceptPrepare();
      await started;

      expect(ws.startCalls, 0);
      expect(ws.prepareCalls, hasLength(1));
      expect(ws.prepareCalls.single['movement'], kTemplateAssessmentMovement);
      expect(
        ws.prepareCalls.single['difficulty'],
        kTemplateAssessmentDifficulty,
      );
      expect(
        ws.prepareCalls.single['movement'],
        isNot('Classroom Wrist Stall'),
      );
      expect(ws.prepareCalls.single['movement'], isNot('Free Practice'));
      expect(ws.prepareCalls.single['session_purpose'], 'live_test');
      expect(ws.prepareCalls.single['allow_submission_recording'], isFalse);
      expect(ws.prepareCalls.single['camera_device_id'], 'win32:teacher-cam');
      expect(ws.prepareCalls.single['assessment_spec'], {
        'schema_version': 1,
        'template_id': 'balance_stall.wrist_v1',
        'prop': 'bottle',
        'target': 'wrist',
        'laterality': 'left',
      });
    },
  );

  test('first preview enters readiness and sends begin_readiness', () async {
    await prepareUntilReadiness();

    expect(controller.phase, PracticeRunPhase.readiness);
    expect(
      ws.actions,
      containsAllInOrder(['begin', 'prepare', 'begin_readiness']),
    );
    expect(ws.startCalls, 0);
  });

  test('stable readiness does not auto-confirm or activate', () async {
    await prepareUntilReadiness();
    ws.emitFeedback(_readinessFeedback(stable: true, complete: true));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 900));

    expect(controller.readiness.stable, isTrue);
    expect(controller.canStartTest, isTrue);
    expect(ws.actions, isNot(contains('confirm_readiness')));
    expect(ws.actions, isNot(contains('activate')));
    expect(controller.phase, PracticeRunPhase.readiness);
  });

  test('teacher confirm then countdown then activate', () async {
    await prepareUntilReadiness();
    ws.emitFeedback(_readinessFeedback(stable: true, complete: true));
    await Future<void>.delayed(Duration.zero);

    final confirmed = controller.confirmReadiness();
    await Future<void>.delayed(Duration.zero);
    ws.acceptConfirmReadiness();
    await confirmed;

    expect(controller.phase, PracticeRunPhase.countdown);
    expect(ws.actions, contains('confirm_readiness'));
    expect(ws.actions, isNot(contains('activate')));

    final activated = controller.activateAfterCountdown();
    await Future<void>.delayed(Duration.zero);
    ws.acceptActivate();
    await activated;

    expect(controller.phase, PracticeRunPhase.active);
    expect(
      ws.actions,
      containsAllInOrder([
        'begin',
        'prepare',
        'begin_readiness',
        'confirm_readiness',
        'activate',
      ]),
    );
    expect(ws.startCalls, 0);
  });

  test(
    'active feedback renders hold progress and Assessment V2 rubric',
    () async {
      await prepareUntilReadiness();
      ws.emitFeedback(_readinessFeedback(stable: true, complete: true));
      await Future<void>.delayed(Duration.zero);
      final confirmed = controller.confirmReadiness();
      ws.acceptConfirmReadiness();
      await confirmed;
      final activated = controller.activateAfterCountdown();
      ws.acceptActivate();
      await activated;

      const rubric = RubricAssessment(
        technique: 3,
        stability: 2,
        completion: 3,
        propPositioning: 2,
      );
      ws.emitFeedback(_activeFeedback(holdProgress: 0.7, assessment: rubric));
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.latestFeedback?.feedback,
        contains('Keep the bottle still'),
      );
      expect(controller.latestFeedback?.bottleDetected, isTrue);
      expect(controller.holdProgress, closeTo(0.7, 0.001));
      expect(controller.assessment?.total, 10);
      expect(
        controller.assessment?.performanceLevel,
        PerformanceLevel.proficient,
      );
      expect(controller.testSucceeded, isFalse);
    },
  );

  test('hold confirmed shows success and stops the session', () async {
    await prepareUntilReadiness();
    ws.emitFeedback(_readinessFeedback(stable: true, complete: true));
    await Future<void>.delayed(Duration.zero);
    final confirmed = controller.confirmReadiness();
    ws.acceptConfirmReadiness();
    await confirmed;
    final activated = controller.activateAfterCountdown();
    ws.acceptActivate();
    await activated;

    ws.emitFeedback(_activeFeedback(holdConfirmed: true, holdProgress: 1));
    await Future<void>.delayed(Duration.zero);

    expect(controller.testSucceeded, isTrue);
    expect(controller.phase, PracticeRunPhase.completed);
    expect(ws.stopCalls, greaterThanOrEqualTo(1));
    expect(controller.assessment?.total, 7);
  });

  test('stop and dispose are idempotent and release the session', () async {
    await prepareUntilReadiness();
    await controller.stopTest();
    await controller.stopTest();
    controller.dispose();

    expect(ws.stopCalls, 1);
    expect(controller.previewFrame, isNull);
  });

  test('close during readiness stops the backend session', () async {
    await prepareUntilReadiness();
    await controller.closeTest();

    expect(ws.stopCalls, 1);
    expect(controller.phase, PracticeRunPhase.idle);
  });

  test(
    'disconnect during an active session stops and reports an error',
    () async {
      await prepareUntilReadiness();
      ws.emitFeedback(_readinessFeedback(stable: true, complete: true));
      await Future<void>.delayed(Duration.zero);
      final confirmed = controller.confirmReadiness();
      ws.acceptConfirmReadiness();
      await confirmed;
      final activated = controller.activateAfterCountdown();
      ws.acceptActivate();
      await activated;

      ws.simulateDisconnect();
      await Future<void>.delayed(Duration.zero);

      expect(controller.errorMessage, isNotNull);
      expect(controller.errorMessage, isNot(contains('Exception')));
      expect(ws.stopCalls, greaterThanOrEqualTo(1));
    },
  );

  test('prepare rejection surfaces a teacher-facing error', () async {
    final started = controller.startSession();
    await Future<void>.delayed(Duration.zero);
    ws.rejectPrepare(
      errorCode: 'unsupported_template',
      message: 'This template is not supported.',
    );
    await started;

    expect(controller.errorMessage, 'This template is not supported.');
    expect(controller.phase, PracticeRunPhase.error);
  });
}
