import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/features/teacher/movements/teacher_live_test_controller.dart';
import 'package:elixr_application/features/teacher/movements/teacher_live_test_screen.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movement_builder_draft.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _ScreenWebSocket extends WebSocketService {
  _ScreenWebSocket();

  final WebSocketConnectionState _state = WebSocketConnectionState.connected;
  int stopCalls = 0;
  int startCalls = 0;

  @override
  WebSocketConnectionState get connectionState => _state;

  @override
  bool get isConnected => _state == WebSocketConnectionState.connected;

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
    WebSocketSessionPurpose sessionPurpose = WebSocketSessionPurpose.official,
    AssessmentSpec? assessmentSpec,
  }) {
    return Future.value(
      CommandAck(
        protocolVersion: 1,
        requestId: 'prepare',
        action: 'prepare',
        accepted: true,
        sessionId: currentSessionId,
      ),
    );
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
    return Future.value(
      const CommandAck(
        protocolVersion: 1,
        requestId: 'start',
        action: 'start',
        accepted: false,
      ),
    );
  }

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) {
    stopCalls += 1;
    return Future.value(
      const CommandAck(
        protocolVersion: 1,
        requestId: 'stop',
        action: 'stop',
        accepted: true,
      ),
    );
  }
}

class _TestSettings extends SettingsService {
  @override
  Future<String?> loadSelectedCameraDeviceId() async => 'win32:teacher-cam';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ScreenWebSocket ws;
  late TeacherLiveTestController controller;
  late _TestSettings settings;

  const draft = TeacherLiveTestDraft(
    title: 'Classroom Wrist Stall',
    instructions: 'Balance the bottle.',
    assessmentSpec: AssessmentSpec(laterality: AssessmentLaterality.left),
  );

  setUp(() {
    ws = _ScreenWebSocket();
    settings = _TestSettings();
    controller = TeacherLiveTestController(
      draft: draft,
      websocket: ws,
      loadCameraDeviceId: () async => 'win32:teacher-cam',
    );
  });

  tearDown(() {
    controller.dispose();
    ws.dispose();
    settings.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: FluentApp(
          theme: AppTheme.dark,
          home: TeacherLiveTestScreen(draft: draft, controller: controller),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows Wrist Stall draft, laterality, and Bottle', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Classroom Wrist Stall'), findsWidgets);
    expect(find.text('Wrist Stall'), findsWidgets);
    expect(find.textContaining('Left wrist'), findsWidgets);
    expect(find.textContaining('Bottle'), findsWidgets);
    expect(find.text('Start Live Test'), findsOneWidget);
    expect(find.textContaining('Just Dance'), findsNothing);
    expect(find.textContaining('XP'), findsNothing);
    expect(find.textContaining('Free Practice'), findsNothing);
    expect(ws.startCalls, 0);
  });

  testWidgets('renders rubric total, performance level, and success', (
    tester,
  ) async {
    await pumpScreen(tester);

    controller.debugForceActive();
    controller.debugApplyFeedback(
      PracticeFeedback(
        bottleDetected: true,
        movement: kTemplateAssessmentMovement,
        feedback: 'Keep the bottle still on the wrist.',
        feedbackType: 'warning',
        postureStatus: 'unstable',
        sessionState: 'active',
        holdProgress: 0.55,
        holdConfirmed: false,
        assessment: const RubricAssessment(
          technique: 3,
          stability: 3,
          completion: 3,
          propPositioning: 3,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('12 / 12'), findsWidgets);
    expect(find.text('Mastered'), findsWidgets);
    expect(find.text('Hold progress'), findsOneWidget);
    expect(find.textContaining('Keep the bottle still'), findsWidgets);

    controller.debugApplyFeedback(
      PracticeFeedback(
        bottleDetected: true,
        movement: kTemplateAssessmentMovement,
        feedback: 'Wrist Stall detected successfully',
        feedbackType: 'positive',
        postureStatus: 'stable',
        sessionState: 'active',
        holdProgress: 1,
        holdConfirmed: true,
        assessment: const RubricAssessment(
          technique: 3,
          stability: 3,
          completion: 3,
          propPositioning: 3,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Wrist Stall detected successfully'), findsOneWidget);
    expect(find.text('Test again'), findsOneWidget);
    expect(find.textContaining('not saved'), findsOneWidget);
  });

  testWidgets('leaving the screen stops the backend session', (tester) async {
    await pumpScreen(tester);
    await controller.startSession();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('live-test-close')));
    await tester.pumpAndSettle();

    expect(ws.stopCalls, greaterThanOrEqualTo(1));
    expect(ws.startCalls, 0);
  });
}
