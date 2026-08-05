import 'dart:convert';

import 'practice_feedback.dart';

/// Protocol version negotiated by new Flutter command payloads.
const int wsProtocolVersion = 1;

/// Correlated acknowledgment for a version-1 command.
class CommandAck {
  const CommandAck({
    required this.protocolVersion,
    required this.requestId,
    required this.action,
    required this.accepted,
    this.sessionId,
    this.sessionState,
    this.errorCode,
    this.message,
  });

  final int protocolVersion;
  final String requestId;
  final String? sessionId;
  final String action;
  final bool accepted;
  final String? sessionState;
  final String? errorCode;
  final String? message;

  factory CommandAck.fromJson(Map<String, dynamic> json) {
    return CommandAck(
      protocolVersion: json['protocol_version'] as int? ?? wsProtocolVersion,
      requestId: json['request_id'] as String? ?? '',
      sessionId: json['session_id'] as String?,
      action: json['action'] as String? ?? '',
      accepted: json['accepted'] as bool? ?? false,
      sessionState: json['session_state'] as String?,
      errorCode: json['error_code'] as String?,
      message: json['message'] as String?,
    );
  }

  bool get isAccepted => accepted;
}

/// Uncorrelated or partially correlated protocol failure.
class ProtocolErrorMessage {
  const ProtocolErrorMessage({
    required this.protocolVersion,
    required this.errorCode,
    required this.message,
    this.requestId,
    this.sessionId,
  });

  final int protocolVersion;
  final String? requestId;
  final String? sessionId;
  final String errorCode;
  final String message;

  factory ProtocolErrorMessage.fromJson(Map<String, dynamic> json) {
    return ProtocolErrorMessage(
      protocolVersion: json['protocol_version'] as int? ?? wsProtocolVersion,
      requestId: json['request_id'] as String?,
      sessionId: json['session_id'] as String?,
      errorCode: json['error_code'] as String? ?? 'invalid_command',
      message: json['message'] as String? ?? 'Protocol error',
    );
  }
}

/// Controlled failure when a pending command times out.
class CommandTimeoutException implements Exception {
  CommandTimeoutException(this.requestId, this.action);

  final String requestId;
  final String action;

  String get errorCode => 'command_timeout';

  @override
  String toString() =>
      'CommandTimeoutException(action=$action, requestId=$requestId)';
}

/// Controlled failure when the socket closes before an acknowledgment.
class CommandDisconnectedException implements Exception {
  CommandDisconnectedException(this.requestId, this.action);

  final String requestId;
  final String action;

  @override
  String toString() =>
      'CommandDisconnectedException(action=$action, requestId=$requestId)';
}

/// Controlled failure when a correlated ack does not match the pending command.
class CommandAckMismatchException implements Exception {
  CommandAckMismatchException({
    required this.requestId,
    required this.pendingAction,
    required this.pendingSessionId,
    required this.ackAction,
    this.ackSessionId,
    required this.actionMismatch,
    required this.sessionMismatch,
  });

  final String requestId;
  final String pendingAction;
  final String pendingSessionId;
  final String ackAction;
  final String? ackSessionId;
  final bool actionMismatch;
  final bool sessionMismatch;

  String get errorCode =>
      actionMismatch ? 'ack_action_mismatch' : 'ack_session_mismatch';

  @override
  String toString() =>
      'CommandAckMismatchException(requestId=$requestId, pending=$pendingAction/'
      '$pendingSessionId, ack=$ackAction/$ackSessionId)';
}

/// Known [CommandAck.sessionState] values produced by the backend.
///
/// - `preparing` – camera and model are warming up; preview frames stream.
/// - `readying`  – pre-practice readiness gate is active; checklist items arrive
///   in [PracticeFeedback.readinessItems] until `readiness_stable` is true.
/// - `active`    – movement evaluation and scoring are running.
/// - `idle`      – no active session.
/// - `unavailable` – camera or model is permanently unavailable.
///
/// Unknown values must be silently ignored so future backend additions are
/// non-breaking for older clients.
sealed class WsInboundMessage {
  const WsInboundMessage();
}

final class WsFeedbackMessage extends WsInboundMessage {
  const WsFeedbackMessage(this.feedback);
  final PracticeFeedback feedback;
}

final class WsCommandAckMessage extends WsInboundMessage {
  const WsCommandAckMessage(this.ack);
  final CommandAck ack;
}

final class WsProtocolErrorInbound extends WsInboundMessage {
  const WsProtocolErrorInbound(this.error);
  final ProtocolErrorMessage error;
}

final class WsUnknownMessage extends WsInboundMessage {
  const WsUnknownMessage(this.messageType);
  final String? messageType;
}

final class WsMalformedMessage extends WsInboundMessage {
  const WsMalformedMessage(this.reason);
  final String reason;
}

/// Decodes inbound WebSocket JSON into typed protocol messages.
class WsMessageDecoder {
  const WsMessageDecoder();

  WsInboundMessage decode(dynamic raw) {
    if (raw is! String) {
      return const WsMalformedMessage('Inbound message was not text');
    }

    late final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const WsMalformedMessage('Inbound message was not valid JSON');
    }

    if (decoded is! Map) {
      return const WsMalformedMessage('Inbound JSON was not an object');
    }

    final json = Map<String, dynamic>.from(decoded);
    final messageType = json['message_type'] as String?;

    try {
      if (messageType == null) {
        // Legacy feedback frames omit message_type.
        return WsFeedbackMessage(PracticeFeedback.fromJson(json));
      }

      switch (messageType) {
        case 'feedback':
          return WsFeedbackMessage(PracticeFeedback.fromJson(json));
        case 'command_ack':
          return WsCommandAckMessage(CommandAck.fromJson(json));
        case 'protocol_error':
          return WsProtocolErrorInbound(ProtocolErrorMessage.fromJson(json));
        default:
          return WsUnknownMessage(messageType);
      }
    } catch (_) {
      return const WsMalformedMessage('Inbound message failed typed parsing');
    }
  }
}
