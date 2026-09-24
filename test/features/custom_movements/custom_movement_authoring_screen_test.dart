import 'dart:async';
import 'dart:convert';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/custom_movement.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/custom_movement_repository.dart';
import 'package:elixr_application/features/custom_movements/custom_movement_authoring_screen.dart';
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

  CommandAck _ack(
    String action, {
    String? id,
    int? start,
    int? end,
    Map<String, dynamic>? template,
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
  );

  void ready() {
    previews.add(
      PreviewFrame(
        jpegBytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aXcAAAAASUVORK5CYII=',
        ),
      ),
    );
    feedback.add(
      const PracticeFeedback(
        bottleDetected: true,
        movement: 'Custom Movement',
        feedback: 'Ready',
        feedbackType: 'positive',
        postureStatus: 'correct',
        readinessStable: true,
        personCount: 1,
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
    if (method == #sendPrepare ||
        method == #sendBeginReadiness ||
        method == #sendConfirmReadiness ||
        method == #sendActivate ||
        method == #sendStartCustomCapture ||
        method == #stopPracticeSession) {
      return Future<CommandAck>.value(_ack('$method'));
    }
    if (method == #sendStopCustomCapture) {
      count++;
      return Future<CommandAck>.value(
        _ack(
          'stop_custom_capture',
          id: 'reference-$count',
          start: 0,
          end: 7000,
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
        _ack('build_custom_template', template: _templateMap(count)),
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
  @override
  Future<String?> loadSelectedCameraDeviceId() async => null;
}

Widget _host({
  required _Repository repository,
  required _Socket socket,
  CustomMovement? existing,
  CustomMovementRevision? revision,
  CustomMovementOwnerRole role = CustomMovementOwnerRole.trainee,
}) {
  final settings = _Settings();
  final cameras = CameraDeviceService(httpGet: (_) async => '{"cameras":[]}');
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsService>.value(value: settings),
      ChangeNotifierProvider<CameraDeviceService>.value(value: cameras),
    ],
    child: FluentApp(
      theme: AppTheme.dark,
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

Future<void> _record(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const ValueKey('custom-reference-record')),
  );
  await tester.tap(find.byKey(const ValueKey('custom-reference-record')));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
  expect(find.text('Finish Reference'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('custom-reference-record')));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
      expect(find.text('Movement details'), findsWidgets);
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
        find.text('2 required  ·  3 recommended  ·  Up to 5'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('custom-movement-review')),
            )
            .onPressed,
        isNull,
      );
      socket.ready();
      for (var attempt = 0; attempt < 20; attempt++) {
        await tester.pump(const Duration(milliseconds: 50));
        if (tester
                .widget<FilledButton>(
                  find.byKey(const ValueKey('custom-reference-record')),
                )
                .onPressed !=
            null) {
          break;
        }
      }
      expect(find.textContaining('Could not prepare'), findsNothing);
      expect(
        find.text('One person ready'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((item) => item.data)
            .whereType<String>()
            .join(' | '),
      );
      expect(find.text('Preparing camera…'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('custom-reference-record')),
            )
            .onPressed,
        isNotNull,
      );
      await _record(tester);
      expect(find.textContaining('Reference 1'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('custom-movement-review')),
            )
            .onPressed,
        isNull,
      );
      await _record(tester);
      expect(find.textContaining('Reference 2'), findsOneWidget);
      expect(
        find.textContaining('A third reference is recommended'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
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
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('custom-movement-save')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Previous'));
      await tester.pump(const Duration(milliseconds: 100));
      for (var index = 0; index < 3; index++) {
        await _record(tester);
      }
      expect(find.textContaining('5 reference limit'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('custom-reference-record')),
            )
            .onPressed,
        isNull,
      );
      final previews = find.text('Preview / Trim');
      await tester.ensureVisible(previews.at(1));
      await tester.tap(previews.at(1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('reference-player-reference-2')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Apply trim'));
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(1000);
      await tester.pump();
      expect(find.text('Start: 00:01.00'), findsOneWidget);
      await tester.tap(find.text('Apply trim'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(socket.trimmed, ['reference-2']);
      await tester.ensureVisible(find.text('Reset trim'));
      await tester.tap(find.text('Reset trim'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Start: 00:00.00'), findsOneWidget);
      expect(find.text('Selected duration: 00:07.00'), findsOneWidget);
      expect(socket.trimmed, ['reference-2', 'reference-2']);
      await tester.ensureVisible(find.text('Delete').at(1));
      await tester.tap(find.text('Delete').at(1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(socket.deleted, ['reference-2']);
      expect(
        find.byKey(const ValueKey('reference-player-reference-2')),
        findsNothing,
      );
      expect(find.textContaining('Reference 4'), findsOneWidget);
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
        find.textContaining('Earlier raw videos were not saved'),
        findsOneWidget,
      );
      expect(find.text('Record new references'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('custom-movement-review')),
      );
      await tester.tap(find.byKey(const ValueKey('custom-movement-review')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester
            .widget<FilledButton>(
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
      expect(find.textContaining('visible bottle rotation'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
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
            .widget<FilledButton>(
              find.byKey(const ValueKey('custom-movement-review')),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
