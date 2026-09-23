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
import 'package:elixr_application/features/custom_movements/custom_reference_recorder_dialog.dart';
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

CommandAck _ack(String action, {int? referenceCount, bool accepted = true}) =>
    CommandAck(
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
      errorCode: accepted ? null : 'missing_modality',
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
  bool rejectNextStop = false;
  bool rejectNextSessionStop = false;

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
    return _ack('prepare');
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
    return _ack('start_custom_capture');
  }

  @override
  Future<CommandAck> sendStopCustomCapture({String? sessionId}) async {
    if (rejectNextStop) {
      rejectNextStop = false;
      return _ack('stop_custom_capture', accepted: false);
    }
    acceptedReferences += 1;
    return _ack('stop_custom_capture', referenceCount: acceptedReferences);
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

  void emitReadiness(bool readinessStable, {bool bottleDetected = true}) {
    emitFeedback(
      bottleDetected: bottleDetected,
      readinessStable: readinessStable,
    );
  }

  void emitFeedback({required bool bottleDetected, bool? readinessStable}) {
    _feedback.add(
      PracticeFeedback(
        bottleDetected: bottleDetected,
        movement: 'Custom Movement',
        feedback: readinessStable == true ? 'Ready.' : 'Getting into position.',
        feedbackType: 'positive',
        postureStatus: 'unknown',
        readinessStable: readinessStable,
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

class _TestSettings extends SettingsService {
  _TestSettings({this.deviceId, this.legacyIndex, this.mirrored = true});

  String? deviceId;
  final int? legacyIndex;
  final bool mirrored;

  @override
  bool get cameraMirrored => mirrored;

  @override
  int? get pendingLegacyCameraIndex => legacyIndex;

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
  testWidgets('reference capture readiness is camera and selected prop only', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final socket = _CustomSocket();
    await tester.pumpWidget(
      _withSettings(
        _TestSettings(),
        CustomReferenceRecorderDialog(
          difficulty: 'Medium',
          prop: TrainingProp.bottle,
          webSocket: socket,
        ),
      ),
    );
    await tester.pump();

    expect(socket.preparedMode, 'custom_capture');
    expect(socket.preparedReadiness, isNotNull);
    expect(socket.preparedReadiness!.isCameraOnly, isTrue);
    expect(socket.preparedCameraDeviceId, isNull);
    expect(socket.preparedLegacyCameraIndex, isNull);
    socket.emitPresentation(
      prop: 'confirmed',
      hands: 'tracking',
      pose: 'tracking',
    );
    await tester.pump();
    expect(find.text('Bottle detected'), findsOne);
    expect(find.text('Hand tracking'), findsOne);
    expect(find.text('Body tracking'), findsOne);

    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets('reference camera change stops before one new prepare', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final socket = _CustomSocket();
    final settings = _TestSettings(deviceId: 'dev-a');
    await tester.pumpWidget(
      _withSettings(
        settings,
        CustomReferenceRecorderDialog(
          difficulty: 'Easy',
          prop: TrainingProp.bottle,
          webSocket: socket,
        ),
      ),
    );
    await tester.pump();
    expect(socket.preparedCameraDeviceIds, ['dev-a']);
    expect(
      find.byKey(const ValueKey('camera-source-preference')),
      findsOneWidget,
    );

    final selector = tester.widget<ComboBox<String>>(
      find.byKey(const ValueKey('camera-source-selector')),
    );
    socket.rejectNextSessionStop = true;
    selector.onChanged!('dev-b');
    await tester.pump();
    await tester.pump();
    expect(socket.stopCalls, 1);
    expect(socket.preparedCameraDeviceIds, ['dev-a']);
    expect(find.text('Retry camera setup'), findsOneWidget);

    await tester.tap(find.text('Retry camera setup'));
    await tester.pump();
    expect(socket.stopCalls, 2);
    expect(socket.preparedCameraDeviceIds, ['dev-a', 'dev-b']);

    socket.emitReady();
    await tester.pump();
    await tester.tap(find.text('Record Reference'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('camera-source-preference')),
      findsNothing,
    );
    for (var second = 0; second < 3; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

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
            repository: _UnusedRepository(),
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

      socket.emitReady();
      await tester.pump();
      expect(find.text('Your setup is stable. Start when ready.'), findsOne);
      expect(find.text('Start Practice'), findsOne);

      await tester.tap(find.text('Start Practice'));
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      expect(socket.startCustomCaptureCalls, 1);
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
      await tester.tap(find.text('Finish Session'));
      await tester.pump();
      expect(
        find.text(
          'The performance could not be assessed. Reposition and retry.',
        ),
        findsOne,
      );
      await tester.tap(find.text('Practice Again'));
      await tester.pump();
      expect(find.text('Searching for bottle'), findsOne);
      expect(find.text('Bottle detected'), findsNothing);

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

  testWidgets('three-reference flow supports rejection retry and discard', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final socket = _CustomSocket()..rejectNextStop = true;
    await tester.pumpWidget(
      _withSettings(
        _TestSettings(legacyIndex: 2, mirrored: false),
        CustomReferenceRecorderDialog(
          difficulty: 'Medium',
          prop: TrainingProp.bottle,
          webSocket: socket,
        ),
      ),
    );
    await tester.pump();
    expect(socket.preparedCameraDeviceId, isNull);
    expect(socket.preparedLegacyCameraIndex, 2);
    socket._previews.add(
      PreviewFrame(
        jpegBytes: Uint8List.fromList(const <int>[
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
      ),
    );
    await tester.pump();
    final frame = tester.widget<Transform>(
      find.byKey(const ValueKey('custom-reference-camera-frame')),
    );
    expect(frame.transform.storage[0], 1);
    socket.emitReady();
    await tester.pump();

    Future<void> recordReference() async {
      await tester.tap(find.byKey(const ValueKey('custom-reference-record')));
      await tester.pump();
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('custom-reference-record')));
      await tester.pump();
    }

    await recordReference();
    expect(
      find.text('This reference was not usable. Reposition and retry.'),
      findsOne,
    );

    await recordReference();
    expect(socket.acceptedReferences, 1);
    await tester.tap(find.text('Discard last'));
    await tester.pump();
    expect(socket.discardCalls, 1);
    expect(socket.acceptedReferences, 0);

    await recordReference();
    await recordReference();
    await recordReference();

    expect(socket.acceptedReferences, 3);
    expect(socket.buildCalls, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    await socket.closeTestStreams();
  });

  testWidgets(
    'active recorder starts later references after readiness becomes unstable',
    (tester) async {
      _useDesktopSurface(tester);
      final socket = _CustomSocket();
      await tester.pumpWidget(
        _withSettings(
          _TestSettings(),
          CustomReferenceRecorderDialog(
            difficulty: 'Medium',
            prop: TrainingProp.bottle,
            webSocket: socket,
          ),
        ),
      );
      await tester.pump();
      socket.emitReady();
      await tester.pump();

      Future<void> startReference() async {
        await tester.tap(find.byKey(const ValueKey('custom-reference-record')));
        await tester.pump();
        for (var second = 0; second < 3; second++) {
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.pump();
      }

      Future<void> finishReference() async {
        await tester.tap(find.byKey(const ValueKey('custom-reference-record')));
        await tester.pump();
      }

      await startReference();
      await finishReference();
      expect(socket.acceptedReferences, 1);

      socket.emitReadiness(false);
      await tester.pump();
      expect(find.text('Reference saved — record the next one'), findsOne);
      final recordButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('custom-reference-record')),
      );
      expect(recordButton.onPressed, isNotNull);

      await startReference();
      expect(socket.startCustomCaptureCalls, 2);
      await finishReference();
      expect(socket.acceptedReferences, 2);

      await startReference();
      expect(socket.startCustomCaptureCalls, 3);
      await finishReference();
      expect(socket.acceptedReferences, 3);
      expect(socket.buildCalls, 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      await socket.closeTestStreams();
    },
  );

  testWidgets('reference recorder fits a 1366 by 768 desktop surface', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final socket = _CustomSocket();
    await tester.pumpWidget(
      _withSettings(
        _TestSettings(),
        CustomReferenceRecorderDialog(
          difficulty: 'Medium',
          prop: TrainingProp.bottle,
          webSocket: socket,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Record movement references'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('custom-reference-record')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });
}
