import 'dart:async';
import 'dart:typed_data';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
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
import 'package:elixr_application/services/auth_service.dart';
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

class _DelayedStartAssignments extends InMemoryClassroomAssignmentRepository {
  Duration? startDelay;
  Object? startError;
  int startCalls = 0;

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
}

class _GatedSettingsService extends SettingsService {
  Duration? cameraDelay;

  @override
  Future<String?> loadSelectedCameraDeviceId() async {
    final delay = cameraDelay;
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    return 'win32:test-camera';
  }
}

class _RecordingWebSocketService extends WebSocketService {
  int beginCalls = 0;
  int activateCalls = 0;
  final preparePayloads = <Map<String, Object?>>[];
  Completer<CommandAck> prepareAck = Completer<CommandAck>();
  Completer<CommandAck> activateAck = Completer<CommandAck>();
  final _previewFrames = StreamController<PreviewFrame>.broadcast();

  @override
  WebSocketConnectionState get connectionState =>
      WebSocketConnectionState.connected;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  @override
  Stream<PreviewFrame> get previewStream => _previewFrames.stream;

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
    String sessionPurpose = 'official',
    AssessmentSpec? assessmentSpec,
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
      'readiness_spec': ?readinessSpec?.toMap(),
      'session_mode': ?sessionMode,
      'allowed_movements': ?allowedMovements
          ?.map(
            (entry) => {
              'movement': entry.movement,
              'prop_type': entry.prop.protocolValue,
            },
          )
          .toList(),
    });
    return prepareAck.future;
  }

  @override
  Future<CommandAck> sendActivate({String? sessionId}) {
    activateCalls += 1;
    return activateAck.future;
  }

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) {
    return Future.value(
      const CommandAck(
        protocolVersion: 1,
        requestId: 'stop-test',
        action: 'stop',
        accepted: true,
        sessionState: 'idle',
      ),
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

  testWidgets('Playground overlapping Start prepares one freestyle session', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Playground'), findsOneWidget);
    expect(find.text('Start Freestyle'), findsOneWidget);
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
    expect(ws.preparePayloads.single['session_mode'], 'freestyle');
    expect(ws.preparePayloads.single['prop_type'], 'bottle_and_shaker');
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
}
