import 'dart:async';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
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
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

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
  final preparePayloads = <Map<String, Object?>>[];
  Completer<CommandAck> prepareAck = Completer<CommandAck>();

  @override
  WebSocketConnectionState get connectionState =>
      WebSocketConnectionState.connected;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

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
    });
    return prepareAck.future;
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

  testWidgets('Free Practice overlapping Start still sends one prepare', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Playground'), findsOneWidget);
    expect(find.text('Start Playground'), findsOneWidget);
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
    ws.acceptPrepare();
    await tester.pump();
  });

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
