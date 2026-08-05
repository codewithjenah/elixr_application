import 'dart:convert';
import 'dart:typed_data';

import 'training_prop.dart';

class PracticeFeedback {
  const PracticeFeedback({
    required this.bottleDetected,
    this.bottleCount = 0,
    required this.movement,
    required this.score,
    required this.feedback,
    required this.feedbackType,
    required this.postureStatus,
    this.frameJpegBytes,
    this.errorCode,
    this.cameraReady,
    this.sessionState,
    this.holdProgress = 0,
    this.holdDurationMs = 0,
    this.holdConfirmed = false,
    this.positiveFrameRatio = 0,
    this.holdTargetMs = 0,
    this.feedbackCode,
    this.feedbackCategory,
    this.protocolVersion,
    this.messageType,
    this.sessionId,
    this.propType = TrainingProp.bottle,
  });

  final bool bottleDetected;
  final int bottleCount;
  final String movement;
  final int score;
  final String feedback;
  final String feedbackType;
  final String postureStatus;
  final Uint8List? frameJpegBytes;
  final String? errorCode;

  /// Optional: true when a usable preview/active JPEG is present.
  final bool? cameraReady;

  /// Optional: preparing | active | recovering | unavailable
  final String? sessionState;

  /// Backend-authoritative hold confirmation (active sessions only).
  final double holdProgress;
  final int holdDurationMs;
  final bool holdConfirmed;
  final double positiveFrameRatio;

  /// Backend-authoritative confirmation target in milliseconds (0 when unknown).
  final int holdTargetMs;

  /// Optional stable coaching identity from the backend registry.
  final String? feedbackCode;
  final String? feedbackCategory;

  /// Optional protocol v1 envelope fields (absent on legacy frames).
  final int? protocolVersion;
  final String? messageType;
  final String? sessionId;
  final TrainingProp propType;

  bool get isPreparing => sessionState == 'preparing';
  bool get isSessionEvaluating => sessionState == 'active';

  bool get isSessionFatal =>
      errorCode != null ||
      (feedbackType == 'error' &&
          frameJpegBytes == null &&
          (feedback.contains('Camera unavailable') ||
              feedback.contains('Model load failed')));

  /// Semantic UI fields only (excludes JPEG bytes).
  bool semanticEquals(PracticeFeedback? other) {
    if (identical(this, other)) return true;
    if (other == null) return false;
    return bottleDetected == other.bottleDetected &&
        bottleCount == other.bottleCount &&
        movement == other.movement &&
        score == other.score &&
        feedback == other.feedback &&
        feedbackType == other.feedbackType &&
        postureStatus == other.postureStatus &&
        errorCode == other.errorCode &&
        cameraReady == other.cameraReady &&
        sessionState == other.sessionState &&
        holdProgress == other.holdProgress &&
        holdDurationMs == other.holdDurationMs &&
        holdConfirmed == other.holdConfirmed &&
        positiveFrameRatio == other.positiveFrameRatio &&
        holdTargetMs == other.holdTargetMs &&
        feedbackCode == other.feedbackCode &&
        feedbackCategory == other.feedbackCategory &&
        protocolVersion == other.protocolVersion &&
        messageType == other.messageType &&
        sessionId == other.sessionId &&
        propType == other.propType;
  }

  /// Fields Free Practice actually displays (excludes score/hold/hidden metrics).
  bool freePracticeVisibleEquals(PracticeFeedback? other) {
    if (identical(this, other)) return true;
    if (other == null) return false;
    return bottleDetected == other.bottleDetected &&
        movement == other.movement &&
        propType == other.propType &&
        feedbackType == other.feedbackType &&
        errorCode == other.errorCode &&
        sessionState == other.sessionState;
  }

  /// Scored-practice chrome fields that require a full screen rebuild.
  ///
  /// Score, hold progress, hold duration/target, feedback codes/categories,
  /// and JPEG bytes are intentionally excluded so high-frequency updates can
  /// use narrowly scoped [ValueNotifier]s / the session accumulator instead.
  bool scoredPracticeChromeEquals(PracticeFeedback? other) {
    if (identical(this, other)) return true;
    if (other == null) return false;
    return bottleDetected == other.bottleDetected &&
        bottleCount == other.bottleCount &&
        movement == other.movement &&
        feedback == other.feedback &&
        feedbackType == other.feedbackType &&
        postureStatus == other.postureStatus &&
        errorCode == other.errorCode &&
        cameraReady == other.cameraReady &&
        sessionState == other.sessionState &&
        holdConfirmed == other.holdConfirmed &&
        protocolVersion == other.protocolVersion &&
        messageType == other.messageType &&
        sessionId == other.sessionId &&
        propType == other.propType;
  }

  factory PracticeFeedback.fromJson(Map<String, dynamic> json) {
    Uint8List? frameBytes;
    final frameB64 = json['frame_jpeg_base64'] as String?;
    if (frameB64 != null && frameB64.isNotEmpty) {
      frameBytes = base64Decode(frameB64);
    }

    final rawTarget = json['hold_target_ms'];
    final holdTargetMs = rawTarget is num ? rawTarget.toInt() : 0;

    return PracticeFeedback(
      bottleDetected: json['bottle_detected'] as bool? ?? false,
      bottleCount: (json['bottle_count'] as num?)?.toInt() ?? 0,
      movement: json['movement'] as String? ?? '',
      score: json['score'] as int? ?? 0,
      feedback: json['feedback'] as String? ?? '',
      feedbackType: json['feedback_type'] as String? ?? 'positive',
      postureStatus: json['posture_status'] as String? ?? 'unknown',
      frameJpegBytes: frameBytes,
      errorCode: json['error_code'] as String?,
      cameraReady: json['camera_ready'] as bool?,
      sessionState: json['session_state'] as String?,
      holdProgress: (json['hold_progress'] as num?)?.toDouble() ?? 0,
      holdDurationMs: json['hold_duration_ms'] as int? ?? 0,
      holdConfirmed: json['hold_confirmed'] as bool? ?? false,
      positiveFrameRatio:
          (json['positive_frame_ratio'] as num?)?.toDouble() ?? 0,
      holdTargetMs: holdTargetMs < 0 ? 0 : holdTargetMs,
      feedbackCode: json['feedback_code'] as String?,
      feedbackCategory: json['feedback_category'] as String?,
      protocolVersion: json['protocol_version'] as int?,
      messageType: json['message_type'] as String?,
      sessionId: json['session_id'] as String?,
      propType: TrainingProp.fromProtocolValue(json['prop_type']),
    );
  }
}
