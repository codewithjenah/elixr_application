import 'dart:convert';
import 'dart:typed_data';

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
    this.calibrationScale,
    this.calibrationSource,
    this.localFilePath,
    this.videoDurationMs,
    this.videoSizeBytes,
    this.contentType,
    this.videoSha256,
  });

  final int protocolVersion;
  final String requestId;
  final String? sessionId;
  final String action;
  final bool accepted;
  final String? sessionState;
  final String? errorCode;
  final String? message;
  final double? calibrationScale;
  final String? calibrationSource;
  final String? localFilePath;
  final int? videoDurationMs;
  final int? videoSizeBytes;
  final String? contentType;
  final String? videoSha256;

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
      calibrationScale: json['calibration_scale'] is num
          ? (json['calibration_scale'] as num).toDouble()
          : null,
      calibrationSource: json['calibration_source'] as String?,
      localFilePath: json['local_file_path'] as String?,
      videoDurationMs: (json['video_duration_ms'] as num?)?.toInt(),
      videoSizeBytes: (json['video_size_bytes'] as num?)?.toInt(),
      contentType: json['content_type'] as String?,
      videoSha256: json['video_sha256'] as String?,
    );
  }

  bool get isAccepted => accepted;
}

/// Local recording result. Never contains video bytes.
class SubmissionRecordResult {
  const SubmissionRecordResult({
    required this.localPath,
    required this.durationMs,
    required this.sizeBytes,
    required this.contentType,
    this.sha256,
  });

  final String localPath;
  final int durationMs;
  final int sizeBytes;
  final String contentType;
  final String? sha256;

  factory SubmissionRecordResult.fromAck(CommandAck ack) {
    final path = ack.localFilePath?.trim() ?? '';
    if (path.isEmpty ||
        ack.videoDurationMs == null ||
        ack.videoSizeBytes == null ||
        (ack.contentType ?? '').isEmpty) {
      throw const FormatException(
        'Incomplete submission record acknowledgment',
      );
    }
    return SubmissionRecordResult(
      localPath: path,
      durationMs: ack.videoDurationMs!,
      sizeBytes: ack.videoSizeBytes!,
      contentType: ack.contentType!,
      sha256: ack.videoSha256,
    );
  }
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

/// Camera-image update only. Must not advance readiness, scoring, or TTS.
class PreviewFrame {
  const PreviewFrame({
    required this.jpegBytes,
    this.sessionId,
    this.sessionState,
    this.cameraReady = true,
    this.captureSequence,
    this.protocolVersion,
  });

  final Uint8List jpegBytes;
  final String? sessionId;
  final String? sessionState;
  final bool cameraReady;
  final int? captureSequence;
  final int? protocolVersion;

  factory PreviewFrame.fromJson(Map<String, dynamic> json) {
    final frameB64 = json['frame_jpeg_base64'] as String? ?? '';
    return PreviewFrame(
      jpegBytes: frameB64.isEmpty ? Uint8List(0) : base64Decode(frameB64),
      sessionId: json['session_id'] as String?,
      sessionState: json['session_state'] as String?,
      cameraReady: json['camera_ready'] as bool? ?? true,
      captureSequence: (json['capture_sequence'] as num?)?.toInt(),
      protocolVersion: json['protocol_version'] as int?,
    );
  }

  bool get hasJpeg => jpegBytes.isNotEmpty;
}

/// Known [CommandAck.sessionState] values produced by the backend.
///
/// - `preparing` – camera and model are warming up; preview frames stream.
/// - `readying`  – pre-practice readiness gate is active; checklist items arrive
///   in [PracticeFeedback.readinessItems] until `readiness_stable` is true.
///   Start Practice sends `confirm_readiness`; countdown begins only after ack.
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

final class WsPreviewFrameMessage extends WsInboundMessage {
  const WsPreviewFrameMessage(this.frame);
  final PreviewFrame frame;
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
        case 'preview_frame':
          return WsPreviewFrameMessage(PreviewFrame.fromJson(json));
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
