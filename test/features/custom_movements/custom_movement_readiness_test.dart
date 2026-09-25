import 'dart:async';
import 'dart:typed_data';

import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/features/custom_movements/custom_movement_practice_screen.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> _oneHandTemplateMap() => {
  'schema_version': 1,
  'capture_version': 1,
  'duration_ms': 900,
  'reference_count': 3,
  'required_modalities': ['hands', 'prop_translation'],
  'normalization_metadata': {
    'anchor': 'shoulder_midpoint',
    'scale': 'shoulder_width',
    'mirrored': false,
  },
  'feature_capabilities': {
    'pose': false,
    'hands': true,
    'prop_translation': true,
    'release_catch': false,
    'prop_rotation': false,
    'left_hand': true,
    'right_hand': false,
  },
  'canonical_sequence': [
    {'timestamp_ms': 0, 'pose': <String, dynamic>{}},
    {'timestamp_ms': 900, 'pose': <String, dynamic>{}},
  ],
  'variability_metadata': {'duration_std_ms': 0.0},
  'prop_events': <Map<String, dynamic>>[],
};

CommandAck _ack(
  String action, {
  int? referenceCount,
  bool accepted = true,
  String? errorCode,
  Map<String, dynamic>? customAssessment,
}) => CommandAck(
  protocolVersion: 1,
  requestId: 'req-$action',
  action: action,
  accepted: accepted,
  sessionId: 'session-test',
  sessionState: action == 'stop' ? 'idle' : 'active',
  referenceCount: referenceCount,
  movementTemplate: action == 'build_custom_template'
      ? _oneHandTemplateMap()
      : null,
  errorCode: accepted ? null : (errorCode ?? 'missing_modality'),
  customAssessment: customAssessment,
);

class _CustomSocket extends WebSocketService {
  final _previews = StreamController<PreviewFrame>.broadcast(sync: true);
  final _feedback = StreamController<PracticeFeedback>.broadcast(sync: true);

  TeacherActivityReadinessSpec? preparedReadiness;
  String? preparedMode;
  String? preparedCameraDeviceId;
  final List<String?> preparedCameraDeviceIds = [];
  int stopCalls = 0;
  int? preparedLegacyCameraIndex;
  int acceptedReferences = 0;
  int discardCalls = 0;
  int buildCalls = 0;
  int startCustomCaptureCalls = 0;
  bool rejectStartCustomCapture = false;
  int finishCustomAssessmentCalls = 0;
  Completer<CommandAck>? finishAssessmentCompleter;
  bool rejectNextStop = false;
  String? rejectNextStopCode;
  bool rejectNextSessionStop = false;
  bool rejectPrepare = false;

  @override
  bool get isConnected => true;

  @override
  WebSocketConnectionState get connectionState =>
      WebSocketConnectionState.connected;

  @override
  Stream<PreviewFrame> get previewStream => _previews.stream;

  @override
  Stream<PracticeFeedback> get feedbackStream => _feedback.stream;

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
    Map<String, dynamic>? customMovementTemplate,
  }) async {
    preparedReadiness = readinessSpec;
    preparedMode = sessionMode;
    preparedCameraDeviceId = cameraDeviceId;
    preparedCameraDeviceIds.add(cameraDeviceId);
    preparedLegacyCameraIndex = legacyCameraIndex;
    return _ack('prepare', accepted: !rejectPrepare);
  }

  @override
  Future<CommandAck> sendBeginReadiness({String? sessionId}) async =>
      _ack('begin_readiness');

  @override
  Future<CommandAck> sendConfirmReadiness({String? sessionId}) async =>
      _ack('confirm_readiness');

  @override
  Future<CommandAck> sendActivate({String? sessionId}) async =>
      _ack('activate');

  @override
  Future<CommandAck> sendStartCustomCapture({
    String? sessionId,
    int durationSeconds = 15,
  }) async {
    startCustomCaptureCalls += 1;
    return _ack(
      'start_custom_capture',
      accepted: !rejectStartCustomCapture,
      errorCode: rejectStartCustomCapture
          ? 'custom_capture_not_recording'
          : null,
    );
  }

  @override
  Future<CommandAck> sendStopCustomCapture({String? sessionId}) async {
    if (rejectNextStop) {
      rejectNextStop = false;
      final code = rejectNextStopCode;
      rejectNextStopCode = null;
      return _ack(
        'stop_custom_capture',
        accepted: false,
        errorCode: code,
        referenceCount: acceptedReferences,
      );
    }
    acceptedReferences += 1;
    return _ack('stop_custom_capture', referenceCount: acceptedReferences);
  }

  @override
  Future<CommandAck> sendFinishCustomAssessment({String? sessionId}) async {
    finishCustomAssessmentCalls += 1;
    final completer = finishAssessmentCompleter;
    if (completer != null) return completer.future;
    return _ack(
      'finish_custom_assessment',
      customAssessment: {
        'score_percent': 83.3,
        'total': 10,
        'performance_level': 'proficient',
        'component_scores': {'Timing': 3, 'Prop path': 2},
        'feedback': ['Good timing'],
      },
    );
  }

  @override
  Future<CommandAck> sendDiscardCustomReference({String? sessionId}) async {
    discardCalls += 1;
    acceptedReferences -= 1;
    return _ack('discard_custom_reference', referenceCount: acceptedReferences);
  }

  @override
  Future<CommandAck> sendBuildCustomTemplate({String? sessionId}) async {
    buildCalls += 1;
    return _ack('build_custom_template', referenceCount: acceptedReferences);
  }

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) async {
    stopCalls += 1;
    if (rejectNextSessionStop) {
      rejectNextSessionStop = false;
      return _ack('stop', accepted: false);
    }
    return _ack('stop');
  }

  void emitReady() {
    emitReadiness(true);
  }

  void emitReadiness(
    bool readinessStable, {
    bool bottleDetected = true,
    List<ReadinessItemView>? readinessItems,
    bool? readinessComplete,
    double? readinessStableProgress,
  }) {
    emitFeedback(
      bottleDetected: bottleDetected,
      readinessStable: readinessStable,
      readinessItems: readinessItems,
      readinessComplete: readinessComplete,
      readinessStableProgress: readinessStableProgress,
    );
  }

  void emitFeedback({
    required bool bottleDetected,
    bool? readinessStable,
    int? personCount = 1,
    bool? referenceInvalid,
    List<ReadinessItemView>? readinessItems,
    bool? readinessComplete,
    double? readinessStableProgress,
  }) {
    _feedback.add(
      PracticeFeedback(
        bottleDetected: bottleDetected,
        movement: 'Custom Movement',
        feedback: readinessStable == true ? 'Ready.' : 'Getting into position.',
        feedbackType: 'positive',
        postureStatus: 'unknown',
        readinessStable: readinessStable,
        readinessItems: readinessItems,
        readinessComplete: readinessComplete,
        readinessStableProgress: readinessStableProgress,
        personCount: personCount,
        referenceInvalid: referenceInvalid,
      ),
    );
  }

  void emitPresentation({
    String prop = 'missing',
    String? hands,
    String? pose,
  }) {
    _previews.add(
      PreviewFrame(
        jpegBytes: Uint8List(0),
        propPresentationState: prop,
        handsPresentationState: hands,
        posePresentationState: pose,
      ),
    );
  }

  Future<void> closeTestStreams() async {
    await _previews.close();
    await _feedback.close();
  }
}

class _UnusedRepository extends Fake implements CustomMovementRepository {}

class _RecordingRepository extends Fake implements CustomMovementRepository {
  int savePersonalResultCalls = 0;
  bool failNextSave = false;
  double? savedScore;
  String? savedMovementName;
  int? savedDurationSeconds;

  @override
  String allocateSessionId() => 'custom-session';

  @override
  Future<void> savePersonalResult({
    required String ownerUid,
    required String movementId,
    required String revisionId,
    required double totalScore,
    required Map<String, double> componentScores,
    required List<String> feedback,
    required String sessionId,
    required String movementName,
    required String difficulty,
    required TrainingProp propType,
    required int durationSeconds,
    String? referenceImageStoragePath,
  }) async {
    savePersonalResultCalls += 1;
    savedScore = totalScore;
    savedMovementName = movementName;
    savedDurationSeconds = durationSeconds;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('offline');
    }
  }
}

class _TestSettings extends SettingsService {
  _TestSettings({this.deviceId});

  String? deviceId;

  @override
  bool get cameraMirrored => true;

  @override
  int? get pendingLegacyCameraIndex => null;

  @override
  String? get selectedCameraDisplayName =>
      deviceId == null ? null : 'Selected test camera';

  @override
  String? get selectedCameraDeviceId => deviceId;

  @override
  Future<SettingsWriteOutcome> setSelectedCameraDevice(
    String? nextDeviceId, {
    String? displayName,
  }) async {
    deviceId = nextDeviceId;
    notifyListeners();
    return SettingsWriteOutcome.saved;
  }

  @override
  Future<SettingsWriteOutcome> clearCameraSelectionForAutoSelect() =>
      setSelectedCameraDevice(null);

  @override
  Future<String?> loadSelectedCameraDeviceId() async => deviceId;
}

Widget _withSettings(SettingsService settings, Widget child) => MultiProvider(
  providers: [
    ChangeNotifierProvider<SettingsService>.value(value: settings),
    ChangeNotifierProvider<CameraDeviceService>(
      create: (_) => CameraDeviceService(
        httpGet: (_) async =>
            '{"cameras":[{"device_id":"dev-a","display_name":"Camera A","runtime_index":0,"is_active":false,"identity_stable":true},{"device_id":"dev-b","display_name":"Camera B","runtime_index":1,"is_active":false,"identity_stable":true}],"preferred_index":null,"fallback_index":null,"active_index":null,"active_device_id":null}',
      ),
    ),
  ],
  child: FluentApp(home: child),
);

void _useDesktopSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test(
    'reference person count parses safely and affects only semantic equality',
    () {
      PracticeFeedback parse(Map<String, dynamic> extra) =>
          PracticeFeedback.fromJson({
            'movement': 'Custom Movement',
            'feedback': 'Ready',
            ...extra,
          });
      final missing = parse({});
      final zero = parse({'person_count': 0});
      final one = parse({'person_count': 1});
      final two = parse({'person_count': 2});
      expect(missing.personCount, isNull);
      expect([zero.personCount, one.personCount, two.personCount], [0, 1, 2]);
      expect(one.semanticEquals(two), isFalse);
      expect(one.scoredPracticeChromeEquals(two), isTrue);
      final invalid = parse({'person_count': 1, 'reference_invalid': true});
      expect(invalid.referenceInvalid, isTrue);
      expect(one.semanticEquals(invalid), isFalse);
      expect(one.scoredPracticeChromeEquals(invalid), isTrue);
    },
  );

  testWidgets(
    'custom assessment releases its session when capture startup fails',
    (tester) async {
      _useDesktopSurface(tester);
      final socket = _CustomSocket()..rejectStartCustomCapture = true;
      final movement = CustomMovement(
        id: 'movement-start-failure',
        ownerUid: 'trainee-1',
        ownerRole: CustomMovementOwnerRole.trainee,
        name: 'Start failure toss',
        description: 'Follow the saved reference.',
        difficulty: 'Easy',
        propType: TrainingProp.bottle,
        status: CustomMovementStatus.active,
        activeRevisionId: 'revision-start-failure',
      );
      final revision = CustomMovementRevision(
        id: 'revision-start-failure',
        movementId: movement.id,
        ownerUid: movement.ownerUid,
        ownerRole: movement.ownerRole,
        template: MovementTemplate.tryFrom(_oneHandTemplateMap())!,
      );

      await tester.pumpWidget(
        _withSettings(
          _TestSettings(),
          CustomMovementPracticeScreen(
            movement: movement,
            revision: revision,
            repository: _UnusedRepository(),
            webSocket: socket,
          ),
        ),
      );
      await tester.pump();
      socket.emitReady();
      await tester.pump();

      await tester.tap(find.text('Start Practice'));
      await tester.pump();
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();

      expect(socket.startCustomCaptureCalls, 1);
      expect(socket.stopCalls, 1);
      expect(find.text('Practice Again'), findsOne);
      expect(find.text('Finish Session'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets(
    'custom assessment camera change clears readiness and reprepares',
    (tester) async {
      _useDesktopSurface(tester);
      final socket = _CustomSocket();
      final movement = CustomMovement(
        id: 'movement-switch',
        ownerUid: 'trainee-1',
        ownerRole: CustomMovementOwnerRole.trainee,
        name: 'Camera switch movement',
        description: 'Follow the saved reference.',
        difficulty: 'Easy',
        propType: TrainingProp.bottle,
        status: CustomMovementStatus.active,
        activeRevisionId: 'revision-switch',
      );
      final revision = CustomMovementRevision(
        id: 'revision-switch',
        movementId: movement.id,
        ownerUid: movement.ownerUid,
        ownerRole: movement.ownerRole,
        template: MovementTemplate.tryFrom(_oneHandTemplateMap())!,
      );
      await tester.pumpWidget(
        _withSettings(
          _TestSettings(deviceId: 'dev-a'),
          CustomMovementPracticeScreen(
            movement: movement,
            revision: revision,
            repository: _UnusedRepository(),
            webSocket: socket,
          ),
        ),
      );
      await tester.pump();
      socket.emitReady();
      socket.emitPresentation(prop: 'confirmed', hands: 'tracking');
      await tester.pump();
      expect(find.text('Bottle detected'), findsOneWidget);

      tester
          .widget<ComboBox<String>>(
            find.byKey(const ValueKey('camera-source-selector')),
          )
          .onChanged!('dev-b');
      await tester.pump();
      await tester.pump();
      expect(socket.stopCalls, 1);
      expect(socket.preparedCameraDeviceIds, ['dev-a', 'dev-b']);
      expect(find.text('Bottle detected'), findsNothing);
      expect(find.text('Start Practice'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets('custom assessment retry waits for accepted camera release', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final socket = _CustomSocket();
    final movement = CustomMovement(
      id: 'movement-stop-retry',
      ownerUid: 'trainee-1',
      ownerRole: CustomMovementOwnerRole.trainee,
      name: 'Stop retry movement',
      description: 'Follow the reference.',
      difficulty: 'Easy',
      propType: TrainingProp.bottle,
      status: CustomMovementStatus.active,
      activeRevisionId: 'revision-stop-retry',
    );
    final revision = CustomMovementRevision(
      id: 'revision-stop-retry',
      movementId: movement.id,
      ownerUid: movement.ownerUid,
      ownerRole: movement.ownerRole,
      template: MovementTemplate.tryFrom(_oneHandTemplateMap())!,
    );
    await tester.pumpWidget(
      _withSettings(
        _TestSettings(deviceId: 'dev-a'),
        CustomMovementPracticeScreen(
          movement: movement,
          revision: revision,
          repository: _UnusedRepository(),
          webSocket: socket,
        ),
      ),
    );
    await tester.pump();

    socket.rejectNextSessionStop = true;
    tester
        .widget<ComboBox<String>>(
          find.byKey(const ValueKey('camera-source-selector')),
        )
        .onChanged!('dev-b');
    await tester.pump();
    await tester.pump();
    expect(socket.preparedCameraDeviceIds, ['dev-a']);
    expect(find.text('Retry Setup'), findsOneWidget);

    socket.rejectNextSessionStop = true;
    await tester.tap(find.text('Retry Setup'));
    await tester.pump();
    expect(socket.preparedCameraDeviceIds, ['dev-a']);

    await tester.tap(find.text('Retry Setup'));
    await tester.pump();
    expect(socket.preparedCameraDeviceIds, ['dev-a', 'dev-b']);
    expect(socket.stopCalls, 3);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets(
    'custom assessment keeps prop detection live across readiness and capture',
    (tester) async {
      _useDesktopSurface(tester);
      final socket = _CustomSocket();
      final repository = _RecordingRepository();
      final template = MovementTemplate.tryFrom(_oneHandTemplateMap())!;
      final movement = CustomMovement(
        id: 'movement-1',
        ownerUid: 'trainee-1',
        ownerRole: CustomMovementOwnerRole.trainee,
        name: 'One-hand toss',
        description: 'Toss and catch with the left hand.',
        difficulty: 'Medium',
        propType: TrainingProp.bottle,
        status: CustomMovementStatus.active,
        activeRevisionId: 'revision-1',
      );
      final revision = CustomMovementRevision(
        id: 'revision-1',
        movementId: movement.id,
        ownerUid: movement.ownerUid,
        ownerRole: movement.ownerRole,
        template: template,
      );

      await tester.pumpWidget(
        _withSettings(
          _TestSettings(deviceId: 'dshow:usb-camera'),
          CustomMovementPracticeScreen(
            movement: movement,
            revision: revision,
            repository: repository,
            webSocket: socket,
          ),
        ),
      );
      await tester.pump();

      expect(socket.preparedMode, 'custom_assessment');
      expect(socket.preparedReadiness!.hands, ActivityHandRequirement.oneHand);
      expect(socket.preparedCameraDeviceId, 'dshow:usb-camera');
      expect(socket.preparedLegacyCameraIndex, isNull);
      expect(socket.preparedReadiness!.body, ActivityBodyRequirement.none);
      expect(
        find.text('Keep the selected prop and the left hand visible.'),
        findsOne,
      );
      expect(find.byKey(const ValueKey('practice-training-header')), findsOne);
      expect(find.byKey(const ValueKey('practice-camera-workspace')), findsOne);
      expect(find.byKey(const ValueKey('practice-session-panel')), findsOne);
      expect(find.text('One-hand toss'), findsWidgets);
      expect(find.text('Medium'), findsWidgets);
      expect(find.text('Bottle'), findsOne);
      expect(find.text('Reference matched'), findsOne);

      socket.emitFeedback(bottleDetected: false, readinessStable: false);
      socket.emitPresentation();
      await tester.pump();
      expect(find.text('Searching for bottle'), findsOne);
      await tester.tap(find.text('Start Practice'));
      await tester.pump();
      expect(socket.startCustomCaptureCalls, 0);

      socket.emitFeedback(bottleDetected: true, readinessStable: false);
      socket.emitPresentation(prop: 'confirmed', hands: 'tracking');
      await tester.pump();
      expect(find.text('Bottle detected'), findsOne);
      expect(find.text('Hand tracking'), findsOne);
      expect(find.text('Body tracking'), findsNothing);
      expect(socket.startCustomCaptureCalls, 0);

      // Feedback remains authoritative for readiness, but a newer preview
      // state owns the tracking words shown beside the rendered JPEG.
      socket.emitPresentation(prop: 'coasted', hands: 'tracking');
      await tester.pump();
      expect(find.text('Tracking bottle'), findsOne);
      socket.emitPresentation();
      await tester.pump();
      expect(find.text('Searching for bottle'), findsOne);
      socket.emitPresentation(prop: 'confirmed', hands: 'tracking');
      await tester.pump();
      expect(find.text('Bottle detected'), findsOne);

      socket.emitReadiness(
        false,
        readinessItems: const [
          ReadinessItemView(
            code: 'camera_frame',
            status: ReadinessItemStatus.ready,
            message: 'Live camera frame received.',
          ),
          ReadinessItemView(
            code: 'prop_detected',
            status: ReadinessItemStatus.ready,
            message: 'Keep the selected prop fully inside the frame.',
          ),
          ReadinessItemView(
            code: 'grip_landmarks_visible',
            status: ReadinessItemStatus.waiting,
            message: 'Keep the full gripping hand visible.',
          ),
        ],
        readinessComplete: false,
        readinessStableProgress: 0.4,
      );
      await tester.pump();
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Selected Prop'), findsOneWidget);
      expect(find.text('Grip Hand'), findsOneWidget);
      expect(find.text('2 of 3 ready'), findsOneWidget);
      expect(find.text('Finish Session'), findsNothing);

      socket.emitReady();
      await tester.pump();
      expect(find.text('Ready to Practice'), findsOne);
      expect(find.text('Start Practice'), findsOne);

      await tester.tap(find.text('Start Practice'));
      await tester.pump();
      expect(find.text('Finish Session'), findsNothing);
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      expect(socket.startCustomCaptureCalls, 1);
      expect(find.text('Recording · 00:30 remaining'), findsOneWidget);
      expect(find.text('Finish Session'), findsOne);

      socket.emitFeedback(bottleDetected: false);
      socket.emitPresentation();
      await tester.pump();
      expect(find.text('Searching for bottle'), findsOne);
      expect(find.text('Finish Session'), findsOne);

      socket.emitFeedback(bottleDetected: true);
      socket.emitPresentation(prop: 'confirmed', hands: 'tracking');
      await tester.pump();
      expect(find.text('Bottle detected'), findsOne);

      socket.rejectNextStop = true;
      socket.rejectNextStopCode = 'track_loss';
      await tester.tap(find.text('Finish Session'));
      await tester.pump();
      expect(
        find.text(
          'Required movement tracking was lost during the recording. Keep the selected prop and required hand or body visible throughout the full movement, then try again.',
        ),
        findsOne,
      );
      expect(
        find.text(
          'The performance could not be assessed. Reposition and retry.',
        ),
        findsNothing,
      );
      await tester.tap(find.text('Practice Again'));
      await tester.pump();
      expect(find.text('Searching for bottle'), findsOne);
      expect(find.text('Bottle detected'), findsNothing);

      expect(repository.savePersonalResultCalls, 0);
      socket.emitReady();
      await tester.pump();
      await tester.tap(find.text('Start Practice'));
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      expect(find.text('Finish Session'), findsOne);
      expect(socket.finishCustomAssessmentCalls, 0);
      expect(repository.savePersonalResultCalls, 0);

      final finishAssessment = Completer<CommandAck>();
      socket.finishAssessmentCompleter = finishAssessment;
      await tester.tap(find.text('Finish Session'));
      await tester.pump();
      expect(socket.finishCustomAssessmentCalls, 1);
      expect(find.text('Finish Session'), findsNothing);
      expect(find.text('Analyzing performance…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('custom-assessment-result')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('practice-primary-action')));
      await tester.pump();
      expect(socket.finishCustomAssessmentCalls, 1);

      finishAssessment.complete(
        _ack(
          'finish_custom_assessment',
          customAssessment: {
            'score_percent': 83.3,
            'total': 10,
            'performance_level': 'proficient',
            'component_scores': {'Timing': 3, 'Prop path': 2},
            'feedback': ['Good timing'],
          },
        ),
      );
      socket.finishAssessmentCompleter = null;
      await tester.pumpAndSettle();
      expect(socket.finishCustomAssessmentCalls, 1);
      expect(repository.savePersonalResultCalls, 1);
      expect(repository.savedScore, 83.3);
      expect(repository.savedMovementName, 'One-hand toss');
      expect(repository.savedDurationSeconds, greaterThanOrEqualTo(0));
      expect(find.byKey(const ValueKey('custom-assessment-result')), findsOne);

      repository.failNextSave = true;
      await tester.tap(find.text('Practice Again'));
      await tester.pump();
      socket.emitReady();
      await tester.pump();
      await tester.tap(find.text('Start Practice'));
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.tap(find.text('Finish Session'));
      await tester.pumpAndSettle();
      expect(repository.savePersonalResultCalls, 2);
      expect(find.byKey(const ValueKey('custom-assessment-result')), findsOne);
      expect(
        find.text(
          'Assessment complete, but the personal result could not be saved.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The performance could not be assessed. Reposition and retry.',
        ),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets('custom assessment uses its route-specific exit callback', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final socket = _CustomSocket();
    final template = MovementTemplate.tryFrom(_oneHandTemplateMap())!;
    final movement = CustomMovement(
      id: 'movement-exit',
      ownerUid: 'trainee-1',
      ownerRole: CustomMovementOwnerRole.trainee,
      name: 'Exit toss',
      description: 'Toss and catch with the left hand.',
      difficulty: 'Medium',
      propType: TrainingProp.bottle,
      status: CustomMovementStatus.active,
      activeRevisionId: 'revision-exit',
    );
    final revision = CustomMovementRevision(
      id: movement.activeRevisionId,
      movementId: movement.id,
      ownerUid: movement.ownerUid,
      ownerRole: movement.ownerRole,
      template: template,
    );
    var exited = false;

    await tester.pumpWidget(
      _withSettings(
        _TestSettings(),
        CustomMovementPracticeScreen(
          movement: movement,
          revision: revision,
          repository: _UnusedRepository(),
          webSocket: socket,
          onExit: () => exited = true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('training-header-back')));

    expect(exited, isTrue);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets(
    'custom assessment uses the selected prop in live detection copy',
    (tester) async {
      _useDesktopSurface(tester);
      final socket = _CustomSocket();
      final template = MovementTemplate.tryFrom(_oneHandTemplateMap())!;
      final movement = CustomMovement(
        id: 'movement-shaker',
        ownerUid: 'trainee-1',
        ownerRole: CustomMovementOwnerRole.trainee,
        name: 'Shaker toss',
        description: 'Toss and catch the shaker.',
        difficulty: 'Medium',
        propType: TrainingProp.shaker,
        status: CustomMovementStatus.active,
        activeRevisionId: 'revision-shaker',
      );
      final revision = CustomMovementRevision(
        id: 'revision-shaker',
        movementId: movement.id,
        ownerUid: movement.ownerUid,
        ownerRole: movement.ownerRole,
        template: template,
      );

      await tester.pumpWidget(
        _withSettings(
          _TestSettings(),
          CustomMovementPracticeScreen(
            movement: movement,
            revision: revision,
            repository: _UnusedRepository(),
            webSocket: socket,
          ),
        ),
      );
      await tester.pump();

      socket.emitFeedback(bottleDetected: false, readinessStable: false);
      socket.emitPresentation();
      await tester.pump();
      expect(find.text('Searching for cocktail shaker'), findsOne);
      socket.emitFeedback(bottleDetected: true, readinessStable: false);
      socket.emitPresentation(prop: 'confirmed', hands: 'tracking');
      await tester.pump();
      expect(find.text('Cocktail Shaker detected'), findsOne);
      expect(find.text('Bottle detected'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );
}
