import 'dart:async';
import 'dart:typed_data';

import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/features/custom_movements/custom_movement_practice_screen.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/features/practice/widgets/training_action_area.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:elixr_application/services/audio_player_handle.dart';
import 'package:elixr_application/services/session_service.dart';
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
  Map<String, dynamic>? nextAssessment;
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

  int confirmCalls = 0;
  int activateCalls = 0;
  String? rejectNextConfirmCode;

  @override
  Future<CommandAck> sendConfirmReadiness({String? sessionId}) async {
    confirmCalls += 1;
    final code = rejectNextConfirmCode;
    rejectNextConfirmCode = null;
    return _ack('confirm_readiness', accepted: code == null, errorCode: code);
  }

  @override
  Future<CommandAck> sendActivate({String? sessionId}) async {
    activateCalls += 1;
    return _ack('activate');
  }

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
      customAssessment:
          nextAssessment ??
          {
            'score_percent': 83.3,
            'total': 10,
            'max_total': 12,
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
  Future<CommandAck> sendBuildCustomTemplate({
    String? sessionId,
    String movementBehavior = 'dynamic',
  }) async {
    buildCalls += 1;
    return _ack('build_custom_template', referenceCount: acceptedReferences);
  }

  /// When set, stop never resolves until completed (slow backend teardown).
  Completer<CommandAck>? stopGate;

  /// When set, stop fails immediately (lost backend connection).
  Object? stopError;

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) async {
    stopCalls += 1;
    final gate = stopGate;
    if (gate != null) return gate.future;
    final error = stopError;
    if (error != null) throw error;
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
    String? customAssessmentProgress,
    String? customAssessmentCue,
    int? customAssessmentCueSequence,
    int? personCount = 1,
    bool? referenceInvalid,
    List<ReadinessItemView>? readinessItems,
    bool? readinessComplete,
    double? readinessStableProgress,
    Uint8List? evidenceJpegBytes,
  }) {
    _feedback.add(
      PracticeFeedback(
        bottleDetected: bottleDetected,
        movement: 'Custom Movement',
        feedback: customAssessmentProgress == 'waiting_for_movement'
            ? 'Waiting for movement…'
            : customAssessmentProgress == 'movement_detected'
            ? 'Movement detected. Keep going through the full sequence.'
            : customAssessmentProgress == 'completed'
            ? 'Movement completed. Processing score…'
            : readinessStable == true
            ? 'Ready.'
            : 'Getting into position.',
        feedbackType: 'positive',
        postureStatus: 'unknown',
        readinessStable: readinessStable,
        readinessItems: readinessItems,
        readinessComplete: readinessComplete,
        readinessStableProgress: readinessStableProgress,
        customAssessmentProgress: customAssessmentProgress,
        customAssessmentCue: customAssessmentCue,
        customAssessmentCueSequence: customAssessmentCueSequence,
        personCount: personCount,
        referenceInvalid: referenceInvalid,
        evidenceJpegBytes: evidenceJpegBytes,
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

class _ClassroomRepository extends Fake
    implements ClassroomAssignmentRepository {
  int saveCalls = 0;
  bool failSave = false;
  int? savedTotal;
  String? savedLevel;
  Map<String, int?>? savedComponents;

  @override
  Future<void> saveCustomMovementAssignmentAttempt({
    required GroupAssignment assignment,
    required String traineeId,
    required int total,
    required String performanceLevel,
    required Map<String, int?> componentScores,
  }) async {
    saveCalls += 1;
    savedTotal = total;
    savedLevel = performanceLevel;
    savedComponents = componentScores;
    if (failSave) throw StateError('network down');
  }
}

const _referenceAssignment = GroupAssignment(
  id: 'assignment-ref',
  teacherId: 'teacher-1',
  groupId: 'group-1',
  movementId: 'movement-auto',
  revisionId: 'revision-auto',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.referenceMatched,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Auto toss',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'BSHM 4A',
  allowedProp: TrainingProp.bottle,
);

class _RecordingRepository extends Fake implements CustomMovementRepository {
  int savePersonalResultCalls = 0;
  int allocatedSessionIds = 0;
  bool failNextSave = false;
  double? savedScore;
  String? savedMovementName;
  int? savedDurationSeconds;
  Map<String, double>? savedComponents;
  final List<String> savedSessionIds = [];
  final List<Uint8List?> savedEvidence = [];

  @override
  String allocateSessionId() => 'custom-session-${++allocatedSessionIds}';

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
    Uint8List? evidenceJpegBytes,
  }) async {
    savePersonalResultCalls += 1;
    savedScore = totalScore;
    savedMovementName = movementName;
    savedDurationSeconds = durationSeconds;
    savedComponents = componentScores;
    savedSessionIds.add(sessionId);
    savedEvidence.add(evidenceJpegBytes);
    if (failNextSave) {
      failNextSave = false;
      throw StateError('offline');
    }
  }
}

class _EvidencePreferences extends SessionService {
  _EvidencePreferences({this.enabled});

  bool? enabled;
  final List<bool> recordedDecisions = [];

  @override
  Future<bool?> sessionEvidenceEnabled(String userId) async => enabled;

  @override
  Future<void> setSessionEvidenceEnabled({
    required String userId,
    required bool enabled,
  }) async {
    recordedDecisions.add(enabled);
    this.enabled = enabled;
  }
}

/// A JPEG-sized payload within the private evidence contract (1–256 KiB).
final _evidenceJpeg = Uint8List.fromList(List<int>.filled(2048, 7));

/// Records native audio commands without opening an audio device.
class _FakeAudioPlayer implements AudioPlayerHandle {
  final _completions = StreamController<void>.broadcast();
  final operations = <String>[];
  int disposeCount = 0;

  int count(String operation) => operations.where((o) => o == operation).length;

  @override
  Stream<void> get onPlayerComplete => _completions.stream;

  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {}

  @override
  Future<void> setVolume(double volume) async =>
      operations.add('volume:$volume');

  @override
  Future<void> setSourceAsset(String assetPath) async =>
      operations.add('source:$assetPath');

  @override
  Future<void> playAsset(String assetPath) async =>
      operations.add('play:$assetPath');

  @override
  Future<void> playAssetAtPosition(String assetPath, {Duration? position}) =>
      playAsset(assetPath);

  @override
  Future<void> playFile(String filePath) async =>
      operations.add('play:$filePath');

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async => operations.add('stop');

  @override
  Future<void> dispose() async {
    disposeCount++;
    await _completions.close();
  }
}

/// Audio service disposal cancels stream subscriptions, which needs real
/// async turns in addition to the fake-clock pumps.
Future<void> _settleAudioTeardown(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

const _countdownSfx = 'play:music/countdown.mp3';
const _selectedTrack = 'play:music/A Sky Full of Stars.mp3';

class _TestSettings extends SettingsService {
  _TestSettings({this.deviceId, this.sound = true});

  String? deviceId;
  final bool sound;

  @override
  bool get soundEnabled => sound;

  @override
  double get musicVolume => 0.6;

  @override
  String? get selectedMusicTrackId => 'sky_full_of_stars';

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

const _autoStartLabel = 'Hold steady… starts automatically';

/// Stable readiness auto-confirms; then the 3-second countdown, activation
/// and custom capture start follow with no user action.
Future<void> _autoStartThroughCountdown(
  WidgetTester tester,
  _CustomSocket socket,
) async {
  socket.emitReady();
  await tester.pump();
  for (var second = 0; second < 3; second++) {
    await tester.pump(const Duration(seconds: 1));
  }
  await tester.pump();
}

CustomMovement _movement({String id = 'movement-auto'}) => CustomMovement(
  id: id,
  ownerUid: 'trainee-1',
  ownerRole: CustomMovementOwnerRole.trainee,
  name: 'Auto toss',
  description: 'Toss and catch with the left hand.',
  difficulty: 'Medium',
  propType: TrainingProp.bottle,
  status: CustomMovementStatus.active,
  activeRevisionId: 'revision-auto',
);

CustomMovementRevision _revision(CustomMovement movement) =>
    CustomMovementRevision(
      id: movement.activeRevisionId,
      movementId: movement.id,
      ownerUid: movement.ownerUid,
      ownerRole: movement.ownerRole,
      template: MovementTemplate.tryFrom(_oneHandTemplateMap())!,
    );

Future<void> _pumpPractice(
  WidgetTester tester,
  _CustomSocket socket, {
  CustomMovementRepository? repository,
  SessionService? sessionService,
  VoidCallback? onExit,
  ClassroomAssignmentRepository? classroomRepository,
  int? classroomAttemptsRemaining,
  DateTime Function() now = DateTime.now,
  SettingsService? settings,
  AudioPlayerHandle? musicPlayer,
  AudioPlayerHandle? sfxPlayer,
}) async {
  _useDesktopSurface(tester);
  final movement = _movement();
  await tester.pumpWidget(
    _withSettings(
      settings ?? _TestSettings(),
      CustomMovementPracticeScreen(
        musicPlayer: musicPlayer,
        sfxPlayer: sfxPlayer,
        movement: movement,
        revision: _revision(movement),
        repository: repository ?? _UnusedRepository(),
        webSocket: socket,
        sessionService: sessionService ?? _EvidencePreferences(enabled: false),
        onExit: onExit,
        assignment: classroomRepository == null ? null : _referenceAssignment,
        traineeUid: classroomRepository == null ? null : 'trainee-1',
        classroomRepository: classroomRepository,
        classroomAttemptsRemaining: classroomAttemptsRemaining,
        now: now,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _completeMovement(
  WidgetTester tester,
  _CustomSocket socket, {
  Uint8List? evidence,
}) async {
  socket.emitFeedback(
    bottleDetected: true,
    customAssessmentProgress: 'completed',
    evidenceJpegBytes: evidence,
  );
  await tester.pumpAndSettle();
}

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

  testWidgets('legacy empty instructions do not refer to unavailable videos', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final socket = _CustomSocket();
    final movement = CustomMovement(
      id: 'legacy-empty-instructions',
      ownerUid: 'teacher-1',
      ownerRole: CustomMovementOwnerRole.teacher,
      name: 'Legacy movement',
      description: '',
      difficulty: 'Easy',
      propType: TrainingProp.bottle,
      status: CustomMovementStatus.active,
      activeRevisionId: 'revision-legacy',
    );
    final revision = CustomMovementRevision(
      id: 'revision-legacy',
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

    const fallback =
        'Execution instructions are unavailable. If you own this movement, edit it to add guidance; otherwise ask the owner to add them before you practice.';
    final instructionSection = find.byKey(
      const ValueKey('custom-movement-instructions'),
    );
    expect(find.text('How to perform'), findsOneWidget);
    expect(
      find.descendant(of: instructionSection, matching: find.text(fallback)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('custom-movement-instructions-text')),
          )
          .data,
      fallback,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('practice-training-header')),
        matching: find.text(fallback),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('saved reference'), findsNothing);
    expect(find.textContaining('saved references'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets(
    'long custom instructions remain complete before practice at compact and desktop widths',
    (tester) async {
      const description =
          'Stand with your feet shoulder width apart and hold the bottle in '
          'your right hand. Toss it gently above shoulder height while keeping '
          'your eyes on the bottle. Let it rotate once, then move your left '
          'hand under its base and catch it securely. Reset your grip, bring '
          'the bottle back to the starting position, and repeat the same '
          'controlled toss and catch until the movement is complete.';

      for (final size in [
        const Size(1400, 1000),
        const Size(900, 1000),
        const Size(760, 1000),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final socket = _CustomSocket();
        final movement = CustomMovement(
          id: 'movement-long-instructions',
          ownerUid: 'trainee-1',
          ownerRole: CustomMovementOwnerRole.trainee,
          name: 'Long instruction toss',
          description: description,
          difficulty: 'Easy',
          propType: TrainingProp.bottle,
          status: CustomMovementStatus.active,
          activeRevisionId: 'revision-long-instructions',
        );
        final revision = CustomMovementRevision(
          id: 'revision-long-instructions',
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

        final instructionSection = find.byKey(
          const ValueKey('custom-movement-instructions'),
        );
        expect(find.text('How to perform'), findsOneWidget);
        expect(
          find.descendant(
            of: instructionSection,
            matching: find.text(description),
          ),
          findsOneWidget,
        );
        final fullInstructions = tester.widget<Text>(
          find.byKey(const ValueKey('custom-movement-instructions-text')),
        );
        expect(fullInstructions.data, description);
        expect(fullInstructions.maxLines, isNull);
        expect(fullInstructions.overflow, isNull);
        // No manual start: setup advances automatically once stable.
        expect(find.text('Start Practice'), findsNothing);
        expect(find.text(_autoStartLabel), findsOneWidget);
        expect(
          tester
              .widget<TrainingActionArea>(find.byType(TrainingActionArea))
              .onPressed,
          isNull,
        );

        final headerInstruction = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('practice-training-header')),
            matching: find.text(description),
          ),
        );
        expect(headerInstruction.maxLines, 2);
        expect(headerInstruction.overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        await socket.closeTestStreams();
      }
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
      await _autoStartThroughCountdown(tester, socket);

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
      // Still calibrating (not yet stable), so the camera may be changed.
      socket.emitReadiness(false);
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
      // The camera change starts a fresh, unconsumed readiness gate.
      expect(find.text(_autoStartLabel), findsOneWidget);
      expect(socket.confirmCalls, 0);
      await _autoStartThroughCountdown(tester, socket);
      expect(socket.confirmCalls, 1);
      expect(socket.startCustomCaptureCalls, 1);
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
      expect(find.text('Start Practice'), findsNothing);
      expect(socket.confirmCalls, 0);
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
      // Stable readiness is accepted and the countdown begins by itself.
      expect(socket.confirmCalls, 1);
      expect(find.text('Get ready · 3'), findsOne);
      expect(find.text('Start Practice'), findsNothing);
      expect(find.text('Finish Session'), findsNothing);
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      expect(socket.startCustomCaptureCalls, 1);
      expect(find.text('Recording · 00:30 max'), findsOneWidget);
      expect(find.text('Completes automatically'), findsOne);
      expect(
        find.text(
          'Perform the complete saved sequence. ELIXR will finish when the sequence is observed.',
        ),
        findsOne,
      );

      socket.emitFeedback(
        bottleDetected: true,
        customAssessmentProgress: 'movement_detected',
        customAssessmentCue: 'release',
        customAssessmentCueSequence: 1,
      );
      await tester.pump();
      expect(find.text('RELEASE'), findsOne);
      socket.emitFeedback(
        bottleDetected: true,
        customAssessmentProgress: 'movement_detected',
        customAssessmentCue: 'release',
        customAssessmentCueSequence: 1,
      );
      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.byKey(const ValueKey('custom-live-cue')), findsNothing);
      socket.emitFeedback(
        bottleDetected: true,
        customAssessmentProgress: 'movement_detected',
        customAssessmentCue: 'catch',
        customAssessmentCueSequence: 2,
      );
      await tester.pump();
      expect(find.text('CATCH'), findsOne);

      socket.emitFeedback(bottleDetected: false);
      socket.emitPresentation();
      await tester.pump();
      expect(find.text('Searching for bottle'), findsOne);
      expect(find.text('Completes automatically'), findsOne);

      socket.emitFeedback(bottleDetected: true);
      socket.emitPresentation(prop: 'confirmed', hands: 'tracking');
      await tester.pump();
      expect(find.text('Bottle detected'), findsOne);

      socket.rejectNextStop = true;
      socket.rejectNextStopCode = 'track_loss';
      socket.emitFeedback(
        bottleDetected: true,
        customAssessmentProgress: 'completed',
      );
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
      await _autoStartThroughCountdown(tester, socket);
      expect(socket.startCustomCaptureCalls, 2);
      expect(find.text('Completes automatically'), findsOne);
      expect(socket.finishCustomAssessmentCalls, 0);
      expect(repository.savePersonalResultCalls, 0);

      final finishAssessment = Completer<CommandAck>();
      socket.finishAssessmentCompleter = finishAssessment;
      socket.emitFeedback(
        bottleDetected: true,
        customAssessmentProgress: 'completed',
      );
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
            'max_total': 12,
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
      expect(repository.savedComponents, {'Timing': 3.0, 'Prop path': 2.0});
      // The result is a modal dialog, not inline session-panel content.
      expect(find.byKey(const ValueKey('custom-result-dialog')), findsOne);
      expect(
        find.byKey(const ValueKey('custom-assessment-result')),
        findsNothing,
      );
      expect(find.text('83%'), findsOne);
      expect(find.text('Score 10 / 12'), findsOne);
      expect(find.text('Proficient'), findsOne);
      expect(find.text('3 / 3'), findsOne);
      expect(find.text('•  Good timing'), findsOne);
      expect(find.text('Session saved'), findsOne);
      expect(find.byKey(const ValueKey('custom-live-cue')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets('static assessment shows hold guidance and observed hold cue', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final socket = _CustomSocket();
    final staticMap = {
      ..._oneHandTemplateMap(),
      'schema_version': 3,
      'movement_behavior': 'static',
      'rotation_trace': null,
      'canonical_sequence': List.generate(
        32,
        (index) => {'timestamp_ms': index * 33, 'pose': <String, dynamic>{}},
      ),
    };
    final template = MovementTemplate.tryFrom(staticMap)!;
    final movement = CustomMovement(
      id: 'static-grip',
      ownerUid: 'trainee-1',
      ownerRole: CustomMovementOwnerRole.trainee,
      name: 'Normal Grip',
      description: 'Hold the bottle.',
      difficulty: 'Easy',
      propType: TrainingProp.bottle,
      status: CustomMovementStatus.active,
      activeRevisionId: 'revision-static',
    );
    await tester.pumpWidget(
      _withSettings(
        _TestSettings(),
        CustomMovementPracticeScreen(
          movement: movement,
          revision: CustomMovementRevision(
            id: 'revision-static',
            movementId: movement.id,
            ownerUid: movement.ownerUid,
            ownerRole: movement.ownerRole,
            template: template,
          ),
          repository: _RecordingRepository(),
          webSocket: socket,
        ),
      ),
    );
    await tester.pump();
    await _autoStartThroughCountdown(tester, socket);
    expect(
      find.text('Move into the saved position and hold steady.'),
      findsOne,
    );
    socket.emitFeedback(
      bottleDetected: true,
      customAssessmentProgress: 'position_detected',
      customAssessmentCue: 'position_detected',
      customAssessmentCueSequence: 1,
    );
    await tester.pump();
    expect(find.text('POSITION DETECTED'), findsOne);
    socket.emitFeedback(
      bottleDetected: true,
      customAssessmentProgress: 'position_detected',
      customAssessmentCue: 'hold_steady',
      customAssessmentCueSequence: 2,
    );
    await tester.pump();
    expect(find.text('HOLD STEADY'), findsOne);
    final finishAssessment = Completer<CommandAck>();
    socket.finishAssessmentCompleter = finishAssessment;
    socket.emitFeedback(
      bottleDetected: true,
      customAssessmentProgress: 'completed',
      customAssessmentCue: 'completed',
      customAssessmentCueSequence: 3,
    );
    await tester.pump();
    expect(find.text('HOLD COMPLETE'), findsOne);
    finishAssessment.complete(
      _ack(
        'finish_custom_assessment',
        customAssessment: {
          'score_percent': 83.3,
          'total': 10,
          'max_total': 12,
          'performance_level': 'proficient',
          'component_scores': {'Hand technique': 3, 'Prop path': 3},
          'feedback': <String>[],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('custom-live-cue')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets(
    'repeated stable readiness starts exactly one countdown, activation and capture',
    (tester) async {
      final socket = _CustomSocket();
      await _pumpPractice(tester, socket, repository: _RecordingRepository());

      for (var i = 0; i < 5; i++) {
        socket.emitReady();
        await tester.pump();
      }
      expect(socket.confirmCalls, 1);
      for (var second = 0; second < 3; second++) {
        socket.emitReady();
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      socket.emitReady();
      await tester.pump();

      expect(socket.confirmCalls, 1);
      expect(socket.activateCalls, 1);
      expect(socket.startCustomCaptureCalls, 1);
      expect(find.text('Completes automatically'), findsOne);
      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets(
    'late readiness loss after acceptance cannot demote or restart the attempt',
    (tester) async {
      final socket = _CustomSocket();
      await _pumpPractice(tester, socket, repository: _RecordingRepository());

      socket.emitReady();
      await tester.pump();
      expect(find.text('Get ready · 3'), findsOne);
      socket.emitReadiness(false);
      await tester.pump();
      expect(find.text('Get ready · 3'), findsOne);
      expect(find.text(_autoStartLabel), findsNothing);
      for (var second = 0; second < 3; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      socket.emitReadiness(false);
      await tester.pump();
      socket.emitReady();
      await tester.pump();

      expect(find.text('Completes automatically'), findsOne);
      expect(socket.confirmCalls, 1);
      expect(socket.activateCalls, 1);
      expect(socket.startCustomCaptureCalls, 1);
      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets(
    'recoverable confirm rejection keeps calibrating and re-arms on fresh stability',
    (tester) async {
      final socket = _CustomSocket()
        ..rejectNextConfirmCode = 'readiness_not_stable';
      await _pumpPractice(tester, socket, repository: _RecordingRepository());

      socket.emitReady();
      await tester.pump();
      await tester.pump();
      expect(socket.confirmCalls, 1);
      expect(find.text(_autoStartLabel), findsOne);
      expect(find.text('Practice needs attention'), findsNothing);

      await _autoStartThroughCountdown(tester, socket);
      expect(socket.confirmCalls, 2);
      expect(socket.startCustomCaptureCalls, 1);
      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets('retry resets the gate so a new attempt auto-starts', (
    tester,
  ) async {
    final socket = _CustomSocket()..rejectStartCustomCapture = true;
    await _pumpPractice(tester, socket, repository: _RecordingRepository());

    await _autoStartThroughCountdown(tester, socket);
    expect(socket.startCustomCaptureCalls, 1);
    expect(find.text('Practice Again'), findsOne);

    socket.rejectStartCustomCapture = false;
    await tester.tap(find.text('Practice Again'));
    await tester.pump();
    expect(find.text(_autoStartLabel), findsOne);
    await _autoStartThroughCountdown(tester, socket);

    expect(socket.confirmCalls, 2);
    expect(socket.activateCalls, 2);
    expect(socket.startCustomCaptureCalls, 2);
    expect(find.text('Completes automatically'), findsOne);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets(
    'completion saves once automatically and Practice Again auto-starts a new attempt',
    (tester) async {
      final socket = _CustomSocket();
      final repository = _RecordingRepository();
      await _pumpPractice(tester, socket, repository: repository);
      await _autoStartThroughCountdown(tester, socket);

      await _completeMovement(tester, socket);
      // A duplicate completion signal cannot finish or save twice.
      socket.emitFeedback(
        bottleDetected: true,
        customAssessmentProgress: 'completed',
      );
      await tester.pumpAndSettle();
      expect(socket.finishCustomAssessmentCalls, 1);
      expect(repository.savePersonalResultCalls, 1);
      expect(repository.savedSessionIds, ['custom-session-1']);
      expect(find.byKey(const ValueKey('custom-result-dialog')), findsOne);
      expect(find.text('Session saved'), findsOne);
      expect(find.text('Personal practice · No global XP'), findsOne);
      expect(find.text('Back to My Movements'), findsOne);
      expect(find.text('Classroom assessment · No global XP'), findsNothing);
      expect(find.textContaining('Legacy'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('custom-result-practice-again')),
      );
      // Setup visuals animate continuously, so pump past the dialog exit.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('custom-result-dialog')), findsNothing);
      expect(socket.preparedCameraDeviceIds, hasLength(2));
      await _autoStartThroughCountdown(tester, socket);
      expect(socket.startCustomCaptureCalls, 2);
      expect(repository.savePersonalResultCalls, 1);
      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets(
    'timeout after a failed attempt shows the scored result and Try Again starts clean',
    (tester) async {
      final socket = _CustomSocket()
        ..nextAssessment = {
          'score_percent': 25.0,
          'total': 3,
          'max_total': 12,
          'performance_level': 'beginning',
          'movement_completed': false,
          'component_scores': {'Timing': 1, 'Prop path': 0},
          'feedback': ['Time expired before the full movement was completed.'],
        };
      final repository = _RecordingRepository();
      var clock = DateTime(2026, 1, 1, 12);
      await _pumpPractice(
        tester,
        socket,
        repository: repository,
        now: () => clock,
      );
      await _autoStartThroughCountdown(tester, socket);
      expect(find.text('Recording · 00:30 max'), findsOne);

      // A wrong first motion is only progress, never a terminal failure.
      socket.emitFeedback(
        bottleDetected: true,
        customAssessmentProgress: 'movement_detected',
        customAssessmentCue: 'movement_detected',
        customAssessmentCueSequence: 1,
      );
      clock = clock.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Practice needs attention'), findsNothing);
      expect(find.text('Recording · 00:20 max'), findsOne);
      expect(socket.finishCustomAssessmentCalls, 0);

      clock = clock.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(socket.finishCustomAssessmentCalls, 1);
      expect(find.text('Practice needs attention'), findsNothing);
      expect(find.byKey(const ValueKey('custom-result-dialog')), findsOne);
      expect(find.text('25%'), findsOne);
      expect(find.text('Score 3 / 12'), findsOne);
      expect(
        find.text('•  Time expired before the full movement was completed.'),
        findsOne,
      );
      expect(repository.savedScore, 25.0);

      await tester.tap(
        find.byKey(const ValueKey('custom-result-practice-again')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('custom-result-dialog')), findsNothing);
      expect(socket.preparedCameraDeviceIds, hasLength(2));
      expect(find.text(_autoStartLabel), findsOne);
      await _autoStartThroughCountdown(tester, socket);
      expect(socket.startCustomCaptureCalls, 2);
      // Fresh timer and no carried-over progress or cue.
      expect(find.text('Recording · 00:30 max'), findsOne);
      expect(find.text('Waiting for movement…'), findsOne);
      expect(find.byKey(const ValueKey('custom-live-cue')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets('save failure keeps the result and retries the same session id', (
    tester,
  ) async {
    final socket = _CustomSocket();
    final repository = _RecordingRepository()..failNextSave = true;
    var exited = false;
    await _pumpPractice(
      tester,
      socket,
      repository: repository,
      onExit: () => exited = true,
    );
    await _autoStartThroughCountdown(tester, socket);
    await _completeMovement(tester, socket);

    expect(find.byKey(const ValueKey('custom-result-dialog')), findsOne);
    expect(find.text('83%'), findsOne);
    expect(find.text('Session saved'), findsNothing);
    expect(find.text('Retry Save'), findsOne);
    expect(
      tester
          .widget<GameActionButton>(
            find.byKey(const ValueKey('custom-result-back')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('Retry Save'));
    await tester.pumpAndSettle();
    expect(repository.savedSessionIds, [
      'custom-session-1',
      'custom-session-1',
    ]);
    expect(repository.allocatedSessionIds, 1);
    expect(find.text('Session saved'), findsOne);

    await tester.tap(
      find.byKey(const ValueKey('custom-result-primary-action')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(exited, isTrue);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets('evidence-enabled save passes the backend completion frame', (
    tester,
  ) async {
    final socket = _CustomSocket();
    final repository = _RecordingRepository();
    final preferences = _EvidencePreferences(enabled: true);
    await _pumpPractice(
      tester,
      socket,
      repository: repository,
      sessionService: preferences,
    );
    await _autoStartThroughCountdown(tester, socket);
    await _completeMovement(tester, socket, evidence: _evidenceJpeg);

    expect(repository.savedEvidence, [same(_evidenceJpeg)]);
    expect(preferences.recordedDecisions, isEmpty);
    expect(find.byKey(const ValueKey('custom-result-evidence')), findsOne);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets('evidence-disabled save uploads no image', (tester) async {
    final socket = _CustomSocket();
    final repository = _RecordingRepository();
    await _pumpPractice(
      tester,
      socket,
      repository: repository,
      sessionService: _EvidencePreferences(enabled: false),
    );
    await _autoStartThroughCountdown(tester, socket);
    await _completeMovement(tester, socket, evidence: _evidenceJpeg);

    expect(repository.savePersonalResultCalls, 1);
    expect(repository.savedEvidence, [isNull]);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets(
    'unset evidence preference asks consent before saving the image',
    (tester) async {
      final socket = _CustomSocket();
      final repository = _RecordingRepository();
      final preferences = _EvidencePreferences();
      await _pumpPractice(
        tester,
        socket,
        repository: repository,
        sessionService: preferences,
      );
      await _autoStartThroughCountdown(tester, socket);
      await _completeMovement(tester, socket, evidence: _evidenceJpeg);

      expect(find.text('Save your confirmed movement?'), findsOne);
      expect(repository.savePersonalResultCalls, 0);
      await tester.tap(find.text('Enable & save image'));
      await tester.pumpAndSettle();
      expect(preferences.recordedDecisions, [true]);
      expect(repository.savedEvidence, [same(_evidenceJpeg)]);
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

  testWidgets(
    'Teacher-assigned result saves once and opens the classroom result dialog',
    (tester) async {
      final socket = _CustomSocket();
      final classroom = _ClassroomRepository();
      var exits = 0;
      await _pumpPractice(
        tester,
        socket,
        classroomRepository: classroom,
        classroomAttemptsRemaining: 2,
        onExit: () => exits++,
      );
      await _autoStartThroughCountdown(tester, socket);
      await _completeMovement(tester, socket);
      // A duplicate completion signal cannot save a second attempt.
      socket.emitFeedback(
        bottleDetected: true,
        customAssessmentProgress: 'completed',
      );
      await tester.pumpAndSettle();

      expect(classroom.saveCalls, 1);
      expect(classroom.savedTotal, 10);
      expect(classroom.savedLevel, 'proficient');
      expect(classroom.savedComponents, {'Timing': 3, 'Prop path': 2});
      expect(find.byKey(const ValueKey('custom-result-dialog')), findsOne);
      expect(
        find.byKey(const ValueKey('custom-assessment-result')),
        findsNothing,
      );
      expect(find.text('Auto toss'), findsWidgets);
      expect(find.text('Classroom assessment · No global XP'), findsOne);
      expect(find.text('Personal practice · No global XP'), findsNothing);
      expect(find.text('Back to Assignment'), findsOne);
      expect(find.text('Back to My Movements'), findsNothing);
      expect(find.text('83%'), findsOne);
      expect(find.text('Score 10 / 12'), findsOne);
      expect(find.text('Proficient'), findsOne);
      expect(find.text('3 / 3'), findsOne);
      expect(find.text('•  Good timing'), findsOne);
      expect(find.text('Session saved'), findsOne);
      // One attempt remains after this save.
      expect(
        find.byKey(const ValueKey('custom-result-practice-again')),
        findsOne,
      );

      await tester.tap(find.byKey(const ValueKey('custom-result-back')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(exits, 1);
      expect(classroom.saveCalls, 1);
      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );

  testWidgets('classroom save failure keeps the result and never re-saves', (
    tester,
  ) async {
    final socket = _CustomSocket();
    final classroom = _ClassroomRepository()..failSave = true;
    var exits = 0;
    await _pumpPractice(
      tester,
      socket,
      classroomRepository: classroom,
      onExit: () => exits++,
    );
    await _autoStartThroughCountdown(tester, socket);
    await _completeMovement(tester, socket);

    expect(classroom.saveCalls, 1);
    expect(find.byKey(const ValueKey('custom-result-dialog')), findsOne);
    expect(find.text('83%'), findsOne);
    expect(
      find.text(
        'Assessment complete, but the classroom result could not be saved. '
        'Return to the assignment to check your attempts before trying again.',
      ),
      findsOne,
    );
    expect(find.textContaining('network down'), findsNothing);
    // The reference-match save is not idempotent, so it is never retried.
    expect(find.text('Retry Save'), findsNothing);
    expect(find.text('Session saved'), findsNothing);
    // The attempt count is unknown after a failed save; the trainee returns
    // to the assignment instead of starting another attempt from here.
    expect(
      find.byKey(const ValueKey('custom-result-practice-again')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('custom-result-primary-action')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(exits, 1);
    expect(classroom.saveCalls, 1);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets('classroom result hides Practice Again after the last attempt', (
    tester,
  ) async {
    final socket = _CustomSocket();
    final classroom = _ClassroomRepository();
    await _pumpPractice(
      tester,
      socket,
      classroomRepository: classroom,
      classroomAttemptsRemaining: 1,
      onExit: () {},
    );
    await _autoStartThroughCountdown(tester, socket);
    await _completeMovement(tester, socket);

    expect(find.byKey(const ValueKey('custom-result-dialog')), findsOne);
    expect(
      find.byKey(const ValueKey('custom-result-practice-again')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  group('practice audio', () {
    testWidgets(
      'countdown SFX plays once, music starts only when recording, and Practice Again repeats both',
      (tester) async {
        final socket = _CustomSocket();
        final music = _FakeAudioPlayer();
        final sfx = _FakeAudioPlayer();
        await _pumpPractice(
          tester,
          socket,
          repository: _RecordingRepository(),
          musicPlayer: music,
          sfxPlayer: sfx,
        );
        expect(sfx.operations, contains('source:music/countdown.mp3'));
        expect(sfx.count(_countdownSfx), 0);

        socket.emitReady();
        await tester.pump();
        expect(sfx.count(_countdownSfx), 1);
        expect(sfx.operations, contains('volume:0.6'));
        // Music never masks the countdown or plays during setup.
        expect(music.count(_selectedTrack), 0);

        for (var second = 0; second < 3; second++) {
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.pump();
        expect(find.text('Completes automatically'), findsOne);
        expect(sfx.count(_countdownSfx), 1);
        expect(music.count(_selectedTrack), 1);

        final stopsBeforeFinish = music.count('stop');
        await _completeMovement(tester, socket);
        expect(music.count('stop'), greaterThan(stopsBeforeFinish));
        expect(music.operations.last, 'stop');

        await tester.tap(
          find.byKey(const ValueKey('custom-result-practice-again')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(music.count(_selectedTrack), 1);
        await _autoStartThroughCountdown(tester, socket);
        expect(sfx.count(_countdownSfx), 2);
        expect(music.count(_selectedTrack), 2);

        await tester.pumpWidget(const SizedBox());
        await _settleAudioTeardown(tester);
        expect(music.operations.last, 'stop');
        expect(music.disposeCount, 1);
        expect(sfx.disposeCount, 1);
        await socket.closeTestStreams();
      },
    );

    testWidgets('sound disabled mutes countdown and plays no music', (
      tester,
    ) async {
      final socket = _CustomSocket();
      final music = _FakeAudioPlayer();
      final sfx = _FakeAudioPlayer();
      await _pumpPractice(
        tester,
        socket,
        settings: _TestSettings(sound: false),
        musicPlayer: music,
        sfxPlayer: sfx,
      );
      await _autoStartThroughCountdown(tester, socket);
      expect(find.text('Completes automatically'), findsOne);
      expect(sfx.operations, contains('volume:0.0'));
      expect(sfx.operations, isNot(contains('volume:0.6')));
      expect(music.count(_selectedTrack), 0);
      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    });

    testWidgets(
      'failed capture start stops audio and retry starts a fresh attempt',
      (tester) async {
        final socket = _CustomSocket()..rejectStartCustomCapture = true;
        final music = _FakeAudioPlayer();
        final sfx = _FakeAudioPlayer();
        await _pumpPractice(tester, socket, musicPlayer: music, sfxPlayer: sfx);
        await _autoStartThroughCountdown(tester, socket);
        expect(find.text('Practice Again'), findsOne);
        expect(music.count(_selectedTrack), 0);
        expect(sfx.operations.last, 'stop');

        socket.rejectStartCustomCapture = false;
        await tester.tap(find.text('Practice Again'));
        await tester.pump();
        await _autoStartThroughCountdown(tester, socket);
        expect(sfx.count(_countdownSfx), 2);
        expect(music.count(_selectedTrack), 1);
        await tester.pumpWidget(const SizedBox());
        await socket.closeTestStreams();
      },
    );

    testWidgets('leaving mid-recording stops and disposes audio once', (
      tester,
    ) async {
      final socket = _CustomSocket();
      final music = _FakeAudioPlayer();
      final sfx = _FakeAudioPlayer();
      var exits = 0;
      await _pumpPractice(
        tester,
        socket,
        onExit: () => exits++,
        musicPlayer: music,
        sfxPlayer: sfx,
      );
      await _autoStartThroughCountdown(tester, socket);
      expect(music.count(_selectedTrack), 1);

      await tester.tap(find.byKey(const ValueKey('training-header-back')));
      await tester.pump();
      expect(exits, 1);
      expect(music.operations.last, 'stop');
      expect(sfx.operations.last, 'stop');

      await tester.pumpWidget(const SizedBox());
      await _settleAudioTeardown(tester);
      expect(music.disposeCount, 1);
      expect(sfx.disposeCount, 1);
      await socket.closeTestStreams();
    });
  });

  testWidgets('Back still exits after a failed assessment', (tester) async {
    final socket = _CustomSocket()..rejectStartCustomCapture = true;
    var exits = 0;
    await _pumpPractice(tester, socket, onExit: () => exits++);
    await _autoStartThroughCountdown(tester, socket);
    expect(find.text('Practice needs attention'), findsOne);

    await tester.tap(find.byKey(const ValueKey('training-header-back')));
    await tester.pump();
    expect(exits, 1);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets('Back still exits when the backend connection is lost', (
    tester,
  ) async {
    final socket = _CustomSocket()
      ..stopError = StateError('WebSocket is not connected');
    var exits = 0;
    await _pumpPractice(tester, socket, onExit: () => exits++);

    await tester.tap(find.byKey(const ValueKey('training-header-back')));
    await tester.pump();
    expect(exits, 1);
    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets(
    'slow teardown cannot trap the trainee and repeated Back exits once',
    (tester) async {
      final socket = _CustomSocket()..stopGate = Completer<CommandAck>();
      var exits = 0;
      await _pumpPractice(tester, socket, onExit: () => exits++);

      final back = find.byKey(const ValueKey('training-header-back'));
      await tester.tap(back);
      await tester.pump();
      await tester.tap(back);
      await tester.pump(const Duration(seconds: 1));
      expect(exits, 0);
      expect(socket.stopCalls, 1);

      await tester.pump(const Duration(seconds: 3));
      expect(exits, 1);
      await tester.tap(back);
      await tester.pump(const Duration(seconds: 4));
      expect(exits, 1);
      expect(socket.stopCalls, 1);
      await tester.pumpWidget(const SizedBox());
      await socket.closeTestStreams();
    },
  );
}
