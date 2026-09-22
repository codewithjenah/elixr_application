import 'dart:async';

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
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

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
  final _previews = StreamController<PreviewFrame>.broadcast();
  final _feedback = StreamController<PracticeFeedback>.broadcast();

  TeacherActivityReadinessSpec? preparedReadiness;
  String? preparedMode;
  int acceptedReferences = 0;
  int discardCalls = 0;
  int buildCalls = 0;
  bool rejectNextStop = false;

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
  }) async => _ack('start_custom_capture');

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
  Future<CommandAck> stopPracticeSession({String? sessionId}) async =>
      _ack('stop');

  void emitReady() {
    _feedback.add(
      const PracticeFeedback(
        bottleDetected: true,
        movement: 'Custom Movement',
        feedback: 'Ready.',
        feedbackType: 'positive',
        postureStatus: 'unknown',
        readinessStable: true,
      ),
    );
  }

  Future<void> closeTestStreams() async {
    await _previews.close();
    await _feedback.close();
  }
}

class _UnusedRepository extends Fake implements CustomMovementRepository {}

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
      FluentApp(
        home: CustomReferenceRecorderDialog(
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

    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets('assessment readiness and guidance follow one-hand template', (
    tester,
  ) async {
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
      FluentApp(
        home: CustomMovementPracticeScreen(
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
    expect(socket.preparedReadiness!.body, ActivityBodyRequirement.none);
    expect(
      find.text('Keep the selected prop and the left hand visible.'),
      findsOne,
    );

    await tester.pumpWidget(const SizedBox());
    await socket.closeTestStreams();
  });

  testWidgets('three-reference flow supports rejection retry and discard', (
    tester,
  ) async {
    _useDesktopSurface(tester);
    final socket = _CustomSocket()..rejectNextStop = true;
    await tester.pumpWidget(
      FluentApp(
        home: CustomReferenceRecorderDialog(
          difficulty: 'Medium',
          prop: TrainingProp.bottle,
          webSocket: socket,
        ),
      ),
    );
    await tester.pump();
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
}
