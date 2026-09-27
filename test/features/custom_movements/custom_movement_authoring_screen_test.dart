import 'dart:async';
import 'dart:convert';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/core/widgets/elixr_video_player.dart';
import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/features/custom_movements/custom_movement_authoring_screen.dart';
import 'package:elixr_application/features/custom_movements/widgets/authoring_wizard_widgets.dart';
import 'package:elixr_application/features/settings/widgets/camera_source_preference.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Map<String, dynamic> _templateMap(int count) => {
  'schema_version': 1,
  'capture_version': 1,
  'duration_ms': 1000,
  'reference_count': count,
  'required_modalities': ['prop_translation'],
  'normalization_metadata': {
    'anchor': 'shoulder_midpoint',
    'scale': 'shoulder_width',
    'mirrored': false,
  },
  'feature_capabilities': {
    'pose': false,
    'hands': false,
    'prop_translation': true,
    'release_catch': false,
    'prop_rotation': false,
  },
  'canonical_sequence': [
    {'timestamp_ms': 0, 'pose': <String, dynamic>{}},
    {'timestamp_ms': 1000, 'pose': <String, dynamic>{}},
  ],
  'variability_metadata': {'duration_std_ms': 0.0},
  'prop_events': <Map<String, dynamic>>[],
};

Map<String, dynamic> _rotationTemplateMap() => _templateMap(3)
  ..['schema_version'] = 2
  ..['canonical_sequence'] = List.generate(
    32,
    (index) => {
      'timestamp_ms': index * 30,
      'pose': <String, dynamic>{},
      'hands': <String, dynamic>{},
      'prop': {'x': 0.5, 'y': 0.5, 'confidence': 0.9},
      'prop_metadata': <String, dynamic>{},
    },
  )
  ..['feature_capabilities'] = {
    'pose': false,
    'hands': false,
    'prop_translation': true,
    'release_catch': false,
    'prop_rotation': true,
  }
  ..['rotation_trace'] = {
    'angles_rad': List.generate(32, (index) => index * 0.2),
    'total_signed_rad': 6.2,
    'coverage': 0.95,
    'pair_coverage': 0.9,
  };

CustomMovement _movement(CustomMovementOwnerRole role) => CustomMovement(
  id: 'movement-1',
  ownerUid: 'owner-1',
  ownerRole: role,
  name: 'Cascade',
  description: 'A complete movement.',
  difficulty: 'Easy',
  propType: TrainingProp.bottle,
  status: CustomMovementStatus.active,
  activeRevisionId: 'revision-1',
);

class _Repository extends Fake implements CustomMovementRepository {
  CustomMovement? saved;
  MovementTemplate? savedTemplate;
  CustomMovementSaveException? saveFailure;
  int saveCalls = 0;

  @override
  Future<CustomMovement> createMovement({
    required String ownerUid,
    required CustomMovementOwnerRole ownerRole,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
    Uint8List? referenceImageJpegBytes,
  }) async {
    saveCalls++;
    if (saveFailure case final failure?) throw failure;
    expect(
      template.referenceCount,
      greaterThanOrEqualTo(
        MovementTemplate.minimumReferencesFor(template.movementBehavior),
      ),
    );
    savedTemplate = template;
    return saved = _movement(ownerRole);
  }

  @override
  Future<CustomMovement> publishRevision({
    required CustomMovement current,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
    Uint8List? referenceImageJpegBytes,
  }) async {
    saveCalls++;
    if (saveFailure case final failure?) throw failure;
    return saved = current;
  }
}

class _Socket extends Fake implements WebSocketService {
  final StreamController<PreviewFrame> previews = StreamController.broadcast();
  final StreamController<PracticeFeedback> feedback =
      StreamController.broadcast();
  int count = 0;
  final List<String> deleted = [];
  final List<String> trimmed = [];
  final List<String> commandOrder = [];
  final List<(String, int, int)> trimRanges = [];
  final Map<String, (int, int)> committedTrims = {};
  bool rejectNextTrim = false;
  bool rejectNextPrepare = false;
  bool rejectNextStartCapture = false;
  String? rejectBuildCode;
  String? rejectBuildMessage;
  Map<String, dynamic>? rejectBuildQuality;
  String? rejectNextStopCode;
  Map<String, dynamic>? rejectNextStopQuality;
  String? builtBehavior;
  int buildCalls = 0;
  bool rejectNextReference = false;
  bool failDisconnect = false;
  final List<String?> preparedCameraIds = [];
  final List<TrainingProp> preparedProps = [];
  Completer<void>? prepareGate;
  int stopCalls = 0;
  int startCustomCaptureCalls = 0;
  int stopCustomCaptureCalls = 0;
  int? lastCaptureDurationSeconds;
  Completer<void>? stopReferenceCompleter;
  String? preparedMode;
  TeacherActivityReadinessSpec? preparedReadiness;
  Map<String, dynamic>? templateOverride;

  CommandAck _ack(
    String action, {
    String? id,
    int? start,
    int? end,
    Map<String, dynamic>? template,
    Map<String, dynamic>? quality,
  }) => CommandAck(
    protocolVersion: 1,
    requestId: 'request-$action',
    sessionId: 'session-1',
    action: action,
    accepted: true,
    referenceCount: count,
    referenceId: id,
    localFilePath: id == null ? null : 'C:/temp/$id.mp4',
    videoDurationMs: id == null ? null : 7000,
    trimStartMs: start,
    trimEndMs: end,
    movementTemplate: template,
    referenceQuality: quality,
  );

  CommandAck _rejected(String action, String code) => CommandAck(
    protocolVersion: 1,
    requestId: 'request-$action',
    sessionId: 'session-1',
    action: action,
    accepted: false,
    errorCode: code,
  );

  void ready({
    int personCount = 1,
    bool readinessStable = true,
    bool handsVisible = true,
    bool upperBodyVisible = true,
    bool propVisible = true,
  }) {
    previews.add(
      PreviewFrame(
        jpegBytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAC0lEQVR4nGNgQAYAAA4AAamRc7EAAAAASUVORK5CYII=',
        ),
        propPresentationState: 'confirmed',
        handsPresentationState: handsVisible ? 'tracking' : 'missing',
        posePresentationState: 'tracking',
      ),
    );
    feedback.add(
      PracticeFeedback(
        bottleDetected: true,
        movement: 'Custom Movement',
        feedback: 'Ready',
        feedbackType: 'positive',
        postureStatus: 'correct',
        readinessStable: readinessStable,
        personCount: personCount,
        capturePropVisible: propVisible,
        captureHandsVisible: handsVisible,
        captureUpperBodyVisible: upperBodyVisible,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final method = invocation.memberName;
    if (method == #previewStream) return previews.stream;
    if (method == #feedbackStream) return feedback.stream;
    if (method == #isConnected) return true;
    if (method == #beginPracticeAttempt) return 'session-1';
    if (method == #connect || method == #disconnect) {
      if (method == #disconnect && failDisconnect) {
        return Future<void>.error(StateError('private teardown detail'));
      }
      return Future<void>.value();
    }
    if (method == #dispose) return null;
    if (method == #sendPrepare) {
      preparedCameraIds.add(
        invocation.namedArguments[#cameraDeviceId] as String?,
      );
      preparedMode = invocation.namedArguments[#sessionMode] as String?;
      preparedReadiness =
          invocation.namedArguments[#readinessSpec]
              as TeacherActivityReadinessSpec?;
      if (rejectNextPrepare) {
        rejectNextPrepare = false;
        return Future<CommandAck>.value(
          _rejected('prepare', 'camera_unavailable'),
        );
      }
      preparedProps.add(invocation.namedArguments[#prop] as TrainingProp);
      final gate = prepareGate;
      if (gate != null) return gate.future.then((_) => _ack('prepare'));
      return Future<CommandAck>.value(_ack('prepare'));
    }
    if (method == #stopPracticeSession) {
      stopCalls++;
      return Future<CommandAck>.value(_ack('stop'));
    }
    if (method == #sendStartCustomCapture) {
      startCustomCaptureCalls++;
      lastCaptureDurationSeconds =
          invocation.namedArguments[#durationSeconds] as int?;
      if (rejectNextStartCapture) {
        rejectNextStartCapture = false;
        return Future<CommandAck>.value(
          _rejected('start_custom_capture', 'readiness_not_stable'),
        );
      }
      return Future<CommandAck>.value(_ack('$method'));
    }
    if (method == #sendBeginReadiness ||
        method == #sendConfirmReadiness ||
        method == #sendActivate) {
      return Future<CommandAck>.value(_ack('$method'));
    }
    if (method == #sendStopCustomCapture) {
      stopCustomCaptureCalls++;
      final stopCompleter = stopReferenceCompleter;
      if (stopCompleter != null) {
        return stopCompleter.future.then((_) {
          count++;
          return _ack(
            'stop_custom_capture',
            id: 'reference-$count',
            start: 0,
            end: 7000,
            quality: {
              'left_hand_coverage': 0.25,
              'right_hand_coverage': 0.1,
              'pose_coverage': 0.8,
            },
          );
        });
      }
      if (rejectNextReference) {
        rejectNextReference = false;
        return Future<CommandAck>.value(
          _rejected('stop_custom_capture', 'multiple_people_detected'),
        );
      }
      if (rejectNextStopCode case final code?) {
        rejectNextStopCode = null;
        return Future<CommandAck>.value(
          CommandAck(
            protocolVersion: 1,
            requestId: 'request-stop_custom_capture',
            sessionId: 'session-1',
            action: 'stop_custom_capture',
            accepted: false,
            errorCode: code,
            referenceQuality: rejectNextStopQuality,
          ),
        );
      }
      count++;
      committedTrims['reference-$count'] = (0, 7000);
      return Future<CommandAck>.value(
        _ack(
          'stop_custom_capture',
          id: 'reference-$count',
          start: 0,
          end: 7000,
          quality: {
            'left_hand_coverage': 0.25,
            'right_hand_coverage': 0.1,
            'pose_coverage': 0.8,
          },
        ),
      );
    }
    if (method == #sendDeleteCustomReference) {
      final id = invocation.positionalArguments.first as String;
      deleted.add(id);
      count--;
      return Future<CommandAck>.value(_ack('delete_custom_reference', id: id));
    }
    if (method == #sendTrimCustomReference) {
      final id = invocation.positionalArguments.first as String;
      trimmed.add(id);
      final start = invocation.namedArguments[#startMs] as int;
      final end = invocation.namedArguments[#endMs] as int;
      trimRanges.add((id, start, end));
      commandOrder.add('trim');
      if (rejectNextTrim) {
        rejectNextTrim = false;
        return Future<CommandAck>.value(
          _rejected('trim_custom_reference', 'insufficient_frames'),
        );
      }
      committedTrims[id] = (start, end);
      return Future<CommandAck>.value(
        _ack('trim_custom_reference', id: id, start: start, end: end),
      );
    }
    if (method == #sendBuildCustomTemplate) {
      buildCalls++;
      builtBehavior = invocation.namedArguments[#movementBehavior] as String?;
      commandOrder.add('build');
      if (rejectBuildCode case final code?) {
        return Future<CommandAck>.value(
          CommandAck(
            protocolVersion: 1,
            requestId: 'request-build_custom_template',
            sessionId: 'session-1',
            action: 'build_custom_template',
            accepted: false,
            errorCode: code,
            message: rejectBuildMessage,
            referenceQuality: rejectBuildQuality,
          ),
        );
      }
      return Future<CommandAck>.value(
        _ack(
          'build_custom_template',
          template: templateOverride ?? _templateMap(count),
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }

  Future<void> close() async {
    await previews.close();
    await feedback.close();
  }
}

class _Settings extends SettingsService {
  _Settings({this.deviceId});

  String? deviceId;

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
  Future<String?> loadSelectedCameraDeviceId() async => deviceId;
}

Widget _host({
  required _Repository repository,
  required _Socket socket,
  CustomMovement? existing,
  CustomMovementRevision? revision,
  CustomMovementOwnerRole role = CustomMovementOwnerRole.trainee,
  _Settings? settingsOverride,
  FluentThemeData? theme,
  List<Uri>? cameraRequests,
}) {
  final settings = settingsOverride ?? _Settings();
  final cameras = CameraDeviceService(
    httpGet: (uri) async {
      cameraRequests?.add(uri);
      return '{"cameras":[{"device_id":"dev-a","display_name":"Camera A","runtime_index":0,"is_active":false,"identity_stable":true},{"device_id":"dev-b","display_name":"Camera B","runtime_index":1,"is_active":false,"identity_stable":true}]}';
    },
  );
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      ChangeNotifierProvider<CameraDeviceService>.value(value: cameras),
    ],
    child: FluentApp(
      theme: theme ?? AppTheme.dark,
      home: CustomMovementAuthoringScreen(
        ownerUid: 'owner-1',
        ownerRole: role,
        repository: repository,
        existing: existing,
        existingRevision: revision,
        webSocket: socket,
      ),
    ),
  );
}

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

final _recordButton = find.byKey(const ValueKey('custom-reference-record'));
final _reviewButton = find.byKey(const ValueKey('custom-movement-review'));
final _saveButton = find.byKey(const ValueKey('custom-movement-save'));
final _backButton = find.byKey(const ValueKey('custom-movement-back'));

VoidCallback? _onPressed(WidgetTester tester, Finder finder) =>
    tester.widget<ElixPrimaryButton>(finder).onPressed;

AuthoringCheckState _pillState(WidgetTester tester, String key) =>
    tester.widget<AuthoringStatusPill>(find.byKey(ValueKey(key))).state;

Future<void> _tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _record(WidgetTester tester, _Socket socket) async {
  await _startReferenceRecording(tester, socket);
  await tester.tap(_recordButton);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _startReferenceRecording(
  WidgetTester tester,
  _Socket socket,
) async {
  await tester.ensureVisible(_recordButton);
  socket.ready();
  await tester.pump();
  await tester.tap(_recordButton);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
  expect(find.text('Stop & save example'), findsOneWidget);
  expect(find.text('REC'), findsOneWidget);
  expect(find.text('00:15 remaining'), findsOneWidget);
  expect(socket.lastCaptureDurationSeconds, 15);
}

Future<void> _fillDetails(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('custom-movement-name')),
    'Bottle Loop',
  );
  await tester.enterText(
    find.byKey(const ValueKey('custom-movement-description')),
    'Hold the bottle, loop it once, then catch it.',
  );
}

Future<void> _continueToRecording(WidgetTester tester) async {
  final next = find.byKey(const ValueKey('custom-movement-next'));
  await tester.ensureVisible(next);
  await tester.tap(next);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _waitUntilRecordable(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (_onPressed(tester, _recordButton) != null) break;
  }
  expect(_onPressed(tester, _recordButton), isNotNull);
}

Future<void> _enterReferenceStudio(WidgetTester tester, _Socket socket) async {
  await _fillDetails(tester);
  await _continueToRecording(tester);
  socket.ready();
  await tester.pump();
  await _waitUntilRecordable(tester);
}

Future<void> _recordTwoReferences(WidgetTester tester, _Socket socket) async {
  await _enterReferenceStudio(tester, socket);
  await _record(tester, socket);
  await _record(tester, socket);
}

/// Moves the start handle with the keyboard (100 ms per arrow press).
Future<void> _nudgeTrimStart(WidgetTester tester, int steps) async {
  final handle = find.byKey(const ValueKey('trim-start-handle'));
  await tester.ensureVisible(handle);
  await tester.tap(handle);
  await tester.pump();
  for (var index = 0; index < steps.abs(); index++) {
    await tester.sendKeyEvent(
      steps > 0 ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft,
    );
  }
  await tester.pump();
}

Future<void> _tapReview(WidgetTester tester) async {
  await tester.ensureVisible(_reviewButton);
  await tester.tap(_reviewButton);
  await tester.pump(const Duration(milliseconds: 100));
}

void _expectFullyVisible(WidgetTester tester, Finder finder, Size viewport) {
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(0), reason: '$finder top');
  expect(rect.bottom, lessThanOrEqualTo(viewport.height), reason: '$finder');
  expect(rect.right, lessThanOrEqualTo(viewport.width), reason: '$finder');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('wizard exposes exactly three labelled steps', (tester) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));

    for (var index = 0; index < 3; index++) {
      expect(find.byKey(ValueKey('authoring-step-$index')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('authoring-step-3')), findsNothing);
    expect(find.text('Set up'), findsOneWidget);
    expect(find.text('Record examples'), findsOneWidget);
    expect(find.text('Review & save'), findsOneWidget);
    expect(find.text('Continue to recording'), findsOneWidget);
    expect(_backButton, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'entering Step 2 prepares once without a competing camera discovery scan',
    (tester) async {
      _useViewport(tester, const Size(1366, 768));
      final socket = _Socket();
      addTearDown(socket.close);
      final cameraRequests = <Uri>[];
      await tester.pumpWidget(
        _host(
          repository: _Repository(),
          socket: socket,
          settingsOverride: _Settings(deviceId: 'dev-a'),
          cameraRequests: cameraRequests,
        ),
      );
      await _fillDetails(tester);
      await _continueToRecording(tester);
      await tester.pump(const Duration(milliseconds: 200));

      expect(socket.preparedCameraIds, ['dev-a']);
      expect(cameraRequests, isEmpty);
      expect(
        tester
            .widget<CameraSourcePreference>(find.byType(CameraSourcePreference))
            .refreshOnMount,
        isFalse,
      );

      // Leaving and re-entering Step 2 keeps the one prepared session.
      await tester.tap(_backButton);
      await tester.pump(const Duration(milliseconds: 200));
      await _continueToRecording(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(socket.preparedCameraIds, ['dev-a']);
      expect(cameraRequests, isEmpty);

      // Only the explicit Refresh action enumerates cameras.
      await tester.tap(find.byKey(const ValueKey('camera-source-refresh')));
      await tester.pump();
      await tester.pump();
      expect(cameraRequests, hasLength(1));
      expect(cameraRequests.single.queryParameters['force_refresh'], 'true');
      expect(socket.preparedCameraIds, ['dev-a']);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'camera shows an intentional loading state until the first JPEG',
    (tester) async {
      _useViewport(tester, const Size(1366, 768));
      final socket = _Socket();
      addTearDown(socket.close);
      await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
      await _fillDetails(tester);
      await _continueToRecording(tester);

      final placeholder = find.byKey(
        const ValueKey('custom-camera-placeholder'),
      );
      expect(placeholder, findsOneWidget);
      expect(find.text('Starting camera…'), findsOneWidget);
      expect(find.text('Auto-select camera'), findsOneWidget);
      expect(
        find.text('This may take a moment while ELIXR checks the camera.'),
        findsOneWidget,
      );
      expect(_onPressed(tester, _recordButton), isNull);
      final sizeBefore = tester.getSize(find.byType(AspectRatio).first);

      socket.ready();
      await tester.pump();
      expect(placeholder, findsNothing);
      expect(find.text('Starting camera…'), findsNothing);
      expect(find.text('LIVE'), findsOneWidget);
      expect(tester.getSize(find.byType(AspectRatio).first), sizeBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('camera preparation failure offers a real retry', (tester) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket()..rejectNextPrepare = true;
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _fillDetails(tester);
    await _continueToRecording(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Camera could not start'), findsOneWidget);
    expect(find.text('Starting camera…'), findsNothing);
    expect(socket.preparedCameraIds, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('custom-camera-retry')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(socket.preparedCameraIds, hasLength(2));
    expect(find.text('Camera could not start'), findsNothing);
    expect(find.text('Starting camera…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('countdown and recording state are prominent and accurate', (
    tester,
  ) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    expect(find.text('Record example 1'), findsOneWidget);
    expect(find.text('0 of 2 required · Up to 5 examples'), findsOneWidget);

    Finder countdown(String value) => find.descendant(
      of: find.byKey(const ValueKey('custom-recording-countdown')),
      matching: find.text(value),
    );
    await tester.tap(_recordButton);
    await tester.pump();
    expect(find.text('Recording starts in'), findsOneWidget);
    expect(countdown('3'), findsOneWidget);
    expect(find.text('REC'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(countdown('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(countdown('1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('Recording starts in'), findsNothing);
    expect(
      find.byKey(const ValueKey('custom-recording-badge')),
      findsOneWidget,
    );
    expect(find.text('REC'), findsOneWidget);
    expect(find.text('00:15 remaining'), findsOneWidget);
    final stop = tester.widget<ElixPrimaryButton>(_recordButton);
    expect(stop.label, 'Stop & save example');
    expect(stop.variant, ElixButtonVariant.destructive);

    await tester.tap(_recordButton);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('REC'), findsNothing);
    expect(find.text('Record example 2'), findsOneWidget);
    expect(find.text('1 of 2 required · Up to 5 examples'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recording UI appears only after capture start is accepted', (
    tester,
  ) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket()..rejectNextStartCapture = true;
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);

    await tester.tap(_recordButton);
    for (var second = 0; second < 3; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();

    expect(socket.startCustomCaptureCalls, 1);
    expect(find.text('REC'), findsNothing);
    expect(find.text('Stop & save example'), findsNothing);
    expect(find.textContaining('Could not start recording'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Review commits a dirty trim before building the template', (
    tester,
  ) async {
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _recordTwoReferences(tester, socket);
    await _tapKey(tester, 'example-select-reference-1');
    await _nudgeTrimStart(tester, 10);
    expect(find.text('Start 00:01.00'), findsOneWidget);

    await _tapReview(tester);

    expect(socket.trimRanges, [('reference-1', 1000, 7000)]);
    expect(socket.commandOrder, ['trim', 'build']);
    expect(socket.buildCalls, 1);
    expect(find.text('Only prop movement was learned'), findsOneWidget);
  });

  testWidgets('Review skips trim when the selected range is unchanged', (
    tester,
  ) async {
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _recordTwoReferences(tester, socket);
    await _tapReview(tester);

    expect(socket.trimRanges, isEmpty);
    expect(socket.commandOrder, ['build']);
    expect(find.text('Only prop movement was learned'), findsOneWidget);
  });

  testWidgets(
    'failed automatic trim preserves committed range and skips build',
    (tester) async {
      final socket = _Socket()..rejectNextTrim = true;
      addTearDown(socket.close);
      await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
      await _recordTwoReferences(tester, socket);
      await _tapKey(tester, 'example-select-reference-1');
      await _nudgeTrimStart(tester, 10);
      await _tapReview(tester);

      expect(socket.commandOrder, ['trim']);
      expect(socket.buildCalls, 0);
      expect(socket.committedTrims['reference-1'], (0, 7000));
      expect(find.textContaining('Could not apply the trim'), findsOneWidget);
      expect(find.text('Apply trim'), findsOneWidget);
      expect(find.text('Continue to review'), findsOneWidget);
    },
  );

  testWidgets('trim handles cannot cross and Apply sends exact milliseconds', (
    tester,
  ) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    await _record(tester, socket);

    // Keyboard nudges are 100 ms; the start cannot move below zero.
    await _nudgeTrimStart(tester, -3);
    expect(find.text('Start 00:00.00'), findsOneWidget);
    await _nudgeTrimStart(tester, 15);
    expect(find.text('Start 00:01.50'), findsOneWidget);
    await _tapKey(tester, 'trim-apply');
    expect(socket.trimRanges.last, ('reference-1', 1500, 7000));

    // Dragging the start past the end stops one millisecond short of it.
    final startHandle = find.byKey(const ValueKey('trim-start-handle'));
    await tester.ensureVisible(startHandle);
    await tester.drag(startHandle, const Offset(4000, 0));
    await tester.pump();
    expect(find.text('Start 00:06.99'), findsOneWidget);
    expect(find.text('End 00:07.00'), findsOneWidget);

    // Dragging the end past the start stops one millisecond after it.
    final endHandle = find.byKey(const ValueKey('trim-end-handle'));
    await tester.drag(endHandle, const Offset(-4000, 0));
    await tester.pump();
    await _tapKey(tester, 'trim-apply');
    final (id, start, end) = socket.trimRanges.last;
    expect(id, 'reference-1');
    expect(start, 6999);
    expect(end, 7000);
    expect(end - start, 1);

    // Reset restores the full clip locally; Apply commits it.
    await _tapKey(tester, 'trim-reset');
    expect(find.text('Keeps 00:07.00'), findsOneWidget);
    await _tapKey(tester, 'trim-apply');
    expect(socket.trimRanges.last, ('reference-1', 0, 7000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected trim keeps the previously committed range', (
    tester,
  ) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    await _record(tester, socket);
    await _nudgeTrimStart(tester, 10);
    await _tapKey(tester, 'trim-apply');
    expect(socket.committedTrims['reference-1'], (1000, 7000));

    socket.rejectNextTrim = true;
    await _nudgeTrimStart(tester, 20);
    await _tapKey(tester, 'trim-apply');

    expect(socket.trimRanges.last, ('reference-1', 3000, 7000));
    expect(socket.committedTrims['reference-1'], (1000, 7000));
    expect(
      find.text(
        'Keep more of the movement in the clip. The previous trim is still saved.',
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('example-card-reference-1')),
        matching: find.text('00:06.00 · Trimmed'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('insufficient template frames show guidance rather than a code', (
    tester,
  ) async {
    final socket = _Socket()..rejectBuildCode = 'insufficient_frames';
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _recordTwoReferences(tester, socket);
    await _tapReview(tester);

    expect(find.text('insufficient_frames'), findsNothing);
    expect(
      find.textContaining(
        'The selected clip is too short or does not contain enough of the full movement.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue to review'), findsOneWidget);
  });

  testWidgets('unstable static reference shows static-hold guidance', (
    tester,
  ) async {
    final socket = _Socket()
      ..rejectBuildCode = 'unstable_static_reference'
      ..rejectBuildMessage = 'backend text';
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _recordTwoReferences(tester, socket);
    await _tapReview(tester);

    expect(
      find.text(
        'The final position was still moving. Hold it steady for at least 0.8 seconds before stopping.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('unstable_static_reference'), findsNothing);
    expect(find.text('Continue to review'), findsOneWidget);
  });

  testWidgets('execution guidance is required before authoring can continue', (
    tester,
  ) async {
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));

    expect(find.text('How to perform it'), findsOneWidget);
    expect(
      find.text(
        'Describe it step by step. ELIXR shows these instructions during practice.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-movement-name')),
      'Bottle Loop',
    );
    await _continueToRecording(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Describe how to perform this movement from start to finish.'),
      findsOneWidget,
    );
    expect(find.text('Movement basics'), findsOneWidget);
    expect(socket.preparedMode, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('movement behavior cards map to dynamic and static values', (
    tester,
  ) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));

    AuthoringChoiceCard card(String value) =>
        tester.widget<AuthoringChoiceCard>(
          find.byKey(ValueKey('custom-movement-behavior-$value')),
        );
    expect(card('dynamic').selected, isTrue);
    expect(card('static').selected, isFalse);
    expect(
      find.text(
        'Use this for a grip, stall, or final position that should be held steady.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('custom-movement-behavior-static')),
    );
    await tester.pump();
    expect(card('static').selected, isTrue);
    expect(card('dynamic').selected, isFalse);

    await _enterReferenceStudio(tester, socket);
    expect(
      find.text('Show the grip or stall, then hold the final position steady.'),
      findsOneWidget,
    );
    await _record(tester, socket);
    await _record(tester, socket);

    // Recorded examples lock the behavior until they are deleted.
    await tester.tap(_backButton);
    await tester.pump(const Duration(milliseconds: 200));
    expect(card('dynamic').onPressed, isNull);
    expect(card('static').onPressed, isNull);
    await _continueToRecording(tester);
    await _tapReview(tester);
    expect(socket.builtBehavior, 'static');
    expect(find.text('Static hold'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'camera source change closes the old reference session before preparing another',
    (tester) async {
      _useViewport(tester, const Size(1366, 768));
      final socket = _Socket();
      addTearDown(socket.close);
      final settings = _Settings(deviceId: 'dev-a');
      await tester.pumpWidget(
        _host(
          repository: _Repository(),
          socket: socket,
          settingsOverride: settings,
        ),
      );
      await _fillDetails(tester);
      await _continueToRecording(tester);
      for (
        var attempt = 0;
        attempt < 20 && socket.preparedCameraIds.isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(socket.preparedCameraIds, ['dev-a']);
      expect(socket.preparedMode, 'custom_capture');
      expect(socket.preparedReadiness?.hands, ActivityHandRequirement.oneHand);
      expect(socket.preparedReadiness?.body, ActivityBodyRequirement.upperBody);
      await tester.pump(const Duration(milliseconds: 100));
      final cameraPreference = tester.widget<CameraSourcePreference>(
        find.byType(CameraSourcePreference),
      );
      await settings.setSelectedCameraDevice('dev-b');
      cameraPreference.onSelectionSaved!('dev-b');
      for (
        var attempt = 0;
        attempt < 20 && socket.preparedCameraIds.length < 2;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(socket.stopCalls, 1);
      expect(socket.preparedCameraIds, ['dev-a', 'dev-b']);
      socket.ready();
      await tester.pump();
      final cameraBefore = tester.getSize(find.byType(AspectRatio).first);
      await tester.ensureVisible(_recordButton);
      await tester.tap(_recordButton);
      await tester.pump();
      expect(tester.getSize(find.byType(AspectRatio).first), cameraBefore);
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(tester.getSize(find.byType(AspectRatio).first), cameraBefore);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reference recording requires one person and rejected clips can be retried',
    (tester) async {
      _useViewport(tester, const Size(1100, 800));
      final socket = _Socket();
      addTearDown(socket.close);
      await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
      await _fillDetails(tester);
      await _continueToRecording(tester);
      socket.ready(personCount: 0);
      await tester.pump();
      expect(_onPressed(tester, _recordButton), isNull);
      expect(find.text('Step into view so ELIXR can see you.'), findsOneWidget);
      socket.ready(personCount: 2);
      await tester.pump();
      expect(_onPressed(tester, _recordButton), isNull);
      expect(
        find.text('Only one person should be in view to record.'),
        findsOneWidget,
      );
      socket.ready(handsVisible: false);
      await tester.pump();
      expect(_onPressed(tester, _recordButton), isNull);
      socket.ready(upperBodyVisible: false);
      await tester.pump();
      expect(_onPressed(tester, _recordButton), isNull);
      expect(
        _pillState(tester, 'camera-check-body'),
        AuthoringCheckState.missing,
      );
      socket.ready();
      await _waitUntilRecordable(tester);
      socket.rejectNextReference = true;
      await _record(tester, socket);
      expect(socket.count, 0);
      expect(
        find.textContaining('This example was not usable'),
        findsOneWidget,
      );
      await _record(tester, socket);
      expect(socket.count, 1);
      expect(socket.stopCustomCaptureCalls, 2);
      expect(find.text('REC'), findsNothing);
      expect(find.textContaining('Example 1'), findsWidgets);
      socket.ready(readinessStable: false);
      await tester.pump();
      expect(_onPressed(tester, _recordButton), isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reference recording automatically finalizes at its deadline', (
    tester,
  ) async {
    _useViewport(tester, const Size(1100, 800));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    await _startReferenceRecording(tester, socket);

    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 100));

    expect(socket.startCustomCaptureCalls, 1);
    expect(socket.stopCustomCaptureCalls, 1);
    expect(socket.count, 1);
    expect(find.text('REC'), findsNothing);
    expect(find.text('Stop & save example'), findsNothing);
    expect(find.textContaining('Example 1'), findsWidgets);

    await tester.pump(const Duration(seconds: 20));
    expect(socket.stopCustomCaptureCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual finish cancels timeout and sends one stop command', (
    tester,
  ) async {
    _useViewport(tester, const Size(1100, 800));
    final socket = _Socket()..stopReferenceCompleter = Completer<void>();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    await _startReferenceRecording(tester, socket);

    await tester.tap(_recordButton);
    await tester.pump();
    expect(socket.stopCustomCaptureCalls, 1);
    expect(find.text('REC'), findsNothing);
    expect(find.text('Saving example…'), findsWidgets);

    await tester.pump(const Duration(seconds: 15));
    expect(socket.stopCustomCaptureCalls, 1);
    socket.stopReferenceCompleter!.complete();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(socket.stopCustomCaptureCalls, 1);
    expect(socket.count, 1);
    expect(find.textContaining('Example 1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the authoring page cancels its capture timer', (
    tester,
  ) async {
    _useViewport(tester, const Size(1100, 800));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    await _startReferenceRecording(tester, socket);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 16));

    expect(socket.stopCustomCaptureCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'full page guides two required references and keeps a third optional',
    (tester) async {
      _useViewport(tester, const Size(1100, 800));
      final repository = _Repository();
      final socket = _Socket();
      addTearDown(socket.close);
      await tester.pumpWidget(_host(repository: repository, socket: socket));
      expect(find.byType(ContentDialog), findsNothing);
      expect(find.text('Movement basics'), findsOneWidget);
      await _fillDetails(tester);
      await _continueToRecording(tester);
      expect(
        tester.getTopLeft(find.text('Live camera')).dx,
        lessThan(tester.getTopLeft(find.text('Examples')).dx),
      );
      expect(
        find.text(
          'Record 2 examples of the same movement. Small movements are okay. Each clip must be at least 1.0 second long.',
        ),
        findsOneWidget,
      );
      expect(find.text('0 of 2 required'), findsOneWidget);
      expect(_onPressed(tester, _reviewButton), isNull);
      expect(find.text('Record 2 more examples to continue.'), findsOneWidget);
      socket.ready(handsVisible: true);
      await _waitUntilRecordable(tester);
      expect(find.textContaining('Could not prepare'), findsNothing);
      for (final key in [
        'camera-check-person',
        'camera-check-prop',
        'camera-check-hands',
        'camera-check-body',
      ]) {
        expect(_pillState(tester, key), AuthoringCheckState.ok, reason: key);
      }
      expect(find.text('Starting camera…'), findsNothing);
      expect(
        find.text('Everything is in view. You can record now.'),
        findsOneWidget,
      );
      socket.ready(handsVisible: false);
      await tester.pump();
      expect(
        _pillState(tester, 'camera-check-hands'),
        AuthoringCheckState.missing,
      );
      expect(
        find.text('Move your hands fully into view to start recording.'),
        findsOneWidget,
      );
      expect(_onPressed(tester, _recordButton), isNull);
      socket.ready(handsVisible: true);
      await tester.pump();
      await _record(tester, socket);
      expect(find.text('Example 1'), findsOneWidget);
      expect(find.text('Hands hard to see'), findsOneWidget);
      expect(find.textContaining('left hand 25%'), findsOneWidget);
      expect(find.byType(ElixrVideoPlayer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('example-card-reference-1')),
          matching: find.byType(ElixrVideoPlayer),
        ),
        findsNothing,
      );
      expect(_onPressed(tester, _reviewButton), isNull);
      await _record(tester, socket);
      expect(find.text('Example 2'), findsOneWidget);
      expect(find.text('Ready to review'), findsOneWidget);
      expect(
        find.text(
          'A third example can help ELIXR learn the movement more consistently.',
        ),
        findsOneWidget,
      );
      expect(_onPressed(tester, _reviewButton), isNotNull);
      await _tapReview(tester);
      expect(find.text('Only prop movement was learned'), findsOneWidget);
      expect(_pillState(tester, 'learned-pose'), AuthoringCheckState.missing);
      expect(_pillState(tester, 'learned-hands'), AuthoringCheckState.missing);
      expect(_pillState(tester, 'learned-prop'), AuthoringCheckState.ok);
      expect(find.text('Record better examples'), findsOneWidget);
      expect(_onPressed(tester, _saveButton), isNotNull);
      await tester.tap(_backButton);
      await tester.pump(const Duration(milliseconds: 100));
      for (var index = 0; index < 3; index++) {
        await _record(tester, socket);
        if (index == 0) {
          expect(
            find.text('You can review whenever you are ready.'),
            findsOneWidget,
          );
        }
      }
      expect(find.textContaining('5 example limit'), findsOneWidget);
      expect(_onPressed(tester, _recordButton), isNull);
      expect(find.text('Example limit reached'), findsOneWidget);
      await _tapKey(tester, 'example-select-reference-2');
      expect(
        find.byKey(const ValueKey('reference-player-reference-2')),
        findsOneWidget,
      );
      expect(find.byType(ElixrVideoPlayer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('example-card-reference-2')),
          matching: find.byType(ElixrVideoPlayer),
        ),
        findsNothing,
      );
      await _nudgeTrimStart(tester, 10);
      expect(find.text('Start 00:01.00'), findsOneWidget);
      expect(find.text('Trim not applied yet'), findsOneWidget);
      await _tapKey(tester, 'trim-apply');
      expect(socket.trimmed, ['reference-2']);
      expect(socket.trimRanges.last, ('reference-2', 1000, 7000));
      await tester.pump(const Duration(milliseconds: 100));
      await _tapKey(tester, 'trim-reset');
      expect(find.text('Start 00:00.00'), findsOneWidget);
      expect(find.text('Keeps 00:07.00'), findsOneWidget);
      expect(socket.trimmed, ['reference-2']);
      await _tapKey(tester, 'trim-apply');
      expect(socket.trimmed, ['reference-2', 'reference-2']);
      await _tapKey(tester, 'example-delete-reference-2');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(socket.deleted, ['reference-2']);
      expect(
        find.byKey(const ValueKey('reference-player-reference-2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('example-card-reference-2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('example-card-reference-3')),
        findsOneWidget,
      );
      expect(find.textContaining('Example 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing teacher template stays active without historical clips',
    (tester) async {
      _useViewport(tester, const Size(650, 750));
      final repository = _Repository();
      final socket = _Socket();
      addTearDown(socket.close);
      final movement = _movement(CustomMovementOwnerRole.teacher);
      final revision = CustomMovementRevision(
        id: 'revision-1',
        movementId: movement.id,
        ownerUid: movement.ownerUid,
        ownerRole: movement.ownerRole,
        template: MovementTemplate.tryFrom(_templateMap(3))!,
      );
      await tester.pumpWidget(
        _host(
          repository: repository,
          socket: socket,
          existing: movement,
          revision: revision,
          role: CustomMovementOwnerRole.teacher,
        ),
      );
      await _continueToRecording(tester);
      expect(socket.preparedCameraIds, isEmpty);
      expect(
        find.textContaining('Earlier recordings were not saved'),
        findsOneWidget,
      );
      expect(find.text('Record new examples'), findsOneWidget);
      await _tapReview(tester);
      expect(_onPressed(tester, _saveButton), isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('save errors identify the failed persistence step', (
    tester,
  ) async {
    _useViewport(tester, const Size(650, 750));

    for (final stage in [
      CustomMovementSaveStage.referenceImageUpload,
      CustomMovementSaveStage.databaseCommit,
    ]) {
      final repository = _Repository()
        ..saveFailure = CustomMovementSaveException(
          stage: stage,
          cause: StateError('private test detail'),
          stackTrace: StackTrace.current,
        );
      final socket = _Socket();
      addTearDown(socket.close);
      final movement = _movement(CustomMovementOwnerRole.trainee);
      final revision = CustomMovementRevision(
        id: 'revision-1',
        movementId: movement.id,
        ownerUid: movement.ownerUid,
        ownerRole: movement.ownerRole,
        template: MovementTemplate.tryFrom(_templateMap(3))!,
      );
      await tester.pumpWidget(
        _host(
          repository: repository,
          socket: socket,
          existing: movement,
          revision: revision,
        ),
      );
      await _continueToRecording(tester);
      await _tapReview(tester);
      await tester.ensureVisible(_saveButton);
      await tester.tap(_saveButton);
      await tester.pump();
      await tester.pump();

      expect(find.text(stage.userMessage), findsOneWidget);
      expect(find.text('private test detail'), findsNothing);
      expect(repository.saved, isNull);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a teardown failure after save cannot submit the save twice', (
    tester,
  ) async {
    _useViewport(tester, const Size(650, 750));

    final repository = _Repository();
    final socket = _Socket()..failDisconnect = true;
    addTearDown(socket.close);
    final movement = _movement(CustomMovementOwnerRole.trainee);
    final revision = CustomMovementRevision(
      id: 'revision-1',
      movementId: movement.id,
      ownerUid: movement.ownerUid,
      ownerRole: movement.ownerRole,
      template: MovementTemplate.tryFrom(_templateMap(3))!,
    );
    await tester.pumpWidget(
      _host(
        repository: repository,
        socket: socket,
        existing: movement,
        revision: revision,
      ),
    );
    await _continueToRecording(tester);
    await _tapReview(tester);
    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton);
    await tester.pump();
    await tester.pump();

    expect(repository.saved, same(movement));
    expect(repository.saveCalls, 1);
    expect(find.text('Movement saved'), findsOneWidget);
    expect(
      find.text(CustomMovementSaveStage.teardown.userMessage),
      findsOneWidget,
    );
    expect(find.text('Close'), findsOneWidget);

    await tester.ensureVisible(_saveButton);
    await tester.tap(_saveButton);
    await tester.pump();
    expect(repository.saveCalls, 1);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new movement saves through createMovement after review', (
    tester,
  ) async {
    _useViewport(tester, const Size(1366, 768));
    final repository = _Repository();
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: repository, socket: socket));
    await _recordTwoReferences(tester, socket);
    await _tapReview(tester);
    expect(find.text('Movement details'), findsOneWidget);
    expect(find.text('Bottle Loop'), findsOneWidget);
    expect(find.text('2 recorded'), findsOneWidget);

    await tester.tap(_saveButton);
    await tester.pump();
    await tester.pump();
    expect(repository.saveCalls, 1);
    expect(repository.saved?.ownerRole, CustomMovementOwnerRole.trainee);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets(
    'rotation is automatic optional evidence and review reports learned capability',
    (tester) async {
      _useViewport(tester, const Size(1050, 800));
      final repository = _Repository();
      final socket = _Socket();
      addTearDown(socket.close);
      final movement = _movement(CustomMovementOwnerRole.trainee);
      CustomMovementRevision revision(MovementTemplate template) =>
          CustomMovementRevision(
            id: 'revision-1',
            movementId: movement.id,
            ownerUid: movement.ownerUid,
            ownerRole: movement.ownerRole,
            template: template,
          );
      await tester.pumpWidget(
        _host(
          repository: repository,
          socket: socket,
          existing: movement,
          revision: revision(MovementTemplate.tryFrom(_rotationTemplateMap())!),
        ),
      );
      expect(
        find.byKey(const ValueKey('custom-movement-require-rotation')),
        findsNothing,
      );
      expect(find.text('Bottle rotation'), findsOneWidget);
      expect(
        find.textContaining(
          'Rotation is optional and will not block assessment.',
        ),
        findsOneWidget,
      );
      await _continueToRecording(tester);
      await _tapReview(tester);
      expect(find.textContaining('Visible bottle rotation'), findsWidgets);
      expect(_pillState(tester, 'learned-rotation'), AuthoringCheckState.ok);
      expect(_onPressed(tester, _saveButton), isNotNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(
          repository: repository,
          socket: socket,
          existing: movement,
          revision: revision(MovementTemplate.tryFrom(_templateMap(3))!),
        ),
      );
      expect(
        find.byKey(const ValueKey('custom-movement-require-rotation')),
        findsNothing,
      );
      await _continueToRecording(tester);
      expect(_onPressed(tester, _reviewButton), isNotNull);
      await _tapReview(tester);
      expect(
        _pillState(tester, 'learned-rotation'),
        AuthoringCheckState.pending,
      );
      expect(find.text('Not learned · optional'), findsOneWidget);
      expect(find.text('Visible bottle rotation bonus'), findsNothing);
      expect(
        find.text(
          'Rotation is optional. This movement can still be saved and scored.',
        ),
        findsOneWidget,
      );
      expect(_onPressed(tester, _saveButton), isNotNull);
    },
  );

  testWidgets('shaker authoring does not claim rotation is supported', (
    tester,
  ) async {
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));

    tester
        .widget<ComboBox<TrainingProp>>(
          find.byKey(const ValueKey('custom-movement-prop')),
        )
        .onChanged!(TrainingProp.shaker);
    await tester.pump();

    expect(find.textContaining('rotation'), findsNothing);
    expect(
      find.byKey(const ValueKey('custom-movement-require-rotation')),
      findsNothing,
    );
  });

  testWidgets(
    'prop cannot change under an in-flight prepare; Bottle to Shaker re-prepares',
    (tester) async {
      _useViewport(tester, const Size(1366, 768));
      final socket = _Socket()..prepareGate = Completer<void>();
      addTearDown(socket.close);
      await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
      ValueChanged<TrainingProp?>? propChanged() => tester
          .widget<ComboBox<TrainingProp>>(
            find.byKey(const ValueKey('custom-movement-prop')),
          )
          .onChanged;

      await _fillDetails(tester);
      await _continueToRecording(tester);
      expect(socket.preparedProps, [TrainingProp.bottle]);
      // Going back while the bottle session is still preparing must not let
      // the prop change underneath that session.
      await tester.tap(_backButton);
      await tester.pump();
      expect(propChanged(), isNull);

      socket.prepareGate!.complete();
      socket.prepareGate = null;
      await tester.pump(const Duration(milliseconds: 100));
      propChanged()!(TrainingProp.shaker);
      await tester.pump(const Duration(milliseconds: 100));
      expect(socket.stopCalls, 1);

      await _continueToRecording(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(socket.preparedProps, [TrainingProp.bottle, TrainingProp.shaker]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review shows only learned hand and body capabilities', (
    tester,
  ) async {
    _useViewport(tester, const Size(1100, 700));
    final socket = _Socket();
    addTearDown(socket.close);
    final movement = _movement(CustomMovementOwnerRole.trainee);
    final template = _templateMap(3);
    template['required_modalities'] = ['prop_translation', 'hands', 'pose'];
    template['feature_capabilities'] = {
      ...template['feature_capabilities'] as Map<String, dynamic>,
      'hands': true,
      'pose': true,
    };
    final revision = CustomMovementRevision(
      id: 'revision-1',
      movementId: movement.id,
      ownerUid: movement.ownerUid,
      ownerRole: movement.ownerRole,
      template: MovementTemplate.tryFrom(template)!,
    );
    await tester.pumpWidget(
      _host(
        repository: _Repository(),
        socket: socket,
        existing: movement,
        revision: revision,
      ),
    );
    await _continueToRecording(tester);
    await _tapReview(tester);
    expect(find.text('Hands'), findsOneWidget);
    expect(find.text('Upper body'), findsOneWidget);
    expect(_pillState(tester, 'learned-hands'), AuthoringCheckState.ok);
    expect(_pillState(tester, 'learned-pose'), AuthoringCheckState.ok);
    expect(find.text('Hands were not learned'), findsNothing);
    expect(
      find.byKey(const ValueKey('custom-movement-learning-warning')),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1366, 768), Size(1648, 920)]) {
    testWidgets(
      'desktop ${size.width.toInt()}x${size.height.toInt()} keeps step actions visible without scrolling',
      (tester) async {
        _useViewport(tester, size);
        final socket = _Socket();
        addTearDown(socket.close);
        await tester.pumpWidget(
          _host(repository: _Repository(), socket: socket),
        );
        final next = find.byKey(const ValueKey('custom-movement-next'));
        _expectFullyVisible(tester, next, size);
        _expectFullyVisible(
          tester,
          find.byKey(const ValueKey('authoring-step-2')),
          size,
        );

        await _fillDetails(tester);
        await tester.tap(next);
        await tester.pump(const Duration(milliseconds: 100));
        socket.ready();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        for (final finder in [
          _recordButton,
          _reviewButton,
          _backButton,
          find.byKey(const ValueKey('custom-camera-frame')),
          find.byKey(const ValueKey('camera-check-guidance')),
          find.text('Examples'),
        ]) {
          _expectFullyVisible(tester, finder, size);
        }
        // Camera and examples share the row; the camera is the larger panel.
        final camera = tester.getRect(
          find.byKey(const ValueKey('custom-camera-frame')),
        );
        expect(camera.width, greaterThan(size.width * 0.38));
        expect(
          tester.getTopLeft(find.text('Examples')).dx,
          greaterThan(camera.right),
        );

        await _record(tester, socket);
        await _record(tester, socket);
        _expectFullyVisible(tester, _reviewButton, size);
        _expectFullyVisible(tester, _recordButton, size);
        expect(_onPressed(tester, _reviewButton), isNotNull);
        await tester.tap(_reviewButton);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 250));
        _expectFullyVisible(tester, _saveButton, size);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('narrow recording studio stacks live capture above examples', (
    tester,
  ) async {
    _useViewport(tester, const Size(450, 750));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _fillDetails(tester);
    await _continueToRecording(tester);
    socket.ready();
    await tester.pump();
    final live = find.text('Live camera');
    final examples = find.text('Examples');
    expect(
      tester.getTopLeft(live).dy,
      lessThan(tester.getTopLeft(examples).dy),
    );
    expect(
      find.ancestor(of: examples, matching: find.byType(SingleChildScrollView)),
      findsWidgets,
    );
    // The step action stays pinned while the studio scrolls.
    _expectFullyVisible(tester, _reviewButton, const Size(450, 750));
    await _record(tester, socket);
    expect(find.byType(ElixrVideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short windows fall back to one scrolling page', (tester) async {
    _useViewport(tester, const Size(1024, 520));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    await _record(tester, socket);
    await _record(tester, socket);
    await tester.ensureVisible(_reviewButton);
    await tester.pump();
    expect(_onPressed(tester, _reviewButton), isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide studio keeps compact examples beside the live camera', (
    tester,
  ) async {
    _useViewport(tester, const Size(1600, 900));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    await _record(tester, socket);
    await _record(tester, socket);
    final first = tester.getTopLeft(
      find.byKey(const ValueKey('example-card-reference-1')),
    );
    final second = tester.getTopLeft(
      find.byKey(const ValueKey('example-card-reference-2')),
    );
    expect((first.dy - second.dy).abs(), lessThan(2));
    expect(first.dx, lessThan(second.dx));
    expect(find.byType(ElixrVideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('customReferenceIssueMessage', () {
    String? message(
      String code,
      Map<String, dynamic>? details, {
      String behavior = 'dynamic',
    }) => customReferenceIssueMessage(
      code,
      details,
      movementBehavior: behavior,
      propLabel: 'Bottle',
    );

    test('short static clip states duration and hold requirements', () {
      expect(
        message('reference_duration_too_short', {
          'duration_ms': 600,
        }, behavior: 'static'),
        'This clip is 0.6 s. Record at least 1.0 second and hold the final position steady for at least 0.8 seconds.',
      );
    });

    test('long clip with few samples is a tracking problem', () {
      final text = message('insufficient_tracking_samples', {
        'duration_ms': 5200,
        'sample_count': 4,
        'required_sample_count': 6,
      })!;
      expect(
        text,
        'Your clip is long enough, but ELIXR captured only 4 usable tracking samples (needs 6). Keep your hand and bottle visible and try again.',
      );
      expect(text, isNot(contains('too short')));
    });

    test('static hold with enough total samples reports its tracked span', () {
      final text = message('insufficient_tracking_samples', {
        'sample_count': 6,
        'required_sample_count': 6,
        'hold_sample_count': 6,
        'required_hold_sample_count': 4,
        'hold_duration_ms': 500,
      }, behavior: 'static')!;
      expect(text, contains('final hold was tracked for only 0.5 s'));
      expect(text, contains('0.8 s'));
      expect(text, isNot(contains('captured only 6')));
    });

    test('coverage, gap, motion, and trim codes are specific', () {
      expect(
        message('insufficient_prop_coverage', {'prop_coverage': 0.4}),
        contains('visible in only 40% of the clip'),
      );
      expect(
        message('insufficient_hand_coverage', {'hand_coverage': 0.5}),
        contains('Your hand was tracked in only 50%'),
      );
      expect(
        message('insufficient_hand_coverage', {
          'hand_side': 'right',
          'hand_coverage': 0.3,
          'left_hand_coverage': 1.0,
        }),
        contains('Your right hand was tracked in only 30%'),
      );
      expect(
        message('excessive_tracking_gap', {'longest_tracking_gap_ms': 1000}),
        contains('lost for 1.0 s in a row'),
      );
      expect(
        message('no_meaningful_motion', {'reference_index': 1}),
        startsWith('Example 2: ELIXR can see your hand and bottle'),
      );
      expect(
        message('invalid_trim_range', null),
        'That trim range is not valid. Keep the start before the end.',
      );
      expect(
        message('invalid_reference_count', null, behavior: 'static'),
        'Record 1 clear example before reviewing.',
      );
      expect(message('multiple_people_detected', null), isNull);
    });
  });

  Map<String, dynamic> staticTemplateMap() => _templateMap(1)
    ..['schema_version'] = 3
    ..['movement_behavior'] = 'static'
    ..['rotation_trace'] = null
    ..['canonical_sequence'] = List.generate(
      32,
      (index) => {'timestamp_ms': index * 30, 'pose': <String, dynamic>{}},
    );

  testWidgets('static hold reviews and saves after one example', (
    tester,
  ) async {
    _useViewport(tester, const Size(1366, 768));
    final repository = _Repository();
    final socket = _Socket()..templateOverride = staticTemplateMap();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: repository, socket: socket));
    await _tapKey(tester, 'custom-movement-behavior-static');
    await _enterReferenceStudio(tester, socket);
    expect(
      find.text(
        'Record 1 clear example. Hold the final position steady for at least 0.8 seconds. Each clip must be at least 1.0 second long.',
      ),
      findsOneWidget,
    );
    expect(find.text('0 of 1 required · Up to 5 examples'), findsOneWidget);
    expect(_onPressed(tester, _reviewButton), isNull);

    await _record(tester, socket);
    expect(find.text('Ready to review'), findsOneWidget);
    expect(_onPressed(tester, _reviewButton), isNotNull);
    await _tapReview(tester);
    expect(socket.builtBehavior, 'static');
    expect(find.text('Static hold'), findsOneWidget);
    expect(find.textContaining('A third example'), findsNothing);

    await tester.tap(_saveButton);
    await tester.pump();
    await tester.pump();
    expect(repository.saveCalls, 1);
    expect(repository.savedTemplate?.referenceCount, 1);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('dynamic still needs two examples before review', (tester) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    await _record(tester, socket);
    expect(_onPressed(tester, _reviewButton), isNull);
    expect(find.text('Record 1 more example to continue.'), findsOneWidget);
  });

  testWidgets('rejected clip explains a tracking problem with measurements', (
    tester,
  ) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket()
      ..rejectNextStopCode = 'insufficient_tracking_samples'
      ..rejectNextStopQuality = {
        'duration_ms': 5200,
        'sample_count': 4,
        'required_sample_count': 6,
      };
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _enterReferenceStudio(tester, socket);
    await _record(tester, socket);
    expect(socket.count, 0);
    expect(
      find.text(
        'Your clip is long enough, but ELIXR captured only 4 usable tracking samples (needs 6). Keep your hand and bottle visible and try again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('too short'), findsNothing);
  });

  testWidgets('build rejection marks the example and shows quality on its card', (
    tester,
  ) async {
    _useViewport(tester, const Size(1366, 768));
    final socket = _Socket()
      ..rejectBuildCode = 'no_meaningful_motion'
      ..rejectBuildQuality = {
        'reference_index': 1,
        'movement_signals': <String>[],
      };
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await _recordTwoReferences(tester, socket);
    await _tapReview(tester);
    expect(
      find.textContaining(
        'Example 2: ELIXR can see your hand and bottle, but no clear movement was detected.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue to review'), findsOneWidget);

    await _tapKey(tester, 'example-select-reference-2');
    expect(
      _pillState(tester, 'reference-quality-motion'),
      AuthoringCheckState.missing,
    );
    expect(
      _pillState(tester, 'reference-quality-duration'),
      AuthoringCheckState.ok,
    );
    expect(
      _pillState(tester, 'reference-quality-hands'),
      AuthoringCheckState.missing,
    );
    expect(
      _pillState(tester, 'reference-quality-body'),
      AuthoringCheckState.ok,
    );
    expect(find.text('Hands · 25%'), findsOneWidget);
    expect(find.text('Duration · 7.0 s'), findsOneWidget);
    await _tapKey(tester, 'example-select-reference-1');
    expect(
      _pillState(tester, 'reference-quality-motion'),
      AuthoringCheckState.pending,
    );
  });

  testWidgets('setup remains usable in light, dark, and high contrast themes', (
    tester,
  ) async {
    _useViewport(tester, const Size(450, 750));
    for (final theme in [
      AppTheme.dark,
      AppTheme.light,
      AppTheme.highContrastDark,
      AppTheme.highContrastLight,
    ]) {
      final socket = _Socket();
      addTearDown(socket.close);
      await tester.pumpWidget(
        _host(repository: _Repository(), socket: socket, theme: theme),
      );
      expect(find.text('Movement basics'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('custom-movement-name')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
