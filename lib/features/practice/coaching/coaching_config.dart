/// Deterministic coaching copy and practice-duration defaults.
///
/// No randomness or remote text generation.
library;

import '../../../data/models/training_prop.dart';

/// Default recommended practice duration when no movement-specific override.
const int defaultRecommendedDurationSeconds = 180;

/// Recommended practice duration by movement name (seconds).
const Map<String, int> movementRecommendedDurationSeconds = {'Hand Stall': 180};

/// Lowercase prop label used inside coaching focus sentences.
String coachingPropLabel(TrainingProp prop) => prop.displayLabel.toLowerCase();

int recommendedDurationForMovement(String movement) {
  return movementRecommendedDurationSeconds[movement] ??
      defaultRecommendedDurationSeconds;
}

/// Prop-aware focus copy for registered Phase A technique codes.
String focusCopyForCode(
  String? code, {
  required TrainingProp prop,
  required String fallbackMessage,
}) {
  final label = coachingPropLabel(prop);
  switch (code) {
    case 'palm_not_open':
      return 'Open your palm and extend your fingers';
    case 'prop_not_upright':
      return 'Keep the $label upright';
    case 'prop_base_not_on_palm':
      return 'Place the $label base on your open palm';
    case 'prop_not_above_palm':
      return 'Keep the $label directly above your palm';
    case 'prop_not_steady':
      return 'Hold the $label steady on your palm';
    case 'hand_stall_locked':
      return 'Maintain a locked-in hand stall';
  }

  final trimmed = fallbackMessage.trim();
  if (trimmed.isEmpty) {
    return 'Refine your technique';
  }
  // Use the representative warning as focus when no code map entry exists.
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

String formatHoldTargetLabel(int holdTargetMs) {
  if (holdTargetMs <= 0) {
    return 'Complete one confirmed hold';
  }
  final seconds = holdTargetMs / 1000.0;
  final formatted = seconds == seconds.roundToDouble()
      ? seconds.round().toString()
      : seconds.toStringAsFixed(1);
  return 'Complete one confirmed hold ($formatted seconds)';
}
