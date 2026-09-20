import 'dart:async';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/class_challenge_session_context.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session_assignment_context.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/practice/freestyle/freestyle_models.dart';
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/features/practice/practice_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _ReadyTutorials extends TutorialProgressService {
  @override
  bool get isInitialized => true;

  @override
  bool hasCompletedLesson(String movement, TrainingProp prop) => true;
}

class _UnusedAuth extends Fake implements AuthRepositoryBase {}

class _TestWebSocket extends WebSocketService {
  int stopCalls = 0;
  Completer<CommandAck> prepareAck = Completer<CommandAck>();
  final List<String?> prepareCameraDeviceIds = [];

  @override
  WebSocketConnectionState get connectionState =>
      WebSocketConnectionState.connected;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

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
  }) {
    prepareCameraDeviceIds.add(cameraDeviceId);
    return prepareAck.future;
  }

  @override
  Future<CommandAck> sendPause({String? sessionId}) {
    return Future.value(
      CommandAck(
        protocolVersion: 1,
        requestId: 'pause-test',
        action: 'pause',
        accepted: true,
        sessionId: sessionId ?? currentSessionId,
        sessionState: 'active',
      ),
    );
  }

  @override
  Future<CommandAck> sendResume({String? sessionId}) {
    return Future.value(
      CommandAck(
        protocolVersion: 1,
        requestId: 'resume-test',
        action: 'resume',
        accepted: true,
        sessionId: sessionId ?? currentSessionId,
        sessionState: 'active',
      ),
    );
  }

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) {
    stopCalls += 1;
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
}

class _GatedSettingsService extends SettingsService {
  @override
  Future<String?> loadSelectedCameraDeviceId() async => 'win32:test-camera';
}

class _TestSessionService extends SessionService {
  int completedSaveCalls = 0;
  int reservedSessionIdCalls = 0;
  String? existingSessionId;

  @override
  String reserveSessionId() {
    reservedSessionIdCalls++;
    return 'test-session-id';
  }

  @override
  Future<String> saveCompletedSession({
    required String userId,
    required String displayName,
    required String movementName,
    required String difficulty,
    required RubricAssessment rubric,
    required int durationSeconds,
    required List<PracticeFeedback> sessionImprovements,
    TrainingProp prop = TrainingProp.bottle,
    String? profilePictureUrl,
    String? existingSessionId,
    Uint8List? evidenceJpegBytes,
    bool saveEvidence = false,
    SessionAssignmentContext? assignmentContext,
    ClassChallengeSessionContext? challengeContext,
  }) async {
    completedSaveCalls++;
    this.existingSessionId = existingSessionId;
    return existingSessionId ?? 'test-session-id';
  }
}

Finder _backButton() => find.byKey(const ValueKey('training-header-back'));

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TestWebSocket ws;
  late AuthService auth;
  late _GatedSettingsService settings;

  setUp(() {
    ws = _TestWebSocket();
    settings = _GatedSettingsService();
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
  });

  tearDown(() {
    ws.dispose();
    settings.dispose();
    auth.dispose();
  });

  Future<GlobalKey<PracticeScreenState>> pumpPractice(
    WidgetTester tester, {
    SessionService? sessionService,
    PracticeExecutionMode executionMode = PracticeExecutionMode.trainee,
  }) async {
    final practiceKey = GlobalKey<PracticeScreenState>();
    final router = GoRouter(
      initialLocation: executionMode == PracticeExecutionMode.teacherPreview
          ? AppRoutePaths.teacherMovementPreview
          : AppRoutePaths.practice,
      routes: [
        GoRoute(
          path: AppRoutePaths.practice,
          builder: (context, state) => PracticeScreen(
            key: practiceKey,
            movement: 'Hand Stall',
            difficulty: 'Easy',
            executionMode: executionMode,
            websocketService: ws,
          ),
        ),
        GoRoute(
          path: AppRoutePaths.teacherMovementPreview,
          builder: (context, state) => PracticeScreen(
            key: practiceKey,
            movement: 'Hand Stall',
            difficulty: 'Easy',
            executionMode: executionMode,
            websocketService: ws,
          ),
        ),
        GoRoute(
          path: AppRoutePaths.movements,
          builder: (context, state) => const Text('movements-destination'),
        ),
        GoRoute(
          path: AppRoutePaths.dashboard,
          builder: (context, state) => const Text('dashboard-destination'),
        ),
        GoRoute(
          path: AppRoutePaths.teacherMovements,
          builder: (context, state) =>
              const Text('teacher-movements-destination'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<CameraDeviceService>(
            create: (_) => CameraDeviceService(
              httpGet: (_) async =>
                  '{"cameras":[{"device_id":"win32:test-camera","display_name":"External Test Camera","runtime_index":2,"is_active":false,"identity_stable":true}],"preferred_index":1,"fallback_index":0,"active_index":null,"active_device_id":null}',
            ),
          ),
          ChangeNotifierProvider<SessionService>(
            create: (_) => sessionService ?? _TestSessionService(),
          ),
          ChangeNotifierProvider<TraineeProgressionService>(
            create: (_) => TraineeProgressionService.ready(totalXp: 20 * 250),
          ),
          ChangeNotifierProvider<TutorialProgressService>(
            create: (_) => _ReadyTutorials(),
          ),
        ],
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    return practiceKey;
  }

  Future<GlobalKey<LivePracticeScreenState>> pumpPlayground(
    WidgetTester tester,
  ) async {
    final screenKey = GlobalKey<LivePracticeScreenState>();
    final assignments = InMemoryClassroomAssignmentRepository();
    final router = GoRouter(
      initialLocation: AppRoutePaths.livePractice,
      routes: [
        GoRoute(
          path: AppRoutePaths.livePractice,
          builder: (context, state) =>
              LivePracticeScreen(key: screenKey, websocketService: ws),
        ),
        GoRoute(
          path: AppRoutePaths.dashboard,
          builder: (context, state) => const Text('dashboard-destination'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(1400, 900));
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
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    return screenKey;
  }

  testWidgets('idle Movement Practice Back leaves without confirmation', (
    tester,
  ) async {
    await pumpPractice(tester);
    expect(find.text('Quit training?'), findsNothing);
    await tester.tap(_backButton());
    await tester.pumpAndSettle();
    expect(find.text('movements-destination'), findsOneWidget);
    expect(ws.stopCalls, 0);
  });

  testWidgets('movement timeout stops once and opens Game Over summary', (
    tester,
  ) async {
    final sessions = _TestSessionService();
    final screenKey = await pumpPractice(tester, sessionService: sessions);
    final run = screenKey.currentState!.debugRun;

    run.beginPreparing(onTimeout: () {});
    run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
    run.enterCountdown();
    run.enterActive();
    run.debugAdvanceActiveSeconds(60);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(ws.stopCalls, 1);
    expect(run.phase, PracticeRunPhase.completed);
    expect(find.text('GAME OVER'), findsOneWidget);
    expect(find.text("Time's Up · Hand Stall"), findsOneWidget);
    expect(sessions.completedSaveCalls, 1);
    expect(sessions.existingSessionId, 'test-session-id');
    expect(find.text('Session saved'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('teacher preview completion stays in memory', (tester) async {
    final sessions = _TestSessionService();
    final screenKey = await pumpPractice(
      tester,
      sessionService: sessions,
      executionMode: PracticeExecutionMode.teacherPreview,
    );
    final run = screenKey.currentState!.debugRun;

    run.beginPreparing(onTimeout: () {});
    run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
    run.enterCountdown();
    run.enterActive();
    run.debugAdvanceActiveSeconds(60);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(
      find.text('Teacher Preview · This result was not saved'),
      findsOneWidget,
    );
    expect(sessions.reservedSessionIdCalls, 0);
    expect(sessions.completedSaveCalls, 0);
    expect(find.text('Next:'), findsNothing);

    await tester.tap(
      find.widgetWithText(GameActionButton, 'Back to Activity Library'),
    );
    await tester.pumpAndSettle();
    expect(find.text('teacher-movements-destination'), findsOneWidget);
  });

  testWidgets(
    'teacher preview exposes camera source only while idle and prepares saved device',
    (tester) async {
      await pumpPractice(
        tester,
        executionMode: PracticeExecutionMode.teacherPreview,
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('camera-source-preference')),
        findsOneWidget,
      );

      await tester.tap(find.text('Start Camera Setup'));
      await tester.pump();

      expect(ws.prepareCameraDeviceIds, ['win32:test-camera']);
      expect(
        find.byKey(const ValueKey('camera-source-preference')),
        findsNothing,
      );
      ws.acceptPrepare();
      await tester.pump();
    },
  );

  testWidgets(
    'timeout while quit dialog is open completes after Keep Training',
    (tester) async {
      final screenKey = await pumpPractice(tester);
      final run = screenKey.currentState!.debugRun;

      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterCountdown();
      run.enterActive();
      run.debugAdvanceActiveSeconds(59);
      await tester.pump();

      await tester.tap(_backButton());
      await _pumpUi(tester);
      expect(find.text('Quit training?'), findsOneWidget);

      run.debugAdvanceActiveSeconds(1);
      await tester.pump();
      expect(run.phase, PracticeRunPhase.completed);
      expect(ws.stopCalls, 0);

      await tester.tap(find.byKey(const ValueKey('training-quit-keep')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      expect(ws.stopCalls, 1);
      expect(find.text('GAME OVER'), findsOneWidget);
      expect(find.text("Time's Up · Hand Stall"), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'keyboard Back on idle Movement Practice leaves without confirmation or save',
    (tester) async {
      await pumpPractice(tester);
      final backIcon = find.descendant(
        of: _backButton(),
        matching: find.byIcon(FluentIcons.chrome_back),
      );
      expect(backIcon, findsOneWidget);
      Focus.of(tester.element(backIcon)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('movements-destination'), findsOneWidget);
      expect(find.text('Quit training?'), findsNothing);
      expect(ws.stopCalls, 0);
    },
  );

  testWidgets(
    'started Movement Practice Back confirms, keep leaves session intact',
    (tester) async {
      await pumpPractice(tester);
      final state = tester.state<PracticeScreenState>(
        find.byType(PracticeScreen),
      );
      await tester.tap(find.text('Start Camera Setup'));
      await tester.pump();
      expect(state.debugRun.phase, PracticeRunPhase.preparingCamera);
      await tester.tap(_backButton());
      await _pumpUi(tester);
      expect(find.text('Quit training?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('training-quit-keep')));
      await _pumpUi(tester);
      expect(find.text('Quit training?'), findsNothing);
      expect(state.debugRun.phase, PracticeRunPhase.preparingCamera);
      expect(find.byType(PracticeScreen), findsOneWidget);
      expect(ws.stopCalls, 0);
    },
  );

  testWidgets(
    'confirming Movement Practice quit stops once and navigates once',
    (tester) async {
      await pumpPractice(tester);
      await tester.tap(find.text('Start Camera Setup'));
      await tester.pump();
      await tester.tap(_backButton());
      await _pumpUi(tester);
      final confirm = find.byKey(const ValueKey('training-quit-confirm'));
      await tester.tap(confirm);
      await _pumpUi(tester);
      expect(find.text('movements-destination'), findsOneWidget);
      expect(ws.stopCalls, 1);
      expect(find.text('Quit training?'), findsNothing);
    },
  );

  testWidgets('Finish Session does not open the quit dialog', (tester) async {
    await pumpPractice(tester);
    final state = tester.state<PracticeScreenState>(
      find.byType(PracticeScreen),
    );
    state.debugRun.beginPreparing(onTimeout: () {});
    state.debugRun.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
    state.debugRun.enterCountdown();
    state.debugRun.enterActive();
    await tester.pump();
    expect(find.text('Finish Session'), findsOneWidget);
    await tester.tap(find.text('Finish Session'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Quit training?'), findsNothing);
  });

  testWidgets('Cancel during camera setup uses the same confirmation guard', (
    tester,
  ) async {
    await pumpPractice(tester);
    final state = tester.state<PracticeScreenState>(
      find.byType(PracticeScreen),
    );
    await tester.tap(find.text('Start Camera Setup'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await _pumpUi(tester);
    expect(find.text('Quit training?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('training-quit-keep')));
    await _pumpUi(tester);
    expect(state.debugRun.phase, PracticeRunPhase.preparingCamera);
    expect(find.byType(PracticeScreen), findsOneWidget);
  });

  testWidgets('idle Playground Back leaves without confirmation', (
    tester,
  ) async {
    await pumpPlayground(tester);
    expect(find.text('NO SCORING'), findsOneWidget);
    expect(find.text('PERFECT!'), findsNothing);
    await tester.tap(_backButton());
    await _pumpUi(tester);
    expect(find.text('Quit Playground?'), findsNothing);
    expect(find.text('dashboard-destination'), findsOneWidget);
    expect(ws.stopCalls, 1);
  });

  testWidgets('active Playground Back uses the same confirmation guard', (
    tester,
  ) async {
    final screenKey = await pumpPlayground(tester);
    screenKey.currentState!.debugStartSession();
    await tester.pump();
    await tester.pump();
    expect(
      screenKey.currentState!.debugFreestyle.phase,
      isNot(FreestyleSessionPhase.idle),
    );
    await tester.tap(_backButton());
    await _pumpUi(tester);
    expect(find.text('Quit Playground?'), findsOneWidget);
    expect(find.text('PERFECT!'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('training-quit-keep')));
    await _pumpUi(tester);
    expect(find.byType(LivePracticeScreen), findsOneWidget);
    expect(
      screenKey.currentState!.debugFreestyle.phase,
      isNot(FreestyleSessionPhase.idle),
    );

    await tester.tap(_backButton());
    await _pumpUi(tester);
    await tester.tap(find.byKey(const ValueKey('training-quit-confirm')));
    await _pumpUi(tester);
    expect(find.text('dashboard-destination'), findsOneWidget);
    expect(ws.stopCalls, 1);
  });
}
