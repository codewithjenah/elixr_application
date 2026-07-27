import 'dart:convert';
import 'dart:typed_data';

class PracticeFeedback {
  const PracticeFeedback({
    required this.bottleDetected,
    required this.movement,
    required this.score,
    required this.feedback,
    required this.feedbackType,
    required this.postureStatus,
    this.frameJpegBytes,
    this.errorCode,
    this.cameraReady,
    this.sessionState,
  });

  final bool bottleDetected;
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

  bool get isPreparing => sessionState == 'preparing';
  bool get isSessionEvaluating => sessionState == 'active';

  bool get isSessionFatal =>
      errorCode != null ||
      (feedbackType == 'error' &&
          frameJpegBytes == null &&
          (feedback.contains('Camera unavailable') ||
              feedback.contains('Model load failed')));

  factory PracticeFeedback.fromJson(Map<String, dynamic> json) {
    Uint8List? frameBytes;
    final frameB64 = json['frame_jpeg_base64'] as String?;
    if (frameB64 != null && frameB64.isNotEmpty) {
      frameBytes = base64Decode(frameB64);
    }

    return PracticeFeedback(
      bottleDetected: json['bottle_detected'] as bool? ?? false,
      movement: json['movement'] as String? ?? '',
      score: json['score'] as int? ?? 0,
      feedback: json['feedback'] as String? ?? '',
      feedbackType: json['feedback_type'] as String? ?? 'positive',
      postureStatus: json['posture_status'] as String? ?? 'unknown',
      frameJpegBytes: frameBytes,
      errorCode: json['error_code'] as String?,
      cameraReady: json['camera_ready'] as bool?,
      sessionState: json['session_state'] as String?,
    );
  }
}
