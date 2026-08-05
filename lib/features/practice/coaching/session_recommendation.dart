import '../../../data/models/training_prop.dart';
import 'coaching_config.dart';
import 'session_coaching_models.dart';

/// Pure deterministic next-session recommendation for scored practice.
SessionRecommendation buildSessionRecommendation({
  required String movement,
  required TrainingProp prop,
  required bool heldSteady,
  required int finalScore,
  required double positiveRatio,
  required int totalApplicableSamples,
  required List<SessionImprovement> improvements,
  required int maxHoldDurationMs,
  required double maxHoldProgress,
  required int holdTargetMs,
}) {
  final durationSeconds = recommendedDurationForMovement(movement);
  final targetLabel = formatHoldTargetLabel(
    movement: movement,
    prop: prop,
    holdTargetMs: holdTargetMs,
  );
  final targetUsesHoldMs = holdTargetMs > 0;

  if (totalApplicableSamples == 0) {
    return SessionRecommendation(
      movementName: movement,
      reason: lowDataRecommendationReasonFor(movement, prop),
      targetLabel: targetLabel,
      targetUsesHoldMs: targetUsesHoldMs,
      recommendedDurationSeconds: durationSeconds,
    );
  }

  if (improvements.isNotEmpty) {
    final top = improvements.first;
    final focus = focusCopyForCode(
      top.code,
      prop: prop,
      fallbackMessage: top.message,
    );
    return SessionRecommendation(
      movementName: movement,
      reason: 'Focus: $focus',
      targetLabel: targetLabel,
      targetUsesHoldMs: targetUsesHoldMs,
      recommendedDurationSeconds: durationSeconds,
    );
  }

  if (!heldSteady) {
    return SessionRecommendation(
      movementName: movement,
      reason: unconfirmedRecommendationReasonFor(movement, prop),
      targetLabel: targetLabel,
      targetUsesHoldMs: targetUsesHoldMs,
      recommendedDurationSeconds: durationSeconds,
    );
  }

  // Confirmed hold with no persistent technique issues.
  return SessionRecommendation(
    movementName: movement,
    reason: successfulRecommendationReasonFor(movement),
    targetLabel: targetLabel,
    targetUsesHoldMs: targetUsesHoldMs,
    recommendedDurationSeconds: durationSeconds,
  );
}
