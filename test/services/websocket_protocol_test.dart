import 'dart:async';
import 'dart:convert';

import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WsMessageDecoder', () {
    const decoder = WsMessageDecoder();

    test('legacy feedback without message_type still parses', () {
      final decoded = decoder.decode(
        jsonEncode({
          'bottle_detected': true,
          'movement': 'Hand Stall',
          'score': 80,
          'feedback': 'Good',
          'feedback_type': 'positive',
          'posture_status': 'stable',
        }),
      );
      expect(decoded, isA<WsFeedbackMessage>());
      final feedback = (decoded as WsFeedbackMessage).feedback;
      expect(feedback.score, 80);
      expect(feedback.sessionId, isNull);
    });

    test('version 1 feedback parses', () {
      final decoded = decoder.decode(
        jsonEncode({
          'protocol_version': 1,
          'message_type': 'feedback',
          'session_id': 'session-1',
          'bottle_detected': false,
          'movement': 'Normal Grip',
          'score': 70,
          'feedback': 'Preparing camera…',
          'feedback_type': 'positive',
          'posture_status': 'unknown',
          'session_state': 'preparing',
          'camera_ready': true,
        }),
      );
      expect(decoded, isA<WsFeedbackMessage>());
      final feedback = (decoded as WsFeedbackMessage).feedback;
      expect(feedback.sessionId, 'session-1');
      expect(feedback.messageType, 'feedback');
      expect(feedback.protocolVersion, 1);
      expect(feedback.isPreparing, isTrue);
    });

    test('command acknowledgment parses independently from feedback', () {
      final decoded = decoder.decode(
        jsonEncode({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': 'req-1',
          'session_id': 'session-1',
          'action': 'activate',
          'accepted': true,
          'session_state': 'active',
          'error_code': null,
          'message': null,
        }),
      );
      expect(decoded, isA<WsCommandAckMessage>());
      final ack = (decoded as WsCommandAckMessage).ack;
      expect(ack.accepted, isTrue);
      expect(ack.action, 'activate');
      expect(ack.sessionState, 'active');
    });

    test('malformed and unknown messages are observable without crashing', () {
      expect(decoder.decode('{bad'), isA<WsMalformedMessage>());
      expect(
        decoder.decode(jsonEncode({'message_type': 'surprise'})),
        isA<WsUnknownMessage>(),
      );
    });
  });

  group('WebSocketService protocol lifecycle', () {
    late StreamController<dynamic> inbound;
    late StreamController<dynamic> outbound;
    late WebSocketService service;
    late List<Map<String, dynamic>> sent;

    setUp(() {
      inbound = StreamController<dynamic>.broadcast();
      outbound = StreamController<dynamic>.broadcast();
      sent = <Map<String, dynamic>>[];
      outbound.stream.listen((event) {
        if (event is String) {
          sent.add(jsonDecode(event) as Map<String, dynamic>);
        }
      });
      service = WebSocketService(
        commandTimeout: const Duration(milliseconds: 80),
        prepareTimeout: const Duration(milliseconds: 80),
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

    test(
      'version 1 command payloads contain protocol and identifiers',
      () async {
        final prepareFuture = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: 'session-fixed',
        );
        await Future<void>.delayed(Duration.zero);

        expect(sent, isNotEmpty);
        expect(sent.last['protocol_version'], 1);
        expect(sent.last['action'], 'prepare');
        expect(sent.last['session_id'], 'session-fixed');
        expect(sent.last['request_id'], isNotEmpty);
        expect(sent.last['prop_type'], 'bottle');
        expect(service.sessionPrepared, isFalse);
        expect(service.sessionActive, isFalse);

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': 'session-fixed',
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        final ack = await prepareFuture;
        expect(ack.accepted, isTrue);
      },
    );

    test('sendPrepare does not optimistically set prepared state', () async {
      final future = service.sendPrepare(
        movement: 'Normal Grip',
        difficulty: 'Easy',
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.sessionPrepared, isFalse);
      expect(service.sessionActive, isFalse);

      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': sent.last['session_id'],
        'action': 'prepare',
        'accepted': true,
        'session_state': 'preparing',
      });
      await future;
      expect(service.sessionPrepared, isTrue);
      expect(service.sessionActive, isFalse);
    });

    test('sendActivate does not optimistically set active state', () async {
      service.beginPracticeAttempt();
      // Seed prepared via accepted prepare.
      final prepare = service.sendPrepare(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        sessionId: service.currentSessionId,
      );
      await Future<void>.delayed(Duration.zero);
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': service.currentSessionId,
        'action': 'prepare',
        'accepted': true,
        'session_state': 'preparing',
      });
      await prepare;

      final activate = service.sendActivate();
      await Future<void>.delayed(Duration.zero);
      expect(service.sessionActive, isFalse);

      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': service.currentSessionId,
        'action': 'activate',
        'accepted': true,
        'session_state': 'active',
      });
      await activate;
      expect(service.sessionPrepared, isTrue);
      expect(service.sessionActive, isTrue);
    });

    test('rejected activation never sets active', () async {
      service.beginPracticeAttempt();
      final activate = service.sendActivate(
        sessionId: service.currentSessionId,
      );
      await Future<void>.delayed(Duration.zero);
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': service.currentSessionId,
        'action': 'activate',
        'accepted': false,
        'session_state': 'preparing',
        'error_code': 'session_not_prepared',
        'message': 'No matching prepared session is available.',
      });
      final ack = await activate;
      expect(ack.accepted, isFalse);
      expect(service.sessionActive, isFalse);
    });

    test('accepted stop clears both states', () async {
      service.beginPracticeAttempt();
      final prepare = service.sendPrepare(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        sessionId: service.currentSessionId,
      );
      await Future<void>.delayed(Duration.zero);
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': service.currentSessionId,
        'action': 'prepare',
        'accepted': true,
        'session_state': 'preparing',
      });
      await prepare;
      expect(service.sessionPrepared, isTrue);

      final stop = service.sendStop();
      await Future<void>.delayed(Duration.zero);
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': service.currentSessionId,
        'action': 'stop',
        'accepted': true,
        'session_state': 'idle',
      });
      await stop;
      expect(service.sessionPrepared, isFalse);
      expect(service.sessionActive, isFalse);
    });

    test('stale acknowledgment from an old session is ignored', () async {
      service.beginPracticeAttempt();
      final sessionId = service.currentSessionId!;
      final prepare = service.sendPrepare(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        sessionId: sessionId,
      );
      await Future<void>.delayed(Duration.zero);
      final requestId = sent.last['request_id'];

      // Arrive with matching request id but wrong session — still completes
      // the future, but must not advance current session flags when mismatched
      // after a newer attempt begins.
      service.beginPracticeAttempt();
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': requestId,
        'session_id': sessionId,
        'action': 'prepare',
        'accepted': true,
        'session_state': 'preparing',
      });
      await prepare;
      expect(service.sessionPrepared, isFalse);
      expect(service.currentSessionId, isNot(sessionId));
    });

    test('stale feedback from an old session is ignored', () async {
      final received = <PracticeFeedback>[];
      final sub = service.feedbackStream.listen(received.add);
      service.beginPracticeAttempt();
      final current = service.currentSessionId!;

      service.debugHandleRawMessage(
        jsonEncode({
          'protocol_version': 1,
          'message_type': 'feedback',
          'session_id': 'session-old',
          'bottle_detected': true,
          'movement': 'Hand Stall',
          'score': 99,
          'feedback': 'stale',
          'feedback_type': 'positive',
          'posture_status': 'stable',
          'session_state': 'active',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, isEmpty);
      expect(service.sessionActive, isFalse);

      service.debugHandleRawMessage(
        jsonEncode({
          'protocol_version': 1,
          'message_type': 'feedback',
          'session_id': current,
          'bottle_detected': false,
          'movement': 'Hand Stall',
          'score': 70,
          'feedback': 'Preparing',
          'feedback_type': 'positive',
          'posture_status': 'unknown',
          'session_state': 'preparing',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(service.sessionPrepared, isTrue);
      await sub.cancel();
    });

    test('pending command timeout completes with controlled failure', () async {
      final future = service.sendPrepare(
        movement: 'Normal Grip',
        difficulty: 'Easy',
      );
      await expectLater(future, throwsA(isA<CommandTimeoutException>()));
      expect(service.hasPendingCommands, isFalse);
      expect(service.lastProtocolError?.errorCode, 'command_timeout');
    });

    test(
      'dispose completes pending requests without notifying listeners',
      () async {
        final future = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.hasPendingCommands, isTrue);
        service.dispose();
        await expectLater(future, throwsA(isA<CommandDisconnectedException>()));
      },
    );

    test('two simultaneous stop requests share one wire command', () async {
      service.beginPracticeAttempt();
      final sessionId = service.currentSessionId!;
      final prepare = service.sendPrepare(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        sessionId: sessionId,
      );
      await Future<void>.delayed(Duration.zero);
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': sessionId,
        'action': 'prepare',
        'accepted': true,
        'session_state': 'preparing',
      });
      await prepare;

      final stop1 = service.stopPracticeSession();
      final stop2 = service.stopPracticeSession();
      await Future<void>.delayed(Duration.zero);

      final stopPayloads = sent
          .where((payload) => payload['action'] == 'stop')
          .toList();
      expect(stopPayloads, hasLength(1));
      expect(stopPayloads.single['session_id'], sessionId);
      expect(identical(stop1, stop2), isFalse);

      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': stopPayloads.single['request_id'],
        'session_id': sessionId,
        'action': 'stop',
        'accepted': true,
        'session_state': 'idle',
      });
      final ack1 = await stop1;
      final ack2 = await stop2;
      expect(ack1.accepted, isTrue);
      expect(ack2.accepted, isTrue);
      expect(service.currentSessionId, isNull);
    });

    test(
      'Try Again allocates a fresh session while old stop is pending',
      () async {
        service.beginPracticeAttempt();
        final oldSession = service.currentSessionId!;
        final prepare = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: oldSession,
        );
        await Future<void>.delayed(Duration.zero);
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': oldSession,
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        await prepare;

        final stopFuture = service.stopPracticeSession();
        await Future<void>.delayed(Duration.zero);
        final stopRequestId = sent.last['request_id'] as String;
        expect(sent.where((p) => p['action'] == 'stop'), hasLength(1));

        final newSession = service.beginPracticeAttempt();
        expect(newSession, isNot(oldSession));
        expect(service.currentSessionId, newSession);

        final prepare2 = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: newSession,
        );
        await Future<void>.delayed(Duration.zero);
        expect(sent.last['session_id'], newSession);

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopRequestId,
          'session_id': oldSession,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopFuture;

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': newSession,
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        await prepare2;
        expect(service.currentSessionId, newSession);
        expect(service.sessionPrepared, isTrue);
      },
    );

    test(
      'delayed feedback from old attempt is ignored after stop and new start',
      () async {
        final received = <PracticeFeedback>[];
        final sub = service.feedbackStream.listen(received.add);

        service.beginPracticeAttempt();
        final oldSession = service.currentSessionId!;
        service.debugHandleRawMessage(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'feedback',
            'session_id': oldSession,
            'bottle_detected': true,
            'movement': 'Hand Stall',
            'score': 50,
            'feedback': 'active',
            'feedback_type': 'positive',
            'posture_status': 'stable',
            'session_state': 'active',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(1));

        final stopFuture = service.stopPracticeSession();
        await Future<void>.delayed(Duration.zero);
        final stopRequestId = sent.last['request_id'] as String;
        expect(service.currentSessionId, isNull);

        service.debugHandleRawMessage(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'feedback',
            'session_id': oldSession,
            'bottle_detected': true,
            'movement': 'Hand Stall',
            'score': 99,
            'feedback': 'stale after stop',
            'feedback_type': 'positive',
            'posture_status': 'stable',
            'session_state': 'active',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(1));

        final newSession = service.beginPracticeAttempt();
        service.debugHandleRawMessage(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'feedback',
            'session_id': oldSession,
            'bottle_detected': true,
            'movement': 'Hand Stall',
            'score': 88,
            'feedback': 'stale after new attempt',
            'feedback_type': 'positive',
            'posture_status': 'stable',
            'session_state': 'active',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(1));

        service.debugHandleRawMessage(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'feedback',
            'session_id': newSession,
            'bottle_detected': false,
            'movement': 'Hand Stall',
            'score': 70,
            'feedback': 'current',
            'feedback_type': 'positive',
            'posture_status': 'unknown',
            'session_state': 'preparing',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(received, hasLength(2));
        expect(received.last.sessionId, newSession);

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopRequestId,
          'session_id': oldSession,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopFuture;
        await sub.cancel();
      },
    );

    test('mismatched ack action does not complete with CommandAck', () async {
      service.beginPracticeAttempt();
      final sessionId = service.currentSessionId!;
      final prepare = service.sendPrepare(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        sessionId: sessionId,
      );
      await Future<void>.delayed(Duration.zero);
      final requestId = sent.last['request_id'];

      final mismatchExpectation = expectLater(
        prepare,
        throwsA(isA<CommandAckMismatchException>()),
      );
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': requestId,
        'session_id': sessionId,
        'action': 'stop',
        'accepted': true,
        'session_state': 'idle',
      });
      await mismatchExpectation;
      expect(service.sessionPrepared, isFalse);
      expect(service.sessionActive, isFalse);
      expect(service.lastProtocolError?.errorCode, 'ack_action_mismatch');
    });

    test(
      'mismatched ack session id does not activate a newer session',
      () async {
        service.beginPracticeAttempt();
        final oldSession = service.currentSessionId!;
        final prepare = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: oldSession,
        );
        await Future<void>.delayed(Duration.zero);
        final requestId = sent.last['request_id'];

        service.beginPracticeAttempt();
        final newSession = service.currentSessionId!;
        expect(newSession, isNot(oldSession));

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': requestId,
          'session_id': oldSession,
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        await prepare;
        expect(service.sessionPrepared, isFalse);
        expect(service.currentSessionId, newSession);
      },
    );

    test(
      'ack session_id mismatch against pending command fails the future',
      () async {
        service.beginPracticeAttempt();
        final sessionId = service.currentSessionId!;
        final prepare = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: sessionId,
        );
        await Future<void>.delayed(Duration.zero);
        final requestId = sent.last['request_id'];

        final mismatchExpectation = expectLater(
          prepare,
          throwsA(isA<CommandAckMismatchException>()),
        );
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': requestId,
          'session_id': 'session-wrong',
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        await mismatchExpectation;
        expect(service.sessionPrepared, isFalse);
        expect(service.sessionActive, isFalse);
        expect(service.lastProtocolError?.errorCode, 'ack_session_mismatch');
      },
    );

    test('stop for a different session does not join pending stop', () async {
      service.beginPracticeAttempt();
      final sessionA = service.currentSessionId!;

      final stopA = service.stopPracticeSession(sessionId: sessionA);
      await Future<void>.delayed(Duration.zero);

      final stopPayloads = sent
          .where((payload) => payload['action'] == 'stop')
          .toList();
      expect(stopPayloads, hasLength(1));
      expect(stopPayloads.single['session_id'], sessionA);

      final stopB = service.stopPracticeSession(sessionId: 'session-b-other');
      await expectLater(stopB, throwsA(isA<StateError>()));
      expect(
        sent.where((payload) => payload['action'] == 'stop'),
        hasLength(1),
      );
      expect(identical(stopA, stopB), isFalse);

      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': stopPayloads.single['request_id'],
        'session_id': sessionA,
        'action': 'stop',
        'accepted': true,
        'session_state': 'idle',
      });
      final ackA = await stopA;
      expect(ackA.accepted, isTrue);
      expect(ackA.action, 'stop');
    });

    test('correct ack still completes pending command normally', () async {
      service.beginPracticeAttempt();
      final sessionId = service.currentSessionId!;
      final prepare = service.sendPrepare(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        sessionId: sessionId,
      );
      await Future<void>.delayed(Duration.zero);

      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': sessionId,
        'action': 'prepare',
        'accepted': true,
        'session_state': 'preparing',
      });
      final ack = await prepare;
      expect(ack, isA<CommandAck>());
      expect(ack.accepted, isTrue);
      expect(ack.action, 'prepare');
      expect(service.sessionPrepared, isTrue);
      expect(service.sessionActive, isFalse);
    });

    test(
      'feedback with session_id is ignored when current session is null',
      () async {
        final received = <PracticeFeedback>[];
        final sub = service.feedbackStream.listen(received.add);
        expect(service.currentSessionId, isNull);

        service.debugHandleRawMessage(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'feedback',
            'session_id': 'session-orphan',
            'bottle_detected': true,
            'movement': 'Hand Stall',
            'score': 42,
            'feedback': 'orphan',
            'feedback_type': 'positive',
            'posture_status': 'stable',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(received, isEmpty);
        await sub.cancel();
      },
    );

    test('legacy feedback without session_id still forwards', () async {
      final received = <PracticeFeedback>[];
      final sub = service.feedbackStream.listen(received.add);

      service.debugHandleRawMessage(
        jsonEncode({
          'bottle_detected': true,
          'movement': 'Hand Stall',
          'score': 80,
          'feedback': 'legacy',
          'feedback_type': 'positive',
          'posture_status': 'stable',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      await sub.cancel();
    });

    test('duplicate pending commands are rejected deterministically', () async {
      final first = service.sendPrepare(
        movement: 'Normal Grip',
        difficulty: 'Easy',
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        () => service.sendPrepare(movement: 'Normal Grip', difficulty: 'Easy'),
        throwsA(isA<StateError>()),
      );
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': sent.last['session_id'],
        'action': 'prepare',
        'accepted': true,
        'session_state': 'preparing',
      });
      await first;
    });

    test(
      'malformed inbound messages increment protocol error observability',
      () async {
        final errors = <ProtocolErrorMessage>[];
        final sub = service.protocolErrorStream.listen(errors.add);
        service.debugHandleRawMessage('{nope');
        await Future<void>.delayed(Duration.zero);
        expect(errors, isNotEmpty);
        expect(service.protocolErrorCount, greaterThan(0));
        expect(service.lastProtocolError?.errorCode, 'invalid_json');
        await sub.cancel();
      },
    );
  });

  test('shaker prepare payload preserves the selected prop', () {
    final payload = WebSocketService.buildPreparePayload(
      movement: 'Hand Stall',
      difficulty: 'Medium',
      prop: TrainingProp.shaker,
      sessionId: 'session-shaker',
      requestId: 'req-shaker',
    );

    expect(payload['prop_type'], 'shaker');
    expect(payload['bottle_detection_enabled'], isTrue);
  });

  group('guided-practice countdown still follows lifecycle helpers', () {
    test('countdown waits for preview JPEG after preparing', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      expect(run.phase, PracticeRunPhase.preparingCamera);
      expect(
        run.onPreviewFeedback(hasJpegFrame: false, isFatal: false),
        isFalse,
      );
      expect(run.onPreviewFeedback(hasJpegFrame: true, isFatal: false), isTrue);
      run.enterCountdown();
      expect(run.phase, PracticeRunPhase.countdown);
      expect(run.isTrainingActive, isFalse);
      run.enterActive();
      expect(run.isTrainingActive, isTrue);
      run.dispose();
    });
  });
}
