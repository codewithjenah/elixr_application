import '../session_assessment.dart';
import 'coaching_config.dart';

/// Pure deterministic next-session recommendation for scored practice.
SessionRecommendation buildSessionRecommendation({
  required String movement,
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
  final targetLabel = formatHoldTargetLabel(holdTargetMs);
  final targetUsesHoldMs = holdTargetMs > 0;

  if (totalApplicableSamples == 0) {
    return SessionRecommendation(
      movementName: movement,
      reason: 'Practice $movement again to gather technique feedback.',
      targetLabel: targetLabel,
      targetUsesHoldMs: targetUsesHoldMs,
      recommendedDurationSeconds: durationSeconds,
    );
  }

  if (improvements.isNotEmpty) {
    final top = improvements.first;
    final focus = focusCopyForCode(top.code, fallbackMessage: top.message);
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
      reason: 'Practice $movement again and complete one confirmed hold.',
      targetLabel: targetLabel,
      targetUsesHoldMs: targetUsesHoldMs,
      recommendedDurationSeconds: durationSeconds,
    );
  }

  // Confirmed hold with no persistent technique issues.
  final consistencyNote = finalScore >= 80 && positiveRatio >= 0.7
      ? 'Build consistency on $movement.'
      : 'Practice $movement again to reinforce a confirmed hold.';
  return SessionRecommendation(
    movementName: movement,
    reason: consistencyNote,
    targetLabel: targetLabel,
    targetUsesHoldMs: targetUsesHoldMs,
    recommendedDurationSeconds: durationSeconds,
  );
}
