import 'dart:async';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/practice/freestyle/freestyle_models.dart';
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/features/practice/practice_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/trainee_progression_service.dart';
import 'package:elixr_application/services/tutorial_progress_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
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

  Future<void> pumpPractice(WidgetTester tester) async {
    final practiceKey = GlobalKey<PracticeScreenState>();
    final router = GoRouter(
      initialLocation: AppRoutePaths.practice,
      routes: [
        GoRoute(
          path: AppRoutePaths.practice,
          builder: (context, state) => PracticeScreen(
            key: practiceKey,
            movement: 'Hand Stall',
            difficulty: 'Easy',
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
      ],
    );
    addTearDown(router.dispose);
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<SessionService>(
            create: (_) => SessionService(),
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
