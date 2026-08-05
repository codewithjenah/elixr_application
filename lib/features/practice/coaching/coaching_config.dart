/// Deterministic coaching copy and practice-duration defaults.
///
/// No randomness or remote text generation.
library;

/// Default recommended practice duration when no movement-specific override.
const int defaultRecommendedDurationSeconds = 180;

/// Phase A focus copy for Hand Stall technique codes.
const Map<String, String> feedbackCodeFocusCopy = {
  'palm_not_open': 'Open your palm and extend your fingers',
  'bottle_not_upright': 'Keep the bottle upright',
  'bottle_base_not_on_palm': 'Place the bottle base on your open palm',
  'bottle_not_above_palm': 'Keep the bottle directly above your palm',
  'bottle_not_steady': 'Hold the bottle steady on your palm',
  'hand_stall_locked': 'Maintain a locked-in hand stall',
};

/// Recommended practice duration by movement name (seconds).
const Map<String, int> movementRecommendedDurationSeconds = {'Hand Stall': 180};

int recommendedDurationForMovement(String movement) {
  return movementRecommendedDurationSeconds[movement] ??
      defaultRecommendedDurationSeconds;
}

String focusCopyForCode(String? code, {required String fallbackMessage}) {
  if (code != null && feedbackCodeFocusCopy.containsKey(code)) {
    return feedbackCodeFocusCopy[code]!;
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
