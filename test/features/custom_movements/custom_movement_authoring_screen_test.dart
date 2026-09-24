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
import 'package:elixr_application/features/settings/widgets/camera_source_preference.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
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

  @override
  Future<CustomMovement> createMovement({
    required String ownerUid,
    required CustomMovementOwnerRole ownerRole,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
  }) async {
    expect(template.referenceCount, greaterThanOrEqualTo(2));
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
  }) async => saved = current;
}

class _Socket extends Fake implements WebSocketService {
  final StreamController<PreviewFrame> previews = StreamController.broadcast();
  final StreamController<PracticeFeedback> feedback =
      StreamController.broadcast();
  int count = 0;
  final List<String> deleted = [];
  final List<String> trimmed = [];
  bool rejectNextReference = false;
  final List<String?> preparedCameraIds = [];
  int stopCalls = 0;
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
      return Future<CommandAck>.value(_ack('prepare'));
    }
    if (method == #stopPracticeSession) {
      stopCalls++;
      return Future<CommandAck>.value(_ack('stop'));
    }
    if (method == #sendBeginReadiness ||
        method == #sendConfirmReadiness ||
        method == #sendActivate ||
        method == #sendStartCustomCapture) {
      return Future<CommandAck>.value(_ack('$method'));
    }
    if (method == #sendStopCustomCapture) {
      if (rejectNextReference) {
        rejectNextReference = false;
        return Future<CommandAck>.value(
          CommandAck(
            protocolVersion: 1,
            requestId: 'request-stop_custom_capture',
            sessionId: 'session-1',
            action: 'stop_custom_capture',
            accepted: false,
            errorCode: 'multiple_people_detected',
          ),
        );
      }
      count++;
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
      return Future<CommandAck>.value(
        _ack(
          'trim_custom_reference',
          id: id,
          start: invocation.namedArguments[#startMs] as int,
          end: invocation.namedArguments[#endMs] as int,
        ),
      );
    }
    if (method == #sendBuildCustomTemplate) {
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
}) {
  final settings = settingsOverride ?? _Settings();
  final cameras = CameraDeviceService(
    httpGet: (_) async =>
        '{"cameras":[{"device_id":"dev-a","display_name":"Camera A","runtime_index":0,"is_active":false,"identity_stable":true},{"device_id":"dev-b","display_name":"Camera B","runtime_index":1,"is_active":false,"identity_stable":true}]}',
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

Future<void> _record(WidgetTester tester, _Socket socket) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('custom-reference-record')),
  );
  socket.ready();
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('custom-reference-record')));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
  expect(find.text('Finish example'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('custom-reference-record')));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'camera source change closes the old reference session before preparing another',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      await tester.enterText(
        find.byKey(const ValueKey('custom-movement-name')),
        'Bottle Loop',
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-movement-description')),
        'A complete bottle loop.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-next')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-next')));
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
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-reference-record')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-reference-record')));
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
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final socket = _Socket();
      addTearDown(socket.close);
      await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
      await tester.enterText(
        find.byKey(const ValueKey('custom-movement-name')),
        'Bottle Loop',
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-movement-description')),
        'A complete bottle loop.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-next')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-next')));
      await tester.pump(const Duration(milliseconds: 100));
      final record = find.byKey(const ValueKey('custom-reference-record'));
      socket.ready(personCount: 0);
      await tester.pump();
      expect(tester.widget<ElixPrimaryButton>(record).onPressed, isNull);
      socket.ready(personCount: 2);
      await tester.pump();
      expect(tester.widget<ElixPrimaryButton>(record).onPressed, isNull);
      socket.ready(handsVisible: false);
      await tester.pump();
      expect(tester.widget<ElixPrimaryButton>(record).onPressed, isNull);
      socket.ready(upperBodyVisible: false);
      await tester.pump();
      expect(tester.widget<ElixPrimaryButton>(record).onPressed, isNull);
      socket.ready();
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (tester.widget<ElixPrimaryButton>(record).onPressed != null) break;
      }
      expect(tester.widget<ElixPrimaryButton>(record).onPressed, isNotNull);
      socket.rejectNextReference = true;
      await _record(tester, socket);
      expect(socket.count, 0);
      expect(
        find.textContaining('This example was not usable'),
        findsOneWidget,
      );
      await _record(tester, socket);
      expect(socket.count, 1);
      expect(find.textContaining('Example 1'), findsWidgets);
      socket.ready(readinessStable: false);
      await tester.pump();
      expect(tester.widget<ElixPrimaryButton>(record).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full page guides two required references and keeps a third optional',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      final socket = _Socket();
      addTearDown(socket.close);
      await tester.pumpWidget(_host(repository: repository, socket: socket));
      expect(find.byType(ContentDialog), findsNothing);
      expect(find.text('Set up your movement'), findsWidgets);
      expect(find.textContaining('Record references'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('custom-movement-name')),
        'Bottle Loop',
      );
      await tester.enterText(
        find.byKey(const ValueKey('custom-movement-description')),
        'A complete bottle loop.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-next')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-next')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(find.text('Live camera').first).dx,
        lessThan(tester.getTopLeft(find.text('Your examples')).dx),
      );
      expect(
        find.text(
          'Perform the full movement from start to finish. Record it at least twice so ELIXR can learn the pattern.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const ValueKey('custom-movement-review')),
            )
            .onPressed,
        isNull,
      );
      socket.ready(handsVisible: true);
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (tester
                .widget<ElixPrimaryButton>(
                  find.byKey(const ValueKey('custom-reference-record')),
                )
                .onPressed !=
            null) {
          break;
        }
      }
      expect(find.textContaining('Could not prepare'), findsNothing);
      expect(
        find.text('In view'),
        findsWidgets,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((item) => item.data)
            .whereType<String>()
            .join(' | '),
      );
      expect(find.text('Preparing camera…'), findsNothing);
      expect(
        find.text('Keep at least one hand visible to record'),
        findsNothing,
      );
      socket.ready(handsVisible: false);
      await tester.pump();
      expect(
        find.text('Keep at least one hand visible to record'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Keep your hands fully visible'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const ValueKey('custom-reference-record')),
            )
            .onPressed,
        isNull,
      );
      socket.ready(handsVisible: true);
      await tester.pump();
      await _record(tester, socket);
      expect(find.textContaining('Example 1'), findsWidgets);
      expect(find.text('Good reference'), findsNothing);
      expect(find.text('✓ Accepted'), findsWidgets);
      expect(find.text('Hands were difficult to see'), findsOneWidget);
      expect(find.textContaining('Left hand: 25% of frames'), findsOneWidget);
      expect(find.byType(ElixrVideoPlayer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('example-card-reference-1')),
          matching: find.byType(ElixrVideoPlayer),
        ),
        findsNothing,
      );
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const ValueKey('custom-movement-review')),
            )
            .onPressed,
        isNull,
      );
      await _record(tester, socket);
      expect(find.textContaining('Example 2'), findsWidgets);
      expect(
        find.textContaining(
          'A third example helps ELIXR learn the pattern more consistently',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const ValueKey('custom-movement-review')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-review')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-review')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Only prop movement was learned'), findsOneWidget);
      expect(find.text('Upper body'), findsNothing);
      expect(find.text('Go back and record better examples'), findsOneWidget);
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const ValueKey('custom-movement-save')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Previous'));
      await tester.pump(const Duration(milliseconds: 100));
      for (var index = 0; index < 3; index++) {
        await _record(tester, socket);
        if (index == 0) {
          expect(
            find.textContaining('Recommended amount reached'),
            findsOneWidget,
          );
        }
      }
      expect(find.textContaining('5 example limit'), findsOneWidget);
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const ValueKey('custom-reference-record')),
            )
            .onPressed,
        isNull,
      );
      final previews = find.text('Preview / edit');
      await tester.ensureVisible(previews.at(1));
      await tester.tap(previews.at(1));
      await tester.pump(const Duration(milliseconds: 100));
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
      await tester.ensureVisible(find.text('Apply changes'));
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(1000);
      await tester.pump();
      expect(find.text('Start  00:01.00'), findsOneWidget);
      await tester.tap(find.text('Apply changes'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(socket.trimmed, ['reference-2']);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(find.text('Reset trim'));
      await tester.tap(find.text('Reset trim'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Start  00:00.00'), findsOneWidget);
      expect(find.text('Selected  00:07.00'), findsOneWidget);
      expect(socket.trimmed, ['reference-2', 'reference-2']);
      await tester.ensureVisible(find.text('Delete').at(1));
      await tester.tap(find.text('Delete').at(1));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(socket.deleted, ['reference-2']);
      expect(
        find.byKey(const ValueKey('reference-player-reference-2')),
        findsNothing,
      );
      expect(find.textContaining('Example 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing teacher template stays active without historical clips',
    (tester) async {
      tester.view.physicalSize = const Size(650, 750);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-next')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-next')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.textContaining('Earlier recordings were not saved'),
        findsOneWidget,
      );
      expect(find.text('Record new examples'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-review')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-review')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const ValueKey('custom-movement-save')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'existing rotation template remains valid and enabling rotation requires new evidence',
    (tester) async {
      tester.view.physicalSize = const Size(1050, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
        tester
            .widget<ToggleSwitch>(
              find.byKey(const ValueKey('custom-movement-require-rotation')),
            )
            .checked,
        isTrue,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-next')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-next')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-review')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-review')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Visible bottle rotation'), findsWidgets);
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const ValueKey('custom-movement-save')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _host(
          repository: repository,
          socket: socket,
          existing: movement,
          revision: revision(MovementTemplate.tryFrom(_templateMap(3))!),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('custom-movement-require-rotation')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-next')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-next')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const ValueKey('custom-movement-review')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('review shows only learned hand and body capabilities', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('custom-movement-next')),
    );
    await tester.tap(find.byKey(const ValueKey('custom-movement-next')));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('custom-movement-review')),
    );
    await tester.tap(find.byKey(const ValueKey('custom-movement-review')));
    await tester.pump();
    expect(find.text('Hands'), findsOneWidget);
    expect(find.text('Upper body'), findsOneWidget);
    expect(find.text('Hands were not learned'), findsNothing);
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow recording studio stacks live capture above examples', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(450, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await tester.enterText(
      find.byKey(const ValueKey('custom-movement-name')),
      'Bottle Loop',
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-movement-description')),
      'A complete bottle loop.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('custom-movement-next')),
    );
    await tester.tap(find.byKey(const ValueKey('custom-movement-next')));
    await tester.pump(const Duration(milliseconds: 100));
    socket.ready();
    await tester.pump();
    final live = find.text('Live camera').first;
    final examples = find.text('Your examples');
    expect(
      tester.getTopLeft(live).dy,
      lessThan(tester.getTopLeft(examples).dy),
    );
    await _record(tester, socket);
    expect(find.byType(ElixrVideoPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide studio keeps compact examples beside the live camera', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final socket = _Socket();
    addTearDown(socket.close);
    await tester.pumpWidget(_host(repository: _Repository(), socket: socket));
    await tester.enterText(
      find.byKey(const ValueKey('custom-movement-name')),
      'Bottle Loop',
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-movement-description')),
      'A complete bottle loop.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('custom-movement-next')),
    );
    await tester.tap(find.byKey(const ValueKey('custom-movement-next')));
    await tester.pump(const Duration(milliseconds: 100));
    socket.ready(handsVisible: true);
    await tester.pump();
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

  testWidgets('setup remains usable in light, dark, and high contrast themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(450, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
      expect(find.text('Set up your movement'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('custom-movement-name')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
