import 'dart:async';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/practice/freestyle/freestyle_models.dart';
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/features/practice/submission_recording_controller.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

/// Test double: every exact lesson is already complete.
class _ReadyTutorials extends TutorialProgressService {
  @override
  bool get isInitialized => true;

  @override
  bool hasCompletedLesson(String movement, TrainingProp prop) => true;
}

const _assignment = GroupAssignment(
  id: 'asg-bbb',
  teacherId: 'teacher-1',
  groupId: 'g1',
  movementId: 'tm-bbb',
  revisionId: 'tm-bbb_v1',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Basic Bottle Balances',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'BSHM 4A',
  displayInstructions: 'Balance the bottle.',
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
        description: 'Keep control.',
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
  id: 'activity-bbb',
  teacherId: 'teacher-1',
  groupId: 'g1',
  movementId: 'tm-bbb',
  revisionId: 'tm-bbb_v1',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Bottle Control Activity',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'BSHM 4A',
  allowedProp: TrainingProp.bottle,
  maxScore: 30,
  activityAssessment: _activityAssessment,
  attemptPolicy: AssignmentAttemptPolicy.finite(3),
);

class _DelayedStartAssignments extends InMemoryClassroomAssignmentRepository {
  Duration? startDelay;
  Object? startError;
  List<AssignmentAttempt>? attemptSnapshot;
  int startCalls = 0;
  int abandonCalls = 0;

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  }) {
    final snapshot = attemptSnapshot;
    return snapshot == null
        ? super.watchAttemptsForTrainee(traineeId: traineeId)
        : Stream.value(snapshot);
  }

  @override
  Future<AssignmentAttempt> getOrCreateTeacherReviewSubmission({
    required String traineeId,
    required GroupAssignment assignment,
  }) async {
    startCalls += 1;
    final error = startError;
    if (error != null) throw error;
    final delay = startDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return super.getOrCreateTeacherReviewSubmission(
      traineeId: traineeId,
      assignment: assignment,
    );
  }

  @override
  Future<void> abandonTeacherActivityAttempt({
    required String traineeId,
    required AssignmentAttempt attempt,
  }) async {
    abandonCalls += 1;
    return super.abandonTeacherActivityAttempt(
      traineeId: traineeId,
      attempt: attempt,
    );
  }
}

class _GatedSettingsService extends SettingsService {
  Duration? cameraDelay;
  String? chosenCameraDeviceId = 'win32:test-camera';

  @override
  String? get selectedCameraDeviceId => chosenCameraDeviceId;

  @override
  Future<SettingsWriteOutcome> setSelectedCameraDevice(
    String? deviceId, {
    String? displayName,
  }) async {
    chosenCameraDeviceId = deviceId;
    notifyListeners();
    return SettingsWriteOutcome.saved;
  }

  @override
  Future<String?> loadSelectedCameraDeviceId() async {
    final delay = cameraDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return chosenCameraDeviceId;
  }
}

class _RecordingWebSocketService extends WebSocketService {
  int beginCalls = 0;
  int beginReadinessCalls = 0;
  int confirmReadinessCalls = 0;
  int activateCalls = 0;
  int targetCalls = 0;
  int startRecordingCalls = 0;
  int stopCalls = 0;
  int disconnectCalls = 0;
  Object? confirmReadinessError;
  Completer<CommandAck>? confirmReadinessAck;
  Completer<void>? stopGate;
  final preparePayloads = <Map<String, Object?>>[];
  Completer<CommandAck> prepareAck = Completer<CommandAck>();
  Completer<CommandAck> activateAck = Completer<CommandAck>();
  Completer<CommandAck> startRecordingAck = Completer<CommandAck>();
  final _previewFrames = StreamController<PreviewFrame>.broadcast();
  final _feedbackFrames = StreamController<PracticeFeedback>.broadcast();

  void emitConnectionChanged() => notifyListeners();

  @override
  WebSocketConnectionState get connectionState =>
      WebSocketConnectionState.connected;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {
    // The real service clears its session identity on stop before disconnect.
    // This fake only records stop, so avoid a second inherited stop here.
    disconnectCalls += 1;
  }

  @override
  Stream<PreviewFrame> get previewStream => _previewFrames.stream;

  @override
  Stream<PracticeFeedback> get feedbackStream => _feedbackFrames.stream;

  @override
  String beginPracticeAttempt() {
    beginCalls += 1;
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
    TeacherActivityReadinessSpec? readinessSpec,
    String? sessionMode,
    List<({String movement, TrainingProp prop})>? allowedMovements,
    Map<String, dynamic>? customMovementTemplate,
  }) {
    final resolvedSessionId =
        sessionId ?? currentSessionId ?? beginPracticeAttempt();
    preparePayloads.add({
      'action': 'prepare',
      'movement': movement,
      'difficulty': difficulty,
      'prop_type': prop.protocolValue,
      'bottle_detection_enabled': true,
      'session_id': resolvedSessionId,
      'request_id': 'req-test',
      'camera_device_id': cameraDeviceId,
      'camera_index': ?legacyCameraIndex,
      if (allowSubmissionRecording) 'allow_submission_recording': true,
      if (readinessSpec != null) 'readiness_spec': readinessSpec.toMap(),
      'session_mode': ?sessionMode,
      if (allowedMovements != null)
        'allowed_movements': [
          for (final entry in allowedMovements)
            {'movement': entry.movement, 'prop_type': entry.prop.protocolValue},
        ],
      'custom_movement_template': ?customMovementTemplate,
    });
    return prepareAck.future;
  }

  @override
  Future<CommandAck> sendActivate({String? sessionId}) {
    activateCalls += 1;
    return activateAck.future;
  }

  @override
  Future<CommandAck> sendSetEndlessTarget({
    required int targetGeneration,
    required String? movement,
    required TrainingProp prop,
    String? customMovementId,
    String? revisionId,
    Map<String, dynamic>? customMovementTemplate,
    String? sessionId,
  }) async {
    targetCalls += 1;
    return CommandAck(
      protocolVersion: 1,
      requestId: 'target-test',
      action: 'set_endless_target',
      accepted: true,
      sessionId: currentSessionId,
      sessionState: 'preparing',
    );
  }

  @override
  Future<CommandAck> sendStartSubmissionRecord({
    String? sessionId,
    int durationSeconds = 30,
  }) {
    startRecordingCalls += 1;
    return startRecordingAck.future;
  }

  @override
  Future<CommandAck> sendBeginReadiness({String? sessionId}) async {
    beginReadinessCalls += 1;
    return CommandAck(
      protocolVersion: 1,
      requestId: 'begin-readiness-test',
      action: 'begin_readiness',
      accepted: true,
      sessionId: currentSessionId,
      sessionState: 'readying',
    );
  }

  @override
  Future<CommandAck> sendConfirmReadiness({String? sessionId}) async {
    confirmReadinessCalls += 1;
    final error = confirmReadinessError;
    if (error != null) throw error;
    final pending = confirmReadinessAck;
    if (pending != null) return pending.future;
    return CommandAck(
      protocolVersion: 1,
      requestId: 'confirm-readiness-test',
      action: 'confirm_readiness',
      accepted: true,
      sessionId: currentSessionId,
      sessionState: 'readying',
    );
  }

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) async {
    stopCalls += 1;
    final gate = stopGate;
    if (gate != null) await gate.future;
    return const CommandAck(
      protocolVersion: 1,
      requestId: 'stop-test',
      action: 'stop',
      accepted: true,
      sessionState: 'idle',
    );
  }

  @override
  Future<CommandAck> sendCancelSubmissionRecord({String? sessionId}) async {
    return const CommandAck(
      protocolVersion: 1,
      requestId: 'cancel-record-test',
      action: 'cancel_submission_record',
      accepted: true,
    );
  }

  void acceptPrepare() {
    if (prepareAck.isCompleted) return;
    prepareAck.complete(
      CommandAck(
        protocolVersion: 1,
        requestId: 'req-test',
        action: 'prepare',
        accepted: true,
        sessionId: currentSessionId,
        sessionState: 'preparing',
      ),
    );
  }

  void rejectPrepare({required String message, required String errorCode}) {
    if (prepareAck.isCompleted) return;
    prepareAck.complete(
      CommandAck(
        protocolVersion: 1,
        requestId: 'req-test',
        action: 'prepare',
        accepted: false,
        sessionId: currentSessionId,
        errorCode: errorCode,
        message: message,
      ),
    );
  }

  void emitPreview() {
    _previewFrames.add(
      PreviewFrame(
        // A valid transparent 1x1 PNG keeps the camera Image widget quiet
        // while this test exercises lifecycle rather than image decoding.
        jpegBytes: Uint8List.fromList([
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
          0,
          0,
          0,
          13,
          73,
          72,
          68,
          82,
          0,
          0,
          0,
          1,
          0,
          0,
          0,
          1,
          8,
          6,
          0,
          0,
          0,
          31,
          21,
          196,
          137,
          0,
          0,
          0,
          13,
          73,
          68,
          65,
          84,
          8,
          215,
          99,
          248,
          207,
          192,
          240,
          31,
          0,
          5,
          0,
          1,
          255,
          137,
          153,
          61,
          29,
          0,
          0,
          0,
          0,
          73,
          69,
          78,
          68,
          174,
          66,
          96,
          130,
        ]),
        sessionId: currentSessionId,
        sessionState: 'preparing',
      ),
    );
  }

  void emitReadiness({required bool stable}) {
    _feedbackFrames.add(
      PracticeFeedback(
        bottleDetected: stable,
        movement: 'Free Practice',
        feedback: stable ? 'Ready' : 'Keep the bottle visible',
        feedbackType: stable ? 'positive' : 'warning',
        postureStatus: 'unknown',
        sessionState: 'readying',
        readinessComplete: stable,
        readinessStable: stable,
        readinessStableProgress: stable ? 1 : 0,
      ),
    );
  }

  void emitFatal({required String errorCode}) {
    _feedbackFrames.add(
      PracticeFeedback(
        bottleDetected: false,
        movement: 'Free Practice',
        feedback: 'Camera unavailable',
        feedbackType: 'error',
        postureStatus: 'unknown',
        errorCode: errorCode,
        sessionState: 'unavailable',
      ),
    );
  }

  void acceptActivate() {
    if (activateAck.isCompleted) return;
    activateAck.complete(
      CommandAck(
        protocolVersion: 1,
        requestId: 'activate-test',
        action: 'activate',
        accepted: true,
        sessionId: currentSessionId,
        sessionState: 'active',
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_previewFrames.close());
    unawaited(_feedbackFrames.close());
    super.dispose();
  }
}

class _UnusedAuth extends Fake implements AuthRepositoryBase {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingWebSocketService ws;
  late _DelayedStartAssignments assignments;
  late _GatedSettingsService settings;
  late AuthService auth;
  late GlobalKey<LivePracticeScreenState> screenKey;

  setUp(() {
    ws = _RecordingWebSocketService();
    assignments = _DelayedStartAssignments()
      ..startDelay = const Duration(milliseconds: 20);
    settings = _GatedSettingsService()
      ..cameraDelay = const Duration(milliseconds: 20);
    auth =
        AuthService(
          repository: _UnusedAuth(),
          awaitInitialAuthState: () async {},
        )..seedAuthenticatedUser(
          const User(
            id: 'trainee-1',
            firstName: 'Ada',
            lastName: 'Lovelace',
            email: 'ada@example.com',
            role: User.roleTrainee,
          ),
        );
    screenKey = GlobalKey<LivePracticeScreenState>();
  });

  tearDown(() {
    ws.dispose();
    assignments.dispose();
    settings.dispose();
    auth.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    TeacherCreatedAssignmentPractice? assignment,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<CameraDeviceService>(
            create: (_) => CameraDeviceService(
              httpGet: (_) async =>
                  '{"cameras":[{"device_id":"win32:test-camera","display_name":"Test Camera","runtime_index":0,"is_active":false,"identity_stable":true},{"device_id":"win32:external-camera","display_name":"External Camera","runtime_index":1,"is_active":false,"identity_stable":true}],"active_index":null}',
            ),
          ),
          ChangeNotifierProvider<TraineeProgressionService>(
            create: (_) => TraineeProgressionService.ready(totalXp: 20 * 250),
          ),
          ChangeNotifierProvider<TutorialProgressService>(
            create: (_) => _ReadyTutorials(),
          ),
          Provider<ClassroomAssignmentRepository>.value(value: assignments),
          Provider<AssignmentSubmissionRepository>(
            create: (_) =>
                InMemoryAssignmentSubmissionRepository(classroom: assignments),
          ),
        ],
        child: FluentApp(
          theme: AppTheme.dark,
          home: SizedBox(
            width: 1400,
            height: 900,
            child: LivePracticeScreen(
              key: screenKey,
              teacherCreatedAssignment: assignment,
              websocketService: ws,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Freestyle uses the camera selected in its idle panel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    settings.cameraDelay = null;
    await pumpScreen(tester);
    expect(
      find.byKey(const ValueKey('camera-source-preference')),
      findsOneWidget,
    );
    tester
        .widget<ComboBox<String>>(
          find.byKey(const ValueKey('camera-source-selector')),
        )
        .onChanged!('win32:external-camera');
    await tester.pump();
    await tester.tap(find.text('Start Endless Mode'));
    await tester.pump();
    expect(
      ws.preparePayloads.single['camera_device_id'],
      'win32:external-camera',
    );
    expect(
      find.byKey(const ValueKey('camera-source-preference')),
      findsNothing,
    );
    ws.acceptPrepare();
    await tester.pump();
  });

  testWidgets('Endless Shaker setup keeps one prop throughout the allowlist', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpScreen(tester);
    tester
        .widget<ComboBox<TrainingProp>>(find.byType(ComboBox<TrainingProp>))
        .onChanged!(TrainingProp.shaker);
    await tester.pump();
    await tester.tap(find.text('Start Endless Mode'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    final payload = ws.preparePayloads.single;
    expect(payload['prop_type'], 'shaker');
    final allowed = payload['allowed_movements'] as List;
    expect(allowed, isNotEmpty);
    expect(allowed.every((entry) => entry['prop_type'] == 'shaker'), isTrue);
    ws.acceptPrepare();
    await tester.pump();
  });

  testWidgets(
    'Activity auto-starts and can return to inline camera choice safely',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      settings.cameraDelay = null;
      assignments.startDelay = null;
      const reservedAttempt = AssignmentAttempt(
        id: 'reserved-attempt',
        traineeId: 'trainee-1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: 'activity-bbb',
        movementId: 'tm-bbb',
        revisionId: 'tm-bbb_v1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.inProgress,
        activityAssessmentSnapshot: _activityAssessment,
      );
      assignments.attemptSnapshot = const [reservedAttempt];
      await pumpScreen(
        tester,
        assignment: const TeacherCreatedAssignmentPractice(
          assignment: _activityAssignment,
          reservedActivityAttempt: reservedAttempt,
        ),
      );
      ws.emitConnectionChanged();
      await tester.pump();
      expect(ws.preparePayloads, hasLength(1));
      expect(find.text('Change camera'), findsOneWidget);

      ws.stopGate = Completer<void>();
      final chooseCamera = tester.widget<Button>(
        find.widgetWithText(Button, 'Change camera'),
      );
      chooseCamera.onPressed!();
      chooseCamera.onPressed!();
      expect(ws.stopCalls, 1);
      ws.stopGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(ws.stopCalls, 1);
      expect(ws.disconnectCalls, 1);
      expect(assignments.abandonCalls, 0);
      expect(ws.preparePayloads, hasLength(1));
      expect(
        find.byKey(const ValueKey('camera-source-preference')),
        findsOneWidget,
      );

      tester
          .widget<ComboBox<String>>(
            find.byKey(const ValueKey('camera-source-selector')),
          )
          .onChanged!('win32:external-camera');
      await tester.pump();
      await tester.tap(find.text('Start assignment practice'));
      await tester.pump();
      await tester.pump();
      expect(ws.preparePayloads, hasLength(2));
      expect(
        ws.preparePayloads.last['camera_device_id'],
        'win32:external-camera',
      );
      ws.acceptPrepare();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets(
    'duplicate Start during Teacher-created attempt persist is ignored',
    (tester) async {
      await pumpScreen(
        tester,
        assignment: const TeacherCreatedAssignmentPractice(
          assignment: _assignment,
        ),
      );

      expect(find.text('Start assignment practice'), findsOneWidget);
      expect(
        find.text(
          'Freestyle is unscored and is not saved to your practice history.',
        ),
        findsNothing,
      );
      expect(find.text('Backend Connected'), findsWidgets);

      final element = tester.element(find.byType(LivePracticeScreen));
      expect(element.read<AuthService>().currentUser?.id, 'trainee-1');
      expect(element.read<ClassroomAssignmentRepository>(), same(assignments));
      expect(element.read<SettingsService>(), same(settings));
      expect(ws.isConnected, isTrue);
      expect(screenKey.currentState, isNotNull);
      expect(screenKey.currentState!.debugWebSocket, same(ws));
      expect(screenKey.currentState!.debugWebSocket.isConnected, isTrue);

      screenKey.currentState!.debugStartSession();
      screenKey.currentState!.debugStartSession();
      await tester.pump();

      expect(assignments.startCalls, 1);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('practice-primary-action')),
          matching: find.byType(ProgressRing),
        ),
        findsOneWidget,
      );
      final action = tester.widget<GameActionButton>(
        find.descendant(
          of: find.byKey(const ValueKey('practice-primary-action')),
          matching: find.byType(GameActionButton),
        ),
      );
      expect(assignments.startCalls, 1);
      expect(action.isLoading, isTrue);

      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump();

      expect(assignments.startCalls, 1);
      expect(ws.beginCalls, 1);
      expect(ws.preparePayloads, hasLength(1));
      final payload = ws.preparePayloads.single;
      expect(payload['action'], 'prepare');
      expect(payload['movement'], 'Free Practice');
      expect(payload['difficulty'], 'Easy');
      expect(payload['prop_type'], 'bottle');
      expect(payload.containsKey('session_mode'), isFalse);
      expect(payload.containsKey('allowed_movements'), isFalse);
      expect(payload['bottle_detection_enabled'], isTrue);
      expect(payload['session_id'], ws.currentSessionId);
      expect(payload.containsKey('camera_device_id'), isTrue);
      expect(payload.containsKey('camera_index'), isFalse);
      expect(payload.values, isNot(contains('Basic Bottle Balances')));
      expect(payload.values, isNot(contains('asg-bbb')));
      expect(payload.values, isNot(contains('teacher-1')));
      expect(payload.values, isNot(contains('g1')));
      expect(payload.values, isNot(contains('tm-bbb_v1')));

      ws.acceptPrepare();
      await tester.pump();
    },
  );

  testWidgets(
    'normal assignment starts one recorder immediately after activation',
    (tester) async {
      assignments.startDelay = null;
      settings.cameraDelay = null;
      await pumpScreen(
        tester,
        assignment: const TeacherCreatedAssignmentPractice(
          assignment: _assignment,
        ),
      );

      unawaited(screenKey.currentState!.debugStartSession());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      ws.acceptPrepare();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(
        screenKey.currentState!.debugRun.phase,
        PracticeRunPhase.preparingCamera,
      );
      expect(
        screenKey.currentState!.debugRun.onPreviewFeedback(
          hasJpegFrame: true,
          isFatal: false,
        ),
        isTrue,
      );
      screenKey.currentState!.debugRun.enterCountdown();
      expect(
        screenKey.currentState!.debugRun.phase,
        PracticeRunPhase.countdown,
      );

      unawaited(screenKey.currentState!.debugBeginSessionAfterCountdown());
      unawaited(screenKey.currentState!.debugBeginSessionAfterCountdown());
      await tester.pump();
      expect(ws.activateCalls, 1);
      expect(ws.startRecordingCalls, 0);

      ws.acceptActivate();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(ws.startRecordingCalls, 1);
      expect(
        screenKey.currentState!.debugRecording!.phase,
        SubmissionRecordingPhase.idle,
        reason: 'Recording waits for the backend start acknowledgement.',
      );
      expect(find.text('Starting recording…'), findsOneWidget);

      ws.startRecordingAck.complete(
        const CommandAck(
          protocolVersion: 1,
          requestId: 'start-recording-test',
          action: 'start_submission_record',
          accepted: true,
          sessionId: 'session-test',
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(ws.startRecordingCalls, 1);
      expect(
        screenKey.currentState!.debugRecording!.phase,
        SubmissionRecordingPhase.recording,
      );
      expect(find.text('Stop recording'), findsOneWidget);
    },
  );

  testWidgets('Playground overlapping Start prepares one freestyle session', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Endless Mode'), findsWidgets);
    expect(find.text('Start Endless Mode'), findsOneWidget);
    expect(
      find.text('Run score is session only. Mastery and XP are unchanged.'),
      findsWidgets,
    );
    expect(find.text('Build Your Set'), findsNothing);
    expect(find.text('Free Practice'), findsNothing);
    final cameraBox = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('practice-camera-workspace')),
    );
    expect(cameraBox.size.aspectRatio, closeTo(4 / 3, 0.01));

    screenKey.currentState!.debugStartSession();
    screenKey.currentState!.debugStartSession();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(ws.beginCalls, 1);
    expect(ws.preparePayloads, hasLength(1));
    expect(ws.preparePayloads.single['movement'], 'Free Practice');
    expect(ws.preparePayloads.single['session_mode'], 'endless');
    expect(ws.preparePayloads.single['prop_type'], 'bottle');
    expect(ws.preparePayloads.single['allowed_movements'], isA<List>());
    expect(
      (ws.preparePayloads.single['allowed_movements'] as List).any(
        (entry) =>
            entry is Map &&
            entry['movement'] == 'Normal Grip' &&
            entry['prop_type'] == 'bottle',
      ),
      isTrue,
    );
    ws.acceptPrepare();
    await tester.pump();
  });

  testWidgets(
    'Playground first JPEG has one activation owner while its ack is slow',
    (tester) async {
      await pumpScreen(tester);

      screenKey.currentState!.debugStartSession();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      ws.acceptPrepare();
      await tester.pump();

      ws.emitPreview();
      await tester.pump();
      // Preview bytes are fixtures for lifecycle timing; ignore decode noise.
      while (tester.takeException() != null) {}
      await tester.pump();
      while (tester.takeException() != null) {}

      expect(ws.targetCalls, 1);
      expect(ws.activateCalls, 1);
      expect(
        find.byType(GameCountdownOverlay),
        findsNothing,
        reason: 'Freestyle does not use a per-movement Get Ready countdown.',
      );
      expect(
        screenKey.currentState!.debugFreestyle.phase,
        FreestyleSessionPhase.ready,
      );

      await tester.pump(const Duration(seconds: 5));
      expect(ws.activateCalls, 1);

      ws.acceptActivate();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump();
      expect(
        screenKey.currentState!.debugFreestyle.phase,
        FreestyleSessionPhase.active,
      );
    },
  );

  testWidgets(
    'assignment initialization permission denial does not prepare the camera',
    (tester) async {
      assignments.startError = FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );
      await pumpScreen(
        tester,
        assignment: const TeacherCreatedAssignmentPractice(
          assignment: _assignment,
        ),
      );

      screenKey.currentState!.debugStartSession();
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'You no longer have permission to start this classroom assignment.',
        ),
        findsWidgets,
      );
      expect(assignments.startCalls, 1);
      expect(ws.beginCalls, 0);
      expect(ws.preparePayloads, isEmpty);
    },
  );

  testWidgets(
    'accepted Activity readiness ignores late loss but still honors fatal camera feedback',
    (tester) async {
      const reservedAttempt = AssignmentAttempt(
        id: 'reserved-attempt',
        traineeId: 'trainee-1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: 'activity-bbb',
        movementId: 'tm-bbb',
        revisionId: 'tm-bbb_v1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.inProgress,
        activityAssessmentSnapshot: _activityAssessment,
      );
      assignments
        ..startDelay = null
        ..attemptSnapshot = const [reservedAttempt];
      settings.cameraDelay = null;
      await pumpScreen(
        tester,
        assignment: const TeacherCreatedAssignmentPractice(
          assignment: _activityAssignment,
          reservedActivityAttempt: reservedAttempt,
        ),
      );

      unawaited(screenKey.currentState!.debugStartSession());
      await tester.pump();
      ws.acceptPrepare();
      await tester.pump();
      ws.emitPreview();
      await tester.pump();
      expect(ws.beginReadinessCalls, 1);

      ws.emitReadiness(stable: true);
      await tester.pump();
      expect(
        screenKey.currentState!.debugRun.requestStartPractice(
          readinessStable: true,
        ),
        isTrue,
      );
      unawaited(screenKey.currentState!.debugConfirmActivityReadiness());
      await tester.pump();
      expect(ws.confirmReadinessCalls, 1);
      expect(
        screenKey.currentState!.debugRun.phase,
        PracticeRunPhase.countdown,
      );

      ws.emitReadiness(stable: false);
      await tester.pump();
      expect(
        screenKey.currentState!.debugRun.phase,
        PracticeRunPhase.countdown,
      );
      expect(assignments.abandonCalls, 0);
      expect(find.text('Camera session interrupted'), findsNothing);

      ws.emitFatal(errorCode: 'camera_unavailable');
      await tester.pump();
      expect(screenKey.currentState!.debugRun.phase, PracticeRunPhase.error);
      expect(find.text('No usable camera'), findsOneWidget);
    },
  );

  testWidgets(
    'Activity readiness timeout stays recoverable instead of showing camera interruption',
    (tester) async {
      const reservedAttempt = AssignmentAttempt(
        id: 'reserved-attempt',
        traineeId: 'trainee-1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: 'activity-bbb',
        movementId: 'tm-bbb',
        revisionId: 'tm-bbb_v1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.inProgress,
        activityAssessmentSnapshot: _activityAssessment,
      );
      assignments
        ..startDelay = null
        ..attemptSnapshot = const [reservedAttempt];
      settings.cameraDelay = null;
      ws.confirmReadinessError = CommandTimeoutException(
        'confirm-readiness-test',
        'confirm_readiness',
      );
      await pumpScreen(
        tester,
        assignment: const TeacherCreatedAssignmentPractice(
          assignment: _activityAssignment,
          reservedActivityAttempt: reservedAttempt,
        ),
      );

      unawaited(screenKey.currentState!.debugStartSession());
      await tester.pump();
      ws.acceptPrepare();
      await tester.pump();
      ws.emitPreview();
      await tester.pump();
      ws.emitReadiness(stable: true);
      await tester.pump();
      expect(
        screenKey.currentState!.debugRun.requestStartPractice(
          readinessStable: true,
        ),
        isTrue,
      );

      await screenKey.currentState!.debugConfirmActivityReadiness();
      await tester.pump();

      expect(
        screenKey.currentState!.debugRun.phase,
        PracticeRunPhase.readiness,
      );
      expect(
        screenKey.currentState!.debugRun.readiness.recoverableMessage,
        contains('timed out'),
      );
      expect(assignments.abandonCalls, 0);
      expect(find.text('Camera session interrupted'), findsNothing);
    },
  );

  testWidgets(
    'fatal readiness teardown blocks an immediate overlapping prepare',
    (tester) async {
      const reservedAttempt = AssignmentAttempt(
        id: 'reserved-attempt',
        traineeId: 'trainee-1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: 'activity-bbb',
        movementId: 'tm-bbb',
        revisionId: 'tm-bbb_v1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.inProgress,
        activityAssessmentSnapshot: _activityAssessment,
      );
      assignments
        ..startDelay = null
        ..attemptSnapshot = const [reservedAttempt];
      settings.cameraDelay = null;
      ws
        ..confirmReadinessError = CommandDisconnectedException(
          'confirm-readiness-test',
          'confirm_readiness',
        )
        ..stopGate = Completer<void>();
      await pumpScreen(
        tester,
        assignment: const TeacherCreatedAssignmentPractice(
          assignment: _activityAssignment,
          reservedActivityAttempt: reservedAttempt,
        ),
      );

      unawaited(screenKey.currentState!.debugStartSession());
      await tester.pump();
      ws.acceptPrepare();
      await tester.pump();
      ws.emitPreview();
      await tester.pump();
      ws.emitReadiness(stable: true);
      await tester.pump();
      expect(
        screenKey.currentState!.debugRun.requestStartPractice(
          readinessStable: true,
        ),
        isTrue,
      );
      await screenKey.currentState!.debugConfirmActivityReadiness();
      await tester.pump();
      expect(screenKey.currentState!.debugRun.phase, PracticeRunPhase.error);
      expect(ws.stopCalls, 1);

      ws.confirmReadinessError = null;
      unawaited(screenKey.currentState!.debugStartSession());
      await tester.pump();
      expect(ws.beginCalls, 1);
      expect(ws.stopCalls, 1);

      ws.stopGate!.complete();
      ws.stopGate = null;
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(ws.stopCalls, 1);
      expect(ws.beginCalls, 1);
    },
  );

  testWidgets(
    'stale confirm acknowledgment after reset cannot advance the restarted run',
    (tester) async {
      const reservedAttempt = AssignmentAttempt(
        id: 'reserved-attempt',
        traineeId: 'trainee-1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: 'activity-bbb',
        movementId: 'tm-bbb',
        revisionId: 'tm-bbb_v1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.inProgress,
        activityAssessmentSnapshot: _activityAssessment,
      );
      assignments
        ..startDelay = null
        ..attemptSnapshot = const [reservedAttempt];
      settings.cameraDelay = null;
      final staleAck = Completer<CommandAck>();
      ws.confirmReadinessAck = staleAck;
      await pumpScreen(
        tester,
        assignment: const TeacherCreatedAssignmentPractice(
          assignment: _activityAssignment,
          reservedActivityAttempt: reservedAttempt,
        ),
      );

      unawaited(screenKey.currentState!.debugStartSession());
      await tester.pump();
      ws.acceptPrepare();
      await tester.pump();
      ws.emitPreview();
      await tester.pump();
      ws.emitReadiness(stable: true);
      await tester.pump();
      expect(
        screenKey.currentState!.debugRun.requestStartPractice(
          readinessStable: true,
        ),
        isTrue,
      );
      unawaited(screenKey.currentState!.debugConfirmActivityReadiness());
      await tester.pump();
      final oldGeneration =
          screenKey.currentState!.debugRun.lifecycleGeneration;

      final run = screenKey.currentState!.debugRun;
      run.cancelToIdle();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      await tester.pump();
      expect(run.lifecycleGeneration, greaterThan(oldGeneration));
      expect(run.phase, PracticeRunPhase.readiness);
      final abandonCallsBeforeAck = assignments.abandonCalls;

      staleAck.complete(
        const CommandAck(
          protocolVersion: 1,
          requestId: 'stale-confirm-readiness',
          action: 'confirm_readiness',
          accepted: true,
          sessionState: 'readying',
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();

      expect(run.phase, PracticeRunPhase.readiness);
      expect(run.readinessFrozen, isFalse);
      expect(assignments.abandonCalls, abandonCallsBeforeAck);
      expect(ws.activateCalls, 0);
    },
  );

  testWidgets(
    'submitted Activity state stays out of camera recovery and disables start',
    (tester) async {
      assignments
        ..startDelay = null
        ..attemptSnapshot = const [
          AssignmentAttempt(
            id: 'submitted-attempt',
            traineeId: 'trainee-1',
            teacherId: 'teacher-1',
            groupId: 'g1',
            assignmentId: 'activity-bbb',
            movementId: 'tm-bbb',
            revisionId: 'tm-bbb_v1',
            origin: MovementOrigin.teacherCreated,
            assessmentMode: AssessmentMode.teacherReviewed,
            attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
            status: AssignmentAttemptStatus.submitted,
            activityAssessmentSnapshot: _activityAssessment,
          ),
        ];
      await pumpScreen(
        tester,
        assignment: const TeacherCreatedAssignmentPractice(
          assignment: _activityAssignment,
        ),
      );

      screenKey.currentState!.debugStartSession();
      await tester.pump();
      await tester.pump();

      expect(
        find.text('This submission is waiting for your teacher to check it.'),
        findsOneWidget,
      );
      expect(find.text('Camera session interrupted'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Attempt unavailable'), findsOneWidget);
      final action = tester.widget<GameActionButton>(
        find.descendant(
          of: find.byKey(const ValueKey('practice-primary-action')),
          matching: find.byType(GameActionButton),
        ),
      );
      expect(action.onPressed, isNull);
      expect(action.isLoading, isFalse);
      expect(ws.beginCalls, 0);
      expect(ws.preparePayloads, isEmpty);
    },
  );
}
