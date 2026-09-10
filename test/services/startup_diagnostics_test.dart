import 'dart:async';
import 'dart:convert';

import 'package:elixr_application/services/startup_diagnostics.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClock {
  Duration now = Duration.zero;

  Duration call() => now;

  void advance(int milliseconds) {
    now += Duration(milliseconds: milliseconds);
  }
}

void main() {
  group('startup percentile', () {
    test('nearest-rank is deterministic and empty is null', () {
      expect(startupPercentile(<double>[], 50), isNull);
      expect(startupPercentile(<double>[10, 20, 30, 40, 50], 50), 30);
      expect(startupPercentile(<double>[10, 20, 30, 40, 50], 95), 50);
      final twenty = List<double>.generate(20, (index) => index.toDouble());
      expect(startupPercentile(twenty, 95), 18);
    });
  });

  group('StartupDiagnosticsRecorder', () {
    test('start action establishes client measurement origin', () {
      final clock = _FakeClock();
      final sink = MemoryStartupDiagnosticSink();
      final recorder = StartupDiagnosticsRecorder(
        clock: clock.call,
        sink: sink,
        persist: false,
        environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
      );
      recorder.beginAttempt(sessionId: 'session-1', sessionMode: 'guided');
      clock.advance(250);
      recorder.markFirstPreview(sessionId: 'session-1');
      final record = recorder.toRecord();
      expect(record['durations_ms']['client_first_preview'], 250);
      expect(sink.writeCalls, 0);
    });

    test('first preview is recorded once; later frames do not replace it', () {
      final clock = _FakeClock();
      final recorder = StartupDiagnosticsRecorder(
        clock: clock.call,
        sink: RaisingStartupDiagnosticSink(),
        persist: false,
        environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
      );
      recorder.beginAttempt(sessionId: 'session-1');
      clock.advance(100);
      recorder.markFirstPreview(sessionId: 'session-1');
      clock.advance(400);
      recorder.markFirstPreview(sessionId: 'session-1');
      expect(recorder.markAttempts('client_first_preview'), 2);
      expect(recorder.durationsMs()[startupDurationClientFirstPreview], 100);
    });

    test('stale session frames do not update the current diagnostic', () {
      final clock = _FakeClock();
      final recorder = StartupDiagnosticsRecorder(
        clock: clock.call,
        persist: false,
        environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
      );
      recorder.beginAttempt(sessionId: 'session-old');
      clock.advance(50);
      recorder.beginAttempt(sessionId: 'session-new');
      clock.advance(10);
      recorder.markFirstPreview(sessionId: 'session-old');
      expect(recorder.durationsMs()[startupDurationClientFirstPreview], isNull);
      recorder.markFirstPreview(sessionId: 'session-new');
      expect(recorder.durationsMs()[startupDurationClientFirstPreview], 10);
    });

    test('missing milestones stay null rather than zero', () {
      final recorder = StartupDiagnosticsRecorder(
        clock: _FakeClock().call,
        persist: false,
        environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
      );
      recorder.beginAttempt(sessionId: 'session-1');
      final durations = recorder.durationsMs();
      expect(durations[startupDurationClientFirstPreview], isNull);
      expect(durations[startupDurationPrepare], isNull);
      expect(durations[startupDurationActivateAck], isNull);
      expect(durations.values.where((value) => value == 0), isEmpty);
    });

    test('failed sample records the milestone instead of zero durations', () {
      final recorder = StartupDiagnosticsRecorder(
        clock: _FakeClock().call,
        persist: false,
        environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
      );
      recorder.beginAttempt(sessionId: 'session-1');
      recorder.fail('prepare', 'camera_unavailable');
      final record = recorder.toRecord();
      expect(record['status'], 'failed');
      expect(record['failed_milestone'], 'prepare');
      expect(record['durations_ms']['prepare'], isNull);
    });

    test('activation uses matching request id only', () {
      final clock = _FakeClock();
      final recorder = StartupDiagnosticsRecorder(
        clock: clock.call,
        persist: false,
        environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
      );
      recorder.beginAttempt(sessionId: 'session-1');
      recorder.markActivateSent(sessionId: 'session-1', requestId: 'req-a');
      clock.advance(12);
      recorder.markActivateAck(
        sessionId: 'session-1',
        requestId: 'req-other',
        accepted: true,
      );
      expect(recorder.durationsMs()[startupDurationActivateAck], isNull);
      recorder.markActivateAck(
        sessionId: 'session-1',
        requestId: 'req-a',
        accepted: true,
      );
      expect(recorder.durationsMs()[startupDurationActivateAck], 12);
    });

    test('serialization contains no image payload', () {
      final recorder = StartupDiagnosticsRecorder(
        clock: _FakeClock().call,
        persist: false,
        environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
      );
      recorder.beginAttempt(sessionId: 'session-1');
      recorder.markFirstPreview(sessionId: 'session-1');
      final record = recorder.toRecord();
      expect(recordContainsImagePayload(record), isFalse);
      expect(jsonEncode(record), isNot(contains('frame_jpeg_base64')));
    });

    test(
      'already-open socket does not report connection wait as this attempt',
      () {
        final clock = _FakeClock();
        final recorder = StartupDiagnosticsRecorder(
          clock: clock.call,
          persist: false,
          environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
        );
        recorder.markConnectStart();
        clock.advance(40);
        recorder.markConnectEnd(success: true);
        recorder.beginAttempt(sessionId: 'session-1');
        expect(recorder.toRecord()['ws_already_connected'], isTrue);
        expect(recorder.durationsMs()[startupDurationConnection], isNull);
      },
    );

    test('in-attempt connection duration is recorded once', () {
      final clock = _FakeClock();
      final recorder = StartupDiagnosticsRecorder(
        clock: clock.call,
        persist: false,
        environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
      );
      recorder.beginAttempt(sessionId: 'session-1');
      recorder.markConnectStart();
      clock.advance(40);
      recorder.markConnectEnd(success: true);
      expect(recorder.durationsMs()[startupDurationConnection], 40);
      clock.advance(10);
      recorder.markConnectEnd(success: true);
      expect(recorder.durationsMs()[startupDurationConnection], 40);
    });

    test('teardown does not leak timing into the next attempt', () {
      final clock = _FakeClock();
      final recorder = StartupDiagnosticsRecorder(
        clock: clock.call,
        persist: false,
        environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
      );
      recorder.beginAttempt(sessionId: 'session-1');
      clock.advance(80);
      recorder.markFirstPreview(sessionId: 'session-1');
      recorder.teardown();
      recorder.beginAttempt(sessionId: 'session-2');
      expect(recorder.durationsMs()[startupDurationClientFirstPreview], isNull);
      clock.advance(15);
      recorder.markFirstPreview(sessionId: 'session-2');
      expect(recorder.durationsMs()[startupDurationClientFirstPreview], 15);
    });

    test('unstable camera identity is not an OpenCV index', () {
      final fallback = cameraDiagnosticIdentity(
        deviceId: 'opencv:1',
        identityStable: false,
      );
      expect(fallback['camera_diagnostic_id'], 'opencv_fallback');
      expect(fallback['identity_stable'], isFalse);
    });
  });

  group('WebSocketService startup diagnostics', () {
    late StreamController<dynamic> inbound;
    late StreamController<dynamic> outbound;
    late List<Map<String, dynamic>> sent;
    late WebSocketService service;
    late _FakeClock clock;
    late MemoryStartupDiagnosticSink sink;

    setUp(() {
      inbound = StreamController<dynamic>.broadcast();
      outbound = StreamController<dynamic>.broadcast();
      sent = <Map<String, dynamic>>[];
      outbound.stream.listen((event) {
        if (event is String) {
          sent.add(jsonDecode(event) as Map<String, dynamic>);
        }
      });
      clock = _FakeClock();
      sink = MemoryStartupDiagnosticSink();
      service = WebSocketService(
        commandTimeout: const Duration(milliseconds: 80),
        prepareTimeout: const Duration(milliseconds: 80),
        startupDiagnostics: StartupDiagnosticsRecorder(
          clock: clock.call,
          sink: sink,
          persist: false,
          environment: const {'ELIXR_PILOT_DEVICE_ID': 'pilot-1'},
        ),
      );
      service.debugAttachTransport(
        inbound: inbound.stream,
        outbound: outbound.sink,
      );
    });

    tearDown(() async {
      service.dispose();
      await inbound.close();
      await outbound.close();
    });

    Future<void> push(Map<String, dynamic> payload) async {
      inbound.add(jsonEncode(payload));
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> ackLatest({
      required String action,
      required String sessionId,
      bool accepted = true,
      String? sessionState,
    }) async {
      await Future<void>.delayed(Duration.zero);
      final requestId = sent.last['request_id'] as String;
      inbound.add(
        jsonEncode({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': requestId,
          'session_id': sessionId,
          'action': action,
          'accepted': accepted,
          'session_state': ?sessionState,
        }),
      );
      await Future<void>.delayed(Duration.zero);
    }

    test(
      'camera start plus first current-session JPEG records preview once',
      () async {
        final sessionId = service.beginPracticeAttempt();
        final prepare = service.sendPrepare(
          movement: 'Hand Stall',
          difficulty: 'Easy',
          sessionId: sessionId,
        );
        await ackLatest(
          action: 'prepare',
          sessionId: sessionId,
          sessionState: 'preparing',
        );
        await prepare;
        clock.advance(90);
        await push({
          'protocol_version': 1,
          'message_type': 'preview_frame',
          'session_id': sessionId,
          'frame_jpeg_base64': 'AQID',
          'camera_ready': true,
          'session_state': 'preparing',
        });
        clock.advance(200);
        await push({
          'protocol_version': 1,
          'message_type': 'preview_frame',
          'session_id': sessionId,
          'frame_jpeg_base64': 'BAUG',
          'camera_ready': true,
          'session_state': 'preparing',
        });
        expect(
          service.startupDiagnostics
              .durationsMs()[startupDurationClientFirstPreview],
          90,
        );
        expect(sink.writeCalls, 0);
      },
    );

    test(
      'previous-session JPEG does not update the current diagnostic',
      () async {
        final firstId = service.beginPracticeAttempt();
        final secondId = service.beginPracticeAttempt();
        clock.advance(5);
        await push({
          'protocol_version': 1,
          'message_type': 'preview_frame',
          'session_id': firstId,
          'frame_jpeg_base64': 'AQID',
          'camera_ready': true,
        });
        expect(
          service.startupDiagnostics
              .durationsMs()[startupDurationClientFirstPreview],
          isNull,
        );
        await push({
          'protocol_version': 1,
          'message_type': 'preview_frame',
          'session_id': secondId,
          'frame_jpeg_base64': 'AQID',
          'camera_ready': true,
        });
        expect(
          service.startupDiagnostics
              .durationsMs()[startupDurationClientFirstPreview],
          5,
        );
      },
    );

    test(
      'activation timing uses matching correlated acknowledgement',
      () async {
        final sessionId = service.beginPracticeAttempt();
        final prepare = service.sendPrepare(
          movement: 'Hand Stall',
          difficulty: 'Easy',
          sessionId: sessionId,
        );
        await ackLatest(
          action: 'prepare',
          sessionId: sessionId,
          sessionState: 'preparing',
        );
        await prepare;

        final activate = service.sendActivate(sessionId: sessionId);
        await Future<void>.delayed(Duration.zero);
        final activateRequest = sent.last['request_id'] as String;
        clock.advance(18);
        inbound.add(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'command_ack',
            'request_id': 'stale-req',
            'session_id': sessionId,
            'action': 'activate',
            'accepted': true,
            'session_state': 'active',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          service.startupDiagnostics.durationsMs()[startupDurationActivateAck],
          isNull,
        );
        inbound.add(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'command_ack',
            'request_id': activateRequest,
            'session_id': sessionId,
            'action': 'activate',
            'accepted': true,
            'session_state': 'active',
          }),
        );
        await activate;
        expect(
          service.startupDiagnostics.durationsMs()[startupDurationActivateAck],
          18,
        );
      },
    );

    test(
      'dispose teardown does not leak first-preview into the next service use',
      () async {
        final sessionId = service.beginPracticeAttempt();
        clock.advance(11);
        await push({
          'protocol_version': 1,
          'message_type': 'preview_frame',
          'session_id': sessionId,
          'frame_jpeg_base64': 'AQID',
          'camera_ready': true,
        });
        expect(
          service.startupDiagnostics
              .durationsMs()[startupDurationClientFirstPreview],
          11,
        );
        service.dispose();
        expect(service.startupDiagnostics.sessionId, isNull);
      },
    );
  });
}
