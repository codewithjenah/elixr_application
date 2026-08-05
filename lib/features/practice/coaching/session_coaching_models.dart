/// Immutable coaching DTOs shared by aggregation and recommendation.
///
/// Dependency direction:
/// `session_coaching_models` ← `session_recommendation` ← `session_assessment`
library;

import '../../../data/models/practice_feedback.dart';

/// One persistent technique issue identified across an active session.
class SessionImprovement {
  const SessionImprovement({
    required this.message,
    required this.occurrenceCount,
    required this.occurrenceRatio,
    required this.feedbackType,
    required this.representativeFeedback,
    this.code,
  });

  final String message;
  final int occurrenceCount;
  final double occurrenceRatio;
  final String feedbackType;
  final PracticeFeedback representativeFeedback;

  /// Stable backend feedback code when present; null for legacy message keys.
  final String? code;

  /// Sample-honest alias for [occurrenceCount] (frame/sample count, not events).
  int get sampleCount => occurrenceCount;

  /// Sample-honest alias for [occurrenceRatio].
  double get sampleRatio => occurrenceRatio;
}

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

  /// positiveCode | holdConfirmed | holdPartialProgress | holdPartialDuration
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

/// Post-session coaching snapshot composed under [SessionAssessment].
class SessionCoachingSummary {
  const SessionCoachingSummary({
    required this.strengths,
    required this.improvements,
    this.recommendation,
    this.cleanSessionMessage,
  });

  /// Empty coaching for legacy/manual [SessionAssessment] construction.
  /// Does not fabricate a recommendation or movement name.
  const SessionCoachingSummary.empty()
    : strengths = const [],
      improvements = const [],
      recommendation = null,
      cleanSessionMessage = null;

  final List<SessionStrength> strengths;

  /// Same list instance as [SessionAssessment.improvements] on production builds.
  final List<SessionImprovement> improvements;

  final SessionRecommendation? recommendation;

  /// Movement-specific copy when no recurring technique issues were found.
  /// Populated by production assessment; null for legacy/manual snapshots.
  final String? cleanSessionMessage;

  bool get hasRecommendation => recommendation != null;

  bool get isEmpty =>
      strengths.isEmpty && improvements.isEmpty && recommendation == null;
}
