import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/features/teacher/movements/teacher_demo_recording_dialog.dart';
import 'package:elixr_application/services/camera_device_service.dart';
import 'package:elixr_application/services/settings_service.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Settings extends SettingsService {
  String? deviceId = 'dev-a';

  @override
  String? get selectedCameraDeviceId => deviceId;

  @override
  Future<String?> loadSelectedCameraDeviceId() async => deviceId;

  @override
  Future<SettingsWriteOutcome> setSelectedCameraDevice(
    String? nextDeviceId, {
    String? displayName,
  }) async {
    deviceId = nextDeviceId;
    notifyListeners();
    return SettingsWriteOutcome.saved;
  }
}

class _Socket extends WebSocketService {
  final preparedIds = <String?>[];
  int stopCalls = 0;
  bool rejectNextStop = false;

  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  CommandAck _ack(String action) => CommandAck(
    protocolVersion: 1,
    requestId: 'req-$action',
    action: action,
    accepted: true,
    sessionId: currentSessionId,
    sessionState: action == 'stop' ? 'idle' : 'preparing',
  );

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
    preparedIds.add(cameraDeviceId);
    return _ack('prepare');
  }

  @override
  Future<CommandAck> stopPracticeSession({String? sessionId}) async {
    stopCalls++;
    if (rejectNextStop) {
      rejectNextStop = false;
      return CommandAck(
        protocolVersion: 1,
        requestId: 'req-stop-rejected',
        action: 'stop',
        accepted: false,
        sessionId: sessionId,
        sessionState: 'preparing',
      );
    }
    return _ack('stop');
  }

  @override
  Future<CommandAck> sendStartSubmissionRecord({
    String? sessionId,
    int durationSeconds = 60,
  }) async => _ack('start_submission_record');
}

void main() {
  testWidgets('teacher demo stops before repreparing and locks while recording', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final settings = _Settings();
    final socket = _Socket();
    addTearDown(settings.dispose);
    addTearDown(socket.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<CameraDeviceService>(
            create: (_) => CameraDeviceService(
              httpGet: (_) async =>
                  '{"cameras":[{"device_id":"dev-a","display_name":"Camera A","runtime_index":0,"is_active":false,"identity_stable":true},{"device_id":"dev-b","display_name":"Camera B","runtime_index":1,"is_active":false,"identity_stable":true}],"active_index":null}',
            ),
          ),
        ],
        child: FluentApp(
          theme: AppTheme.highContrastDark,
          builder: (context, child) =>
              ElixShadThemeBridge(child: child ?? const SizedBox.shrink()),
          home: Builder(
            builder: (context) => Button(
              onPressed: () => showTeacherDemoRecordingDialog(
                context,
                upload:
                    ({
                      required localFile,
                      required duration,
                      required source,
                    }) async => throw UnimplementedError(),
                webSocket: socket,
              ),
              child: const Text('Open recorder'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open recorder'));
    await tester.pump();
    await tester.pump();
    expect(socket.preparedIds, ['dev-a']);
    expect(
      find.byKey(const ValueKey('camera-source-preference')),
      findsOneWidget,
    );

    socket.rejectNextStop = true;
    tester
        .widget<ComboBox<String>>(
          find.byKey(const ValueKey('camera-source-selector')),
        )
        .onChanged!('dev-b');
    await tester.pump();
    await tester.pump();
    expect(socket.stopCalls, 1);
    expect(socket.preparedIds, ['dev-a']);
    await tester.ensureVisible(find.text('Retry camera setup'));
    await tester.tap(find.text('Retry camera setup'));
    await tester.pump();
    await tester.pump();
    expect(socket.stopCalls, 2);
    expect(socket.preparedIds, ['dev-a', 'dev-b']);

    await tester.ensureVisible(find.text('Start recording'));
    await tester.tap(find.text('Start recording'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('camera-source-preference')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
  });
}
