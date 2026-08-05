/// Immutable coaching DTOs for post-session summary.
///
/// [SessionCoachingSummary] lives in `session_assessment.dart` so it can share
/// the same [SessionImprovement] list without a circular import.
library;

class SessionStrength {
  const SessionStrength({
    required this.code,
    required this.message,
    required this.sampleCount,
    required this.sampleRatio,
    required this.evidenceKind,
  });

  final String code;
  final String message;
  final int sampleCount;
  final double sampleRatio;

  /// positiveCode | holdConfirmed | holdPartialProgress |
  /// holdPartialDuration | holdExceptionalDuration
  final String evidenceKind;
}

class SessionRecommendation {
  const SessionRecommendation({
    required this.movementName,
    required this.reason,
    required this.targetLabel,
    required this.targetUsesHoldMs,
    required this.recommendedDurationSeconds,
  });

  final String movementName;
  final String reason;
  final String targetLabel;
  final bool targetUsesHoldMs;
  final int recommendedDurationSeconds;
}
