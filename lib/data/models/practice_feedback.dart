import 'dart:convert';
import 'dart:typed_data';

import 'rubric_assessment.dart';
import 'training_prop.dart';
import 'coaching_verdict.dart';

/// Typed status for a single readiness checklist item.
///
/// Values beyond the known set (ready / waiting / error) parse as [unknown]
/// for forward compatibility with future backend extensions.
enum ReadinessItemStatus {
  ready,
  waiting,
  error,

  /// Fallback for any unrecognized wire value.
  unknown;

  /// Wire-protocol string sent by the backend.
  String get wireValue => switch (this) {
    ReadinessItemStatus.ready => 'ready',
    ReadinessItemStatus.waiting => 'waiting',
    ReadinessItemStatus.error => 'error',
    ReadinessItemStatus.unknown => 'unknown',
  };

  /// Parse a wire string; unrecognized values map to [unknown].
  static ReadinessItemStatus fromWire(String value) => switch (value) {
    'ready' => ReadinessItemStatus.ready,
    'waiting' => ReadinessItemStatus.waiting,
    'error' => ReadinessItemStatus.error,
    _ => ReadinessItemStatus.unknown,
  };
}

/// A single checklist item from the pre-practice readiness gate.
class ReadinessItemView {
  const ReadinessItemView({
    required this.code,
    required this.status,
    required this.message,
  });

  /// Backend-defined identifier for the check (e.g. 'camera_frame', 'bottle_detected').
  final String code;

  /// Parsed readiness status. Unknown wire values map to [ReadinessItemStatus.unknown].
  final ReadinessItemStatus status;

  final String message;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ReadinessItemView) return false;
    return code == other.code &&
        status == other.status &&
        message == other.message;
  }

  @override
  int get hashCode => Object.hash(code, status, message);
}

class PracticeFeedback {
  const PracticeFeedback({
    required this.bottleDetected,
    this.bottleCount = 0,
    required this.movement,
    this.assessment,
    required this.feedback,
    required this.feedbackType,
    required this.postureStatus,
    this.frameJpegBytes,
    this.evidenceJpegBytes,
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
    this.readinessItems,
    this.readinessComplete,
    this.readinessStable,
    this.readinessStableProgress,
  });

  final bool bottleDetected;
  final int bottleCount;
  final String movement;

  /// Assessment V2 rubric snapshot (active scored sessions only).
  final RubricAssessment? assessment;

  final String feedback;
  final String feedbackType;
  final String postureStatus;
  final Uint8List? frameJpegBytes;

  /// Private annotated still from the one frame that first confirmed a hold.
  /// Invalid/missing wire data is intentionally treated as unavailable.
  final Uint8List? evidenceJpegBytes;
  final String? errorCode;

  /// Optional: true when a usable preview/active JPEG is present.
  final bool? cameraReady;

  /// Optional: preparing | readying | active | recovering | unavailable
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

  /// Readiness gate checklist items. Present only when session_state is 'readying'.
  final List<ReadinessItemView>? readinessItems;

  /// True when all readiness checks have passed at least once.
  final bool? readinessComplete;

  /// True when readiness has been stable long enough to proceed.
  final bool? readinessStable;

  /// Progress toward stable readiness confirmation (0.0–1.0). Absent when not readying.
  final double? readinessStableProgress;

  bool get isPreparing => sessionState == 'preparing';
  bool get isSessionEvaluating => sessionState == 'active';
  bool get isReadying => sessionState == 'readying';

  bool get isSessionFatal =>
      errorCode != null ||
      (feedbackType == 'error' &&
          frameJpegBytes == null &&
          (feedback.contains('Camera unavailable') ||
              feedback.contains('Model load failed')));

  /// Trainee-facing live verdict. [postureStatus] is the primary source;
  /// visibility/environment/system category is only a leftover safety net.
  CoachingVerdict get coachingVerdict {
    if (isSessionFatal) {
      return CoachingVerdict.wrong;
    }
    if (postureStatus == 'unknown') {
      return CoachingVerdict.uncertain;
    }
    if (feedbackType == 'positive' && postureStatus == 'stable') {
      return CoachingVerdict.correct;
    }
    if (postureStatus == 'unstable') {
      return CoachingVerdict.wrong;
    }
    final category = feedbackCategory;
    if (category != null && nonEvaluableFeedbackCategories.contains(category)) {
      return CoachingVerdict.uncertain;
    }
    return CoachingVerdict.wrong;
  }

  /// Semantic UI fields only (excludes JPEG bytes).
  bool semanticEquals(PracticeFeedback? other) {
    if (identical(this, other)) return true;
    if (other == null) return false;
    return bottleDetected == other.bottleDetected &&
        bottleCount == other.bottleCount &&
        movement == other.movement &&
        assessment == other.assessment &&
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
        propType == other.propType &&
        readinessComplete == other.readinessComplete &&
        readinessStable == other.readinessStable &&
        readinessStableProgress == other.readinessStableProgress &&
        _readinessItemsEqual(readinessItems, other.readinessItems);
  }

  /// Fields Free Practice actually displays (excludes assessment/hold/hidden metrics).
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
  /// Rubric totals, hold progress, hold duration/target, feedback codes/categories,
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
        propType == other.propType &&
        readinessComplete == other.readinessComplete &&
        readinessStable == other.readinessStable &&
        _readinessItemsEqual(readinessItems, other.readinessItems);
  }

  factory PracticeFeedback.fromJson(Map<String, dynamic> json) {
    Uint8List? frameBytes;
    final frameB64 = json['frame_jpeg_base64'] as String?;
    if (frameB64 != null && frameB64.isNotEmpty) {
      frameBytes = base64Decode(frameB64);
    }
    Uint8List? evidenceBytes;
    final evidenceB64 = json['evidence_jpeg_base64'];
    if (evidenceB64 is String && evidenceB64.isNotEmpty) {
      try {
        evidenceBytes = base64Decode(evidenceB64);
      } on FormatException {
        // Evidence is optional and must never make session completion fail.
      }
    }

    final rawTarget = json['hold_target_ms'];
    final holdTargetMs = rawTarget is num ? rawTarget.toInt() : 0;

    final rawProgress = json['readiness_stable_progress'];
    double? readinessStableProgress = rawProgress is num
        ? rawProgress.toDouble().clamp(0.0, 1.0)
        : null;

    return PracticeFeedback(
      bottleDetected: json['bottle_detected'] as bool? ?? false,
      bottleCount: (json['bottle_count'] as num?)?.toInt() ?? 0,
      movement: json['movement'] as String? ?? '',
      assessment: RubricAssessment.tryFromJson(json['assessment']),
      feedback: json['feedback'] as String? ?? '',
      feedbackType: json['feedback_type'] as String? ?? 'positive',
      postureStatus: json['posture_status'] as String? ?? 'unknown',
      frameJpegBytes: frameBytes,
      evidenceJpegBytes: evidenceBytes,
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
      readinessItems: _parseReadinessItems(json['readiness_items']),
      readinessComplete: json['readiness_complete'] as bool?,
      readinessStable: json['readiness_stable'] as bool?,
      readinessStableProgress: readinessStableProgress,
    );
  }

  static List<ReadinessItemView>? _parseReadinessItems(dynamic raw) {
    if (raw == null) return null;
    if (raw is! List) return null;
    final result = <ReadinessItemView>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final code = entry['code'];
      final statusRaw = entry['status'];
      final message = entry['message'];
      if (code is! String || statusRaw is! String || message is! String) {
        continue;
      }
      result.add(
        ReadinessItemView(
          code: code,
          status: ReadinessItemStatus.fromWire(statusRaw),
          message: message,
        ),
      );
    }
    return result;
  }

  static bool _readinessItemsEqual(
    List<ReadinessItemView>? a,
    List<ReadinessItemView>? b,
  ) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
