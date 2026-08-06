import 'dart:async';
import 'dart:convert';

import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors practice-screen teardown: controlled stop failures must not escape.
Future<void> _swallowControlledStopFailures(Future<CommandAck> future) async {
  try {
    await future;
  } on CommandTimeoutException {
    // Expected when the backend is slow or unavailable.
  } on CommandAckMismatchException {
    // Stop ack did not match; session identity was already cleared.
  } on CommandDisconnectedException {
    // Expected during navigation or dispose.
  }
}

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
      expect(feedback.feedbackCode, isNull);
      expect(feedback.feedbackCategory, isNull);
      expect(feedback.holdTargetMs, 0);
    });

    test('optional coaching fields parse from feedback JSON', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': true,
        'movement': 'Hand Stall',
        'score': 85,
        'feedback': 'Hand stall locked in.',
        'feedback_type': 'positive',
        'posture_status': 'stable',
        'session_state': 'active',
        'hold_target_ms': 2500,
        'feedback_code': 'hand_stall_locked',
        'feedback_category': 'technique',
      });
      expect(feedback.holdTargetMs, 2500);
      expect(feedback.feedbackCode, 'hand_stall_locked');
      expect(feedback.feedbackCategory, 'technique');
    });

    test('invalid hold_target_ms defaults to zero', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': true,
        'movement': 'Hand Stall',
        'score': 70,
        'feedback': 'Keep steady',
        'feedback_type': 'warning',
        'posture_status': 'unstable',
        'hold_target_ms': 'nope',
      });
      expect(feedback.holdTargetMs, 0);
    });

    test('legacy payload omitting coaching fields parses safely', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': true,
        'movement': 'Hand Stall',
        'score': 72,
        'feedback': 'Keep the bottle upright on your palm.',
        'feedback_type': 'warning',
        'posture_status': 'unstable',
        'session_state': 'active',
      });
      expect(feedback.feedbackCode, isNull);
      expect(feedback.feedbackCategory, isNull);
      expect(feedback.holdTargetMs, 0);
      expect(feedback.feedback, 'Keep the bottle upright on your palm.');
    });

    test('unknown feedback code and category remain parseable', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': true,
        'movement': 'Hand Stall',
        'score': 65,
        'feedback': 'Keep steady',
        'feedback_type': 'warning',
        'posture_status': 'unstable',
        'session_state': 'active',
        'feedback_code': 'totally_unknown_future_code',
        'feedback_category': 'mystery_bucket',
        'hold_target_ms': 2500,
      });
      expect(feedback.feedbackCode, 'totally_unknown_future_code');
      expect(feedback.feedbackCategory, 'mystery_bucket');
      expect(feedback.holdTargetMs, 2500);
    });

    test('preparing and inactive frames default coaching fields safely', () {
      for (final state in ['preparing', 'inactive']) {
        final feedback = PracticeFeedback.fromJson({
          'bottle_detected': false,
          'movement': 'Hand Stall',
          'score': 70,
          'feedback': 'Preparing camera…',
          'feedback_type': 'positive',
          'posture_status': 'unknown',
          'session_state': state,
        });
        expect(feedback.feedbackCode, isNull, reason: state);
        expect(feedback.feedbackCategory, isNull, reason: state);
        expect(feedback.holdTargetMs, 0, reason: state);
      }
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

    test(
      'different-session stops serialize without premature wire send',
      () async {
        service.beginPracticeAttempt();
        final sessionA = service.currentSessionId!;

        final stopA = service.stopPracticeSession(sessionId: sessionA);
        await Future<void>.delayed(Duration.zero);

        final stopPayloads = sent
            .where((payload) => payload['action'] == 'stop')
            .toList();
        expect(stopPayloads, hasLength(1));
        expect(stopPayloads.single['session_id'], sessionA);
        final stopARequestId = stopPayloads.single['request_id'] as String;

        final stopB = service.stopPracticeSession(sessionId: 'session-b-other');
        await Future<void>.delayed(Duration.zero);

        expect(
          sent.where((payload) => payload['action'] == 'stop'),
          hasLength(1),
        );
        expect(identical(stopA, stopB), isFalse);

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopARequestId,
          'session_id': sessionA,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        final ackA = await stopA;
        expect(ackA.accepted, isTrue);
        expect(ackA.requestId, stopARequestId);

        await Future<void>.delayed(Duration.zero);
        final allStopPayloads = sent
            .where((payload) => payload['action'] == 'stop')
            .toList();
        expect(allStopPayloads, hasLength(2));
        expect(allStopPayloads.last['session_id'], 'session-b-other');
        final stopBRequestId = allStopPayloads.last['request_id'] as String;
        expect(stopBRequestId, isNot(stopARequestId));

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopBRequestId,
          'session_id': 'session-b-other',
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        final ackB = await stopB;
        expect(ackB.accepted, isTrue);
        expect(ackB.requestId, stopBRequestId);
        expect(ackB.requestId, isNot(ackA.requestId));
      },
    );

    test(
      'queued stop B still sends after stop A times out while connected',
      () async {
        service.beginPracticeAttempt();
        final sessionA = service.currentSessionId!;

        final stopA = service.stopPracticeSession(sessionId: sessionA);
        await Future<void>.delayed(Duration.zero);
        final stopARequestId = sent.last['request_id'] as String;

        final stopB = service.stopPracticeSession(
          sessionId: 'session-b-timeout',
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          sent.where((payload) => payload['action'] == 'stop'),
          hasLength(1),
        );

        await expectLater(stopA, throwsA(isA<CommandTimeoutException>()));
        await Future<void>.delayed(Duration.zero);

        final stopPayloads = sent
            .where((payload) => payload['action'] == 'stop')
            .toList();
        expect(stopPayloads, hasLength(2));
        expect(stopPayloads.last['session_id'], 'session-b-timeout');
        final stopBRequestId = stopPayloads.last['request_id'] as String;

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopBRequestId,
          'session_id': 'session-b-timeout',
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        final ackB = await stopB;
        expect(ackB.accepted, isTrue);
        expect(ackB.requestId, stopBRequestId);
        expect(ackB.requestId, isNot(stopARequestId));
      },
    );

    test(
      'queued stop B still sends after stop A ack mismatch while connected',
      () async {
        service.beginPracticeAttempt();
        final sessionA = service.currentSessionId!;

        final stopA = service.stopPracticeSession(sessionId: sessionA);
        await Future<void>.delayed(Duration.zero);
        final stopARequestId = sent.last['request_id'] as String;

        final stopB = service.stopPracticeSession(
          sessionId: 'session-b-mismatch',
        );
        await Future<void>.delayed(Duration.zero);

        final mismatchExpectation = expectLater(
          stopA,
          throwsA(isA<CommandAckMismatchException>()),
        );
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopARequestId,
          'session_id': sessionA,
          'action': 'activate',
          'accepted': true,
          'session_state': 'active',
        });
        await mismatchExpectation;
        await Future<void>.delayed(Duration.zero);

        final stopPayloads = sent
            .where((payload) => payload['action'] == 'stop')
            .toList();
        expect(stopPayloads, hasLength(2));
        expect(stopPayloads.last['session_id'], 'session-b-mismatch');
        final stopBRequestId = stopPayloads.last['request_id'] as String;

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopBRequestId,
          'session_id': 'session-b-mismatch',
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        final ackB = await stopB;
        expect(ackB.accepted, isTrue);
      },
    );

    test(
      'late stop ack for session A does not clear newer session B lifecycle',
      () async {
        service.beginPracticeAttempt();
        final sessionA = service.currentSessionId!;
        final prepareA = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: sessionA,
        );
        await Future<void>.delayed(Duration.zero);
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': sessionA,
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        await prepareA;

        final stopA = service.stopPracticeSession(sessionId: sessionA);
        await Future<void>.delayed(Duration.zero);
        final stopARequestId = sent.last['request_id'] as String;

        final sessionB = service.beginPracticeAttempt();
        final prepareB = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: sessionB,
        );
        await Future<void>.delayed(Duration.zero);
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': sessionB,
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        await prepareB;
        expect(service.currentSessionId, sessionB);
        expect(service.sessionPrepared, isTrue);

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopARequestId,
          'session_id': sessionA,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopA;
        expect(service.currentSessionId, sessionB);
        expect(service.sessionPrepared, isTrue);

        final stopB = service.stopPracticeSession(sessionId: sessionB);
        await Future<void>.delayed(Duration.zero);
        expect(service.currentSessionId, isNull);

        final stopBPayloads = sent
            .where(
              (payload) =>
                  payload['action'] == 'stop' &&
                  payload['session_id'] == sessionB,
            )
            .toList();
        expect(stopBPayloads, hasLength(1));

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopBPayloads.single['request_id'],
          'session_id': sessionB,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopB;
        expect(service.currentSessionId, isNull);
        expect(service.sessionPrepared, isFalse);
      },
    );

    test(
      'queued stop C cannot bypass queued stop B after in-flight stop A settles',
      () async {
        service.beginPracticeAttempt();
        final sessionA = service.currentSessionId!;

        final stopA = service.stopPracticeSession(sessionId: sessionA);
        await Future<void>.delayed(Duration.zero);

        final stopB = service.stopPracticeSession(sessionId: 'session-b-queue');
        await Future<void>.delayed(Duration.zero);

        final stopPayloadsAfterB = sent
            .where((payload) => payload['action'] == 'stop')
            .toList();
        expect(stopPayloadsAfterB, hasLength(1));
        expect(stopPayloadsAfterB.single['session_id'], sessionA);
        final stopARequestId =
            stopPayloadsAfterB.single['request_id'] as String;

        inbound.add(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'command_ack',
            'request_id': stopARequestId,
            'session_id': sessionA,
            'action': 'stop',
            'accepted': true,
            'session_state': 'idle',
          }),
        );

        final stopC = service.stopPracticeSession(sessionId: 'session-c-queue');
        expect(
          sent.where((payload) => payload['action'] == 'stop'),
          hasLength(1),
        );

        await Future<void>.delayed(Duration.zero);

        final stopPayloadsAfterDrain = sent
            .where((payload) => payload['action'] == 'stop')
            .toList();
        expect(stopPayloadsAfterDrain, hasLength(2));
        expect(stopPayloadsAfterDrain[1]['session_id'], 'session-b-queue');
        final stopBRequestId =
            stopPayloadsAfterDrain[1]['request_id'] as String;
        expect(stopBRequestId, isNot(stopARequestId));

        final ackA = await stopA;
        expect(ackA.requestId, stopARequestId);

        await Future<void>.delayed(Duration.zero);

        final stopPayloadsBeforeC = sent
            .where((payload) => payload['action'] == 'stop')
            .toList();
        expect(stopPayloadsBeforeC, hasLength(2));
        expect(stopPayloadsBeforeC[0]['session_id'], sessionA);
        expect(stopPayloadsBeforeC[1]['session_id'], 'session-b-queue');

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopBRequestId,
          'session_id': 'session-b-queue',
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        final ackB = await stopB;
        expect(ackB.requestId, stopBRequestId);

        await Future<void>.delayed(Duration.zero);

        final allStopPayloads = sent
            .where((payload) => payload['action'] == 'stop')
            .toList();
        expect(allStopPayloads, hasLength(3));
        expect(allStopPayloads[0]['session_id'], sessionA);
        expect(allStopPayloads[1]['session_id'], 'session-b-queue');
        expect(allStopPayloads[2]['session_id'], 'session-c-queue');
        final stopCRequestId = allStopPayloads[2]['request_id'] as String;
        expect(stopCRequestId, isNot(stopARequestId));
        expect(stopCRequestId, isNot(stopBRequestId));

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopCRequestId,
          'session_id': 'session-c-queue',
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        final ackC = await stopC;
        expect(ackC.requestId, stopCRequestId);
      },
    );

    test(
      'repeated requests for a queued stop share one future and one wire command',
      () async {
        service.beginPracticeAttempt();
        final sessionA = service.currentSessionId!;

        final stopA = service.stopPracticeSession(sessionId: sessionA);
        await Future<void>.delayed(Duration.zero);

        final stopB1 = service.stopPracticeSession(sessionId: 'session-b-dup');
        final stopB2 = service.stopPracticeSession(sessionId: 'session-b-dup');
        await Future<void>.delayed(Duration.zero);

        expect(
          sent.where((payload) => payload['action'] == 'stop'),
          hasLength(1),
        );
        expect(identical(stopB1, stopB2), isTrue);

        final stopARequestId = sent.last['request_id'] as String;
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopARequestId,
          'session_id': sessionA,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopA;
        await Future<void>.delayed(Duration.zero);

        final stopBPayloads = sent
            .where(
              (payload) =>
                  payload['action'] == 'stop' &&
                  payload['session_id'] == 'session-b-dup',
            )
            .toList();
        expect(stopBPayloads, hasLength(1));

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopBPayloads.single['request_id'],
          'session_id': 'session-b-dup',
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        final ackB1 = await stopB1;
        final ackB2 = await stopB2;
        expect(ackB1.requestId, ackB2.requestId);
      },
    );

    test(
      'queued stop for current session clears identity and rejects feedback immediately',
      () async {
        final received = <PracticeFeedback>[];
        final sub = service.feedbackStream.listen(received.add);

        service.beginPracticeAttempt();
        final sessionA = service.currentSessionId!;

        final stopA = service.stopPracticeSession(sessionId: sessionA);
        await Future<void>.delayed(Duration.zero);

        service.beginPracticeAttempt();
        final sessionB = service.currentSessionId!;
        final prepareB = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: sessionB,
        );
        await Future<void>.delayed(Duration.zero);
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': sessionB,
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        await prepareB;
        expect(service.sessionPrepared, isTrue);

        final stopB = service.stopPracticeSession(sessionId: sessionB);
        expect(service.currentSessionId, isNull);
        expect(service.sessionPrepared, isFalse);
        expect(service.sessionActive, isFalse);

        service.debugHandleRawMessage(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'feedback',
            'session_id': sessionB,
            'bottle_detected': true,
            'movement': 'Hand Stall',
            'score': 55,
            'feedback': 'stale after queued stop',
            'feedback_type': 'positive',
            'posture_status': 'stable',
            'session_state': 'active',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(received, isEmpty);

        final newSession = service.beginPracticeAttempt();
        expect(newSession, isNot(sessionB));
        expect(service.currentSessionId, newSession);

        final stopARequestId =
            sent
                    .where((payload) => payload['action'] == 'stop')
                    .single['request_id']
                as String;
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopARequestId,
          'session_id': sessionA,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopA;
        await Future<void>.delayed(Duration.zero);

        final stopBPayloads = sent
            .where(
              (payload) =>
                  payload['action'] == 'stop' &&
                  payload['session_id'] == sessionB,
            )
            .toList();
        expect(stopBPayloads, hasLength(1));

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopBPayloads.single['request_id'],
          'session_id': sessionB,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopB;
        expect(service.currentSessionId, newSession);
        await sub.cancel();
      },
    );

    test(
      'late acks for queued stops A and B do not clear a newer session C',
      () async {
        service.beginPracticeAttempt();
        final sessionA = service.currentSessionId!;
        final prepareA = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: sessionA,
        );
        await Future<void>.delayed(Duration.zero);
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': sessionA,
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        await prepareA;

        final stopA = service.stopPracticeSession(sessionId: sessionA);
        await Future<void>.delayed(Duration.zero);
        final stopARequestId = sent.last['request_id'] as String;

        final stopB = service.stopPracticeSession(sessionId: 'session-b-late');
        await Future<void>.delayed(Duration.zero);

        final sessionC = service.beginPracticeAttempt();
        final prepareC = service.sendPrepare(
          movement: 'Normal Grip',
          difficulty: 'Easy',
          sessionId: sessionC,
        );
        await Future<void>.delayed(Duration.zero);
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': sessionC,
          'action': 'prepare',
          'accepted': true,
          'session_state': 'preparing',
        });
        await prepareC;
        expect(service.currentSessionId, sessionC);
        expect(service.sessionPrepared, isTrue);

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopARequestId,
          'session_id': sessionA,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopA;
        await Future<void>.delayed(Duration.zero);
        expect(service.currentSessionId, sessionC);
        expect(service.sessionPrepared, isTrue);

        final stopBPayloads = sent
            .where(
              (payload) =>
                  payload['action'] == 'stop' &&
                  payload['session_id'] == 'session-b-late',
            )
            .toList();
        expect(stopBPayloads, hasLength(1));
        final stopBRequestId = stopBPayloads.single['request_id'] as String;

        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopBRequestId,
          'session_id': 'session-b-late',
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopB;
        expect(service.currentSessionId, sessionC);
        expect(service.sessionPrepared, isTrue);
      },
    );

    test(
      'disconnect completes normally when stop receives mismatched ACK',
      () async {
        service.beginPracticeAttempt();
        final sessionId = service.currentSessionId!;

        final disconnectFuture = service.disconnect();
        await Future<void>.delayed(Duration.zero);

        final stopPayloads = sent
            .where((payload) => payload['action'] == 'stop')
            .toList();
        expect(stopPayloads, hasLength(1));
        expect(stopPayloads.single['session_id'], sessionId);
        final stopRequestId = stopPayloads.single['request_id'] as String;

        inbound.add(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'command_ack',
            'request_id': stopRequestId,
            'session_id': sessionId,
            'action': 'activate',
            'accepted': true,
            'session_state': 'active',
          }),
        );

        await disconnectFuture;
        expect(service.connectionState, WebSocketConnectionState.disconnected);
      },
    );

    test(
      'controlled stop failures complete without unhandled async errors',
      () async {
        service.beginPracticeAttempt();
        final sessionId = service.currentSessionId!;

        final stopFuture = service.stopPracticeSession(sessionId: sessionId);
        await Future<void>.delayed(Duration.zero);

        final handled = _swallowControlledStopFailures(stopFuture);
        unawaited(handled);

        await expectLater(handled, completes);
        await expectLater(stopFuture, throwsA(isA<CommandTimeoutException>()));
      },
    );

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

  test('bottle_and_shaker prepare/start payloads carry the combined prop', () {
    final preparePayload = WebSocketService.buildPreparePayload(
      movement: 'Bottle in a tin',
      difficulty: 'Hard',
      prop: TrainingProp.bottleAndShaker,
      sessionId: 'session-tin',
      requestId: 'req-tin-prepare',
    );
    final startPayload = WebSocketService.buildStartPayload(
      movement: 'Bottle in a tin',
      difficulty: 'Hard',
      prop: TrainingProp.bottleAndShaker,
      sessionId: 'session-tin',
      requestId: 'req-tin-start',
    );

    expect(preparePayload['prop_type'], 'bottle_and_shaker');
    expect(startPayload['prop_type'], 'bottle_and_shaker');
  });

  test('buildBeginReadinessPayload uses begin_readiness action', () {
    final payload = WebSocketService.buildBeginReadinessPayload(
      sessionId: 'session-r',
      requestId: 'req-r',
    );
    expect(payload['action'], 'begin_readiness');
    expect(payload['protocol_version'], 1);
    expect(payload['session_id'], 'session-r');
    expect(payload['request_id'], 'req-r');
  });

  group('WebSocketService begin_readiness lifecycle', () {
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

    test('sendBeginReadiness sends correct protocol payload', () async {
      service.beginPracticeAttempt();
      final sessionId = service.currentSessionId!;

      // Seed prepared state first.
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
      expect(service.sessionPrepared, isTrue);

      final readinessFuture = service.sendBeginReadiness(sessionId: sessionId);
      await Future<void>.delayed(Duration.zero);

      expect(sent.last['action'], 'begin_readiness');
      expect(sent.last['protocol_version'], 1);
      expect(sent.last['session_id'], sessionId);
      expect(sent.last['request_id'], isNotEmpty);
      // sessionPrepared stays true; sessionActive stays false.
      expect(service.sessionPrepared, isTrue);
      expect(service.sessionActive, isFalse);

      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': sessionId,
        'action': 'begin_readiness',
        'accepted': true,
        'session_state': 'readying',
      });
      final ack = await readinessFuture;
      expect(ack.accepted, isTrue);
      expect(service.sessionPrepared, isTrue);
      expect(service.sessionActive, isFalse);
      expect(service.sessionReadying, isTrue);
    });

    test('sendBeginReadiness without session_id errors', () {
      expect(() => service.sendBeginReadiness(), throwsA(isA<StateError>()));
    });

    test('duplicate sendBeginReadiness is rejected while in flight', () async {
      service.beginPracticeAttempt();
      final sessionId = service.currentSessionId!;

      final first = service.sendBeginReadiness(sessionId: sessionId);
      await Future<void>.delayed(Duration.zero);
      expect(
        () => service.sendBeginReadiness(sessionId: sessionId),
        throwsA(isA<StateError>()),
      );
      // Resolve first to avoid unhandled timeout.
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': sessionId,
        'action': 'begin_readiness',
        'accepted': true,
        'session_state': 'readying',
      });
      await first;
    });

    test(
      'readying session_state in feedback reconciles to prepared=true active=false',
      () async {
        service.beginPracticeAttempt();
        final sessionId = service.currentSessionId!;

        service.debugHandleRawMessage(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'feedback',
            'session_id': sessionId,
            'bottle_detected': false,
            'movement': 'Hand Stall',
            'score': 0,
            'feedback': 'Checking',
            'feedback_type': 'positive',
            'posture_status': 'unknown',
            'session_state': 'readying',
          }),
        );
        await Future<void>.delayed(Duration.zero);

        expect(service.sessionPrepared, isTrue);
        expect(service.sessionActive, isFalse);
        expect(service.sessionReadying, isTrue);
      },
    );

    test(
      'transitioning from readying to active via activate clears readying',
      () async {
        service.beginPracticeAttempt();
        final sessionId = service.currentSessionId!;

        service.debugHandleRawMessage(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'feedback',
            'session_id': sessionId,
            'bottle_detected': false,
            'movement': 'Hand Stall',
            'score': 0,
            'feedback': 'Checking',
            'feedback_type': 'positive',
            'posture_status': 'unknown',
            'session_state': 'readying',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.sessionReadying, isTrue);

        final activate = service.sendActivate(sessionId: sessionId);
        await Future<void>.delayed(Duration.zero);
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': sessionId,
          'action': 'activate',
          'accepted': true,
          'session_state': 'active',
        });
        await activate;
        expect(service.sessionPrepared, isTrue);
        expect(service.sessionActive, isTrue);
        expect(service.sessionReadying, isFalse);
      },
    );
  });

  group('WebSocketService confirm_readiness lifecycle', () {
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

    test('sendConfirmReadiness sends correct protocol payload', () async {
      service.beginPracticeAttempt();
      final sessionId = service.currentSessionId!;

      final confirmFuture = service.sendConfirmReadiness(sessionId: sessionId);
      await Future<void>.delayed(Duration.zero);

      expect(sent.last['action'], 'confirm_readiness');
      expect(sent.last['session_id'], sessionId);

      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': sessionId,
        'action': 'confirm_readiness',
        'accepted': true,
        'session_state': 'readying',
      });
      final ack = await confirmFuture;
      expect(ack.accepted, isTrue);
      expect(service.sessionReadying, isTrue);
      expect(service.sessionActive, isFalse);
    });

    test(
      'duplicate sendConfirmReadiness is rejected while in flight',
      () async {
        service.beginPracticeAttempt();
        final sessionId = service.currentSessionId!;

        final first = service.sendConfirmReadiness(sessionId: sessionId);
        await Future<void>.delayed(Duration.zero);
        expect(
          () => service.sendConfirmReadiness(sessionId: sessionId),
          throwsA(isA<StateError>()),
        );
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': sent.last['request_id'],
          'session_id': sessionId,
          'action': 'confirm_readiness',
          'accepted': true,
          'session_state': 'readying',
        });
        await first;
      },
    );

    test('readiness_not_stable rejection keeps readying state', () async {
      service.beginPracticeAttempt();
      final sessionId = service.currentSessionId!;

      final prepare = service.sendPrepare(
        movement: 'Hand Stall',
        difficulty: 'Medium',
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

      final begin = service.sendBeginReadiness(sessionId: sessionId);
      await Future<void>.delayed(Duration.zero);
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': sessionId,
        'action': 'begin_readiness',
        'accepted': true,
        'session_state': 'readying',
      });
      await begin;
      expect(service.sessionReadying, isTrue);

      final confirmFuture = service.sendConfirmReadiness(sessionId: sessionId);
      await Future<void>.delayed(Duration.zero);
      await push({
        'protocol_version': 1,
        'message_type': 'command_ack',
        'request_id': sent.last['request_id'],
        'session_id': sessionId,
        'action': 'confirm_readiness',
        'accepted': false,
        'session_state': 'readying',
        'error_code': 'readiness_not_stable',
      });
      final ack = await confirmFuture;
      expect(ack.accepted, isFalse);
      expect(ack.errorCode, 'readiness_not_stable');
      expect(service.sessionReadying, isTrue);
      expect(service.sessionActive, isFalse);
    });
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

  group('WebSocketService sessionReadying reset invariants', () {
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

    test('beginPracticeAttempt resets sessionReadying to false', () async {
      service.beginPracticeAttempt();
      final sessionId = service.currentSessionId!;

      // Advance to readying via feedback.
      service.debugHandleRawMessage(
        jsonEncode({
          'protocol_version': 1,
          'message_type': 'feedback',
          'session_id': sessionId,
          'bottle_detected': false,
          'movement': 'Hand Stall',
          'score': 0,
          'feedback': 'Checking',
          'feedback_type': 'positive',
          'posture_status': 'unknown',
          'session_state': 'readying',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.sessionReadying, isTrue);

      // New attempt must clear readying.
      service.beginPracticeAttempt();
      expect(service.sessionReadying, isFalse);
      expect(service.sessionPrepared, isFalse);
      expect(service.sessionActive, isFalse);
    });

    test(
      'stopPracticeSession clears sessionReadying for the stopped session',
      () async {
        service.beginPracticeAttempt();
        final sessionId = service.currentSessionId!;

        // Seed readying state.
        service.debugHandleRawMessage(
          jsonEncode({
            'protocol_version': 1,
            'message_type': 'feedback',
            'session_id': sessionId,
            'bottle_detected': false,
            'movement': 'Hand Stall',
            'score': 0,
            'feedback': 'Checking',
            'feedback_type': 'positive',
            'posture_status': 'unknown',
            'session_state': 'readying',
          }),
        );
        await Future<void>.delayed(Duration.zero);
        expect(service.sessionReadying, isTrue);

        // Stop clears identity and flags immediately.
        final stopFuture = service.stopPracticeSession(sessionId: sessionId);
        expect(service.currentSessionId, isNull);
        expect(service.sessionReadying, isFalse);
        expect(service.sessionPrepared, isFalse);

        // Allow stop wire command to be sent.
        await Future<void>.delayed(Duration.zero);

        final stopPayloads = sent.where((p) => p['action'] == 'stop').toList();
        expect(stopPayloads, isNotEmpty);

        // Resolve stop.
        await push({
          'protocol_version': 1,
          'message_type': 'command_ack',
          'request_id': stopPayloads.last['request_id'],
          'session_id': sessionId,
          'action': 'stop',
          'accepted': true,
          'session_state': 'idle',
        });
        await stopFuture;
        expect(service.sessionReadying, isFalse);
      },
    );
  });
}
