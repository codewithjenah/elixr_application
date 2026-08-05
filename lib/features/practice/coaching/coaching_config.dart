/// Deterministic coaching copy and practice-duration defaults.
///
/// No randomness or remote text generation.
library;

import '../../../data/models/training_prop.dart';

/// Default recommended practice duration when no movement-specific override.
const int defaultRecommendedDurationSeconds = 180;

/// Recommended practice duration by movement name (seconds).
const Map<String, int> movementRecommendedDurationSeconds = {
  'Normal Grip': 120,
  "Bartender's Grip": 120,
  'Reverse Grip': 120,
  'Claw Grip': 120,
  'Hand Stall': 180,
  'One Finger Stall': 180,
  'Forearm Stall': 180,
  'Elbow Stall': 180,
  'Reverse Forearm Stall': 180,
  'Shoulder Stall': 180,
  'Double Hand Stall': 180,
  'Bottle in a tin': 180,
};

/// Movement display name → positive locked success code.
const Map<String, String> movementPositiveLockedCodes = {
  'Normal Grip': 'normal_grip_locked',
  "Bartender's Grip": 'bartender_grip_locked',
  'Reverse Grip': 'reverse_grip_locked',
  'Claw Grip': 'claw_grip_locked',
  'Hand Stall': 'hand_stall_locked',
  'One Finger Stall': 'one_finger_stall_locked',
  'Forearm Stall': 'forearm_stall_locked',
  'Elbow Stall': 'elbow_stall_locked',
  'Reverse Forearm Stall': 'reverse_forearm_stall_locked',
  'Shoulder Stall': 'shoulder_stall_locked',
  'Double Hand Stall': 'double_hand_stall_locked',
  'Bottle in a tin': 'bottle_in_tin_locked',
};

/// Positive success codes used for evidence-based strength aggregation.
final Set<String> positiveSuccessCodes = movementPositiveLockedCodes.values
    .toSet();

/// Combined confirmed-hold strength identity for a locked success code.
String confirmedStrengthCodeFor(String lockedCode) =>
    '${lockedCode.replaceFirst(RegExp(r'_locked$'), '')}_confirmed';

/// Movement-specific coaching copy for post-session strengths, clean sessions,
/// recommendations, and hold targets. Keys match [movementCatalog] enabled names.
class MovementCoachingProfile {
  const MovementCoachingProfile({
    required this.confirmedStrengthMessage,
    required this.formStrengthMessage,
    required this.cleanSessionMessage,
    required this.successfulRecommendationReason,
    required this.holdTargetInstruction,
  });

  final String confirmedStrengthMessage;
  final String formStrengthMessage;
  final String cleanSessionMessage;
  final String successfulRecommendationReason;

  /// May include `{prop}` for prop-aware stall movements.
  final String holdTargetInstruction;
}

const Map<String, MovementCoachingProfile> movementCoachingProfiles = {
  'Normal Grip': MovementCoachingProfile(
    confirmedStrengthMessage: 'Secure overhand neck grip maintained',
    formStrengthMessage: 'Correct overhand neck grip detected',
    cleanSessionMessage:
        'No recurring neck-grip issues — overhand finger wrap stayed consistent.',
    successfulRecommendationReason:
        'Repeat overhand neck grips to lock in a faster, steadier hold.',
    holdTargetInstruction:
        'Maintain the overhand neck grip through one confirmed hold',
  ),
  "Bartender's Grip": MovementCoachingProfile(
    confirmedStrengthMessage: 'Controlled neck pinch maintained',
    formStrengthMessage: 'Correct bartender pinch and hand position detected',
    cleanSessionMessage:
        'No recurring pinch issues — thumb-and-index neck control stayed steady.',
    successfulRecommendationReason:
        'Repeat the neck pinch until thumb-and-index control locks in cleanly.',
    holdTargetInstruction:
        'Maintain the thumb-and-index neck pinch through one confirmed hold',
  ),
  'Reverse Grip': MovementCoachingProfile(
    confirmedStrengthMessage: 'Stable reverse underhand grip maintained',
    formStrengthMessage: 'Correct reverse grip orientation detected',
    cleanSessionMessage:
        'No recurring grip issues — reverse underhand orientation held stable.',
    successfulRecommendationReason:
        'Repeat reverse underhand grips to build a steadier confirmed hold.',
    holdTargetInstruction:
        'Maintain the reverse underhand grip through one confirmed hold',
  ),
  'Claw Grip': MovementCoachingProfile(
    confirmedStrengthMessage: 'Top-down claw grip maintained',
    formStrengthMessage: 'Correct curled-finger claw position detected',
    cleanSessionMessage:
        'No recurring claw issues — top-down finger curl stayed controlled.',
    successfulRecommendationReason:
        'Repeat top-down claw grips until curled fingers lock around the neck.',
    holdTargetInstruction:
        'Keep the top-down claw grip through one confirmed hold',
  ),
  'Hand Stall': MovementCoachingProfile(
    confirmedStrengthMessage: 'Open-palm balance confirmed',
    formStrengthMessage: 'Upright prop balance detected over the open palm',
    cleanSessionMessage:
        'No recurring balance issues — open-palm stall position stayed stable.',
    successfulRecommendationReason:
        'Repeat open-palm balancing to extend steady hold time.',
    holdTargetInstruction:
        'Balance the {prop} upright on the open palm through one confirmed hold',
  ),
  'One Finger Stall': MovementCoachingProfile(
    confirmedStrengthMessage: 'Index-fingertip balance confirmed',
    formStrengthMessage: 'Correct one-finger balance position detected',
    cleanSessionMessage:
        'No recurring balance issues — index-fingertip centering stayed controlled.',
    successfulRecommendationReason:
        'Repeat index-fingertip balancing to build a longer confirmed hold.',
    holdTargetInstruction:
        'Center the {prop} over the extended index fingertip through one confirmed hold',
  ),
  'Forearm Stall': MovementCoachingProfile(
    confirmedStrengthMessage: 'Forearm balance point held steady',
    formStrengthMessage: 'Correct forearm stall position detected',
    cleanSessionMessage:
        'No recurring balance issues — forearm alignment stayed steady.',
    successfulRecommendationReason:
        'Repeat forearm stalls to keep the prop aligned longer through confirmation.',
    holdTargetInstruction:
        'Keep the {prop} aligned on the forearm through one confirmed hold',
  ),
  'Elbow Stall': MovementCoachingProfile(
    confirmedStrengthMessage: 'Elbow-crease balance held steady',
    formStrengthMessage: 'Correct elbow stall position detected',
    cleanSessionMessage:
        'No recurring balance issues — elbow-crease placement stayed steady.',
    successfulRecommendationReason:
        'Repeat elbow-crease balancing to hold the prop steady through confirmation.',
    holdTargetInstruction:
        'Maintain the {prop} over the elbow crease through one confirmed hold',
  ),
  'Reverse Forearm Stall': MovementCoachingProfile(
    confirmedStrengthMessage: 'Reverse forearm balance held steady',
    formStrengthMessage: 'Correct reverse forearm placement detected',
    cleanSessionMessage:
        'No recurring balance issues — reverse forearm placement held steady.',
    successfulRecommendationReason:
        'Repeat reverse forearm placement to extend a steady confirmed balance.',
    holdTargetInstruction:
        'Keep the bottle on the reverse forearm through one confirmed hold',
  ),
  'Shoulder Stall': MovementCoachingProfile(
    confirmedStrengthMessage: 'Shoulder balance held steady',
    formStrengthMessage: 'Correct shoulder stall position detected',
    cleanSessionMessage:
        'No recurring balance issues — shoulder stall position stayed stable.',
    successfulRecommendationReason:
        'Repeat shoulder balancing to keep the bottle stable through confirmation.',
    holdTargetInstruction:
        'Keep the bottle balanced on top of the shoulder through one confirmed hold',
  ),
  'Double Hand Stall': MovementCoachingProfile(
    confirmedStrengthMessage: 'Both bottle stalls held together',
    formStrengthMessage: 'One upright bottle detected over each open palm',
    cleanSessionMessage:
        'No recurring balance issues — both palm stalls stayed coordinated.',
    successfulRecommendationReason:
        'Repeat dual-palm stalls until both bottles hold together through confirmation.',
    holdTargetInstruction:
        'Keep both bottles balanced simultaneously through one confirmed hold',
  ),
  'Bottle in a tin': MovementCoachingProfile(
    confirmedStrengthMessage: 'Bottle-on-shaker balance confirmed',
    formStrengthMessage: 'Upright bottle detected over the horizontal shaker',
    cleanSessionMessage:
        'No recurring balance issues — bottle stayed centered on the shaker.',
    successfulRecommendationReason:
        'Repeat bottle-on-shaker balancing to center the bottle through confirmation.',
    holdTargetInstruction:
        'Keep the bottle centered on the horizontal shaker through one confirmed hold',
  ),
};

MovementCoachingProfile? movementCoachingProfileFor(String movement) =>
    movementCoachingProfiles[movement];

String confirmedStrengthMessageFor(String movement) =>
    movementCoachingProfileFor(movement)?.confirmedStrengthMessage ??
    '$movement confirmed';

String formStrengthMessageFor(String movement) =>
    movementCoachingProfileFor(movement)?.formStrengthMessage ??
    'Correct $movement form detected';

String cleanSessionMessageFor(String movement) =>
    movementCoachingProfileFor(movement)?.cleanSessionMessage ??
    'No recurring technique issue met the session threshold.';

String successfulRecommendationReasonFor(String movement) =>
    movementCoachingProfileFor(movement)?.successfulRecommendationReason ??
    'Practice $movement again to reinforce a confirmed hold.';

/// Prop-aware hold target instruction before duration suffixing.
String holdTargetInstructionFor(String movement, TrainingProp prop) {
  final instruction = movementCoachingProfileFor(
    movement,
  )?.holdTargetInstruction;
  if (instruction == null) {
    return 'Complete one confirmed hold';
  }
  return instruction.replaceAll('{prop}', coachingPropLabel(prop));
}

String? positiveLockedCodeForMovement(String movement) =>
    movementPositiveLockedCodes[movement];

/// Lowercase prop label used inside coaching focus sentences.
String coachingPropLabel(TrainingProp prop) => prop.displayLabel.toLowerCase();

int recommendedDurationForMovement(String movement) {
  return movementRecommendedDurationSeconds[movement] ??
      defaultRecommendedDurationSeconds;
}

/// Prop-aware focus copy for registered technique codes.
String focusCopyForCode(
  String? code, {
  required TrainingProp prop,
  required String fallbackMessage,
}) {
  final label = coachingPropLabel(prop);
  switch (code) {
    // Shared technique
    case 'palm_not_open':
      return 'Open your palm and extend your fingers';
    case 'both_palms_not_open':
      return 'Open both palms and extend your fingers';
    case 'prop_not_upright':
      return 'Keep the $label upright';
    case 'prop_base_not_on_palm':
      return 'Place the $label base on your open palm';
    case 'prop_not_above_palm':
      return 'Keep the $label directly above your palm';
    case 'prop_not_steady':
      return 'Hold the $label steady';
    case 'prop_not_positioned_on_target':
      return 'Align the $label over the stall point';
    case 'hand_bottle_too_far':
      return 'Move the $label closer to your hand';
    case 'pinch_not_closed':
      return 'Pinch the $label between thumb and fingers';
    case 'prop_not_in_pinch':
      return 'Move the $label into the pinch';

    // Normal / reverse grips
    case 'hand_not_at_neck':
      return 'Move your hand to the upper bottle neck';
    case 'overhand_grip_required':
      return 'Rotate your wrist into an overhand grip';
    case 'underhand_grip_required':
      return 'Rotate your wrist into a reverse grip';
    case 'insufficient_neck_finger_wrap':
      return 'Wrap at least three fingers around the bottle neck';
    case 'reverse_pinky_thumb_orientation':
      return 'Point your pinky toward the bottle mouth and thumb toward the base';
    case 'normal_grip_locked':
      return 'Maintain a locked-in normal grip';
    case 'reverse_grip_locked':
      return 'Maintain a locked-in reverse grip';

    // Bartender's Grip
    case 'bartender_grip_position':
      return 'Grip the bottle at the upper neck and shoulder';
    case 'bartender_pinch_required':
      return 'Secure the neck between your thumb and index finger';
    case 'bartender_hand_orientation':
      return "Turn your hand sideways for a bartender's grip";
    case 'bartender_palm_too_low':
      return "Raise your palm above the bottle center for a bartender's grip";
    case 'bartender_index_extension':
      return 'Extend your index finger along the bottle neck';
    case 'bartender_wrap_fingers':
      return 'Wrap your other fingers around the bottle shoulder';
    case 'bartender_grip_locked':
      return "Maintain a locked-in bartender's grip";

    // Claw Grip
    case 'claw_wrist_above_neck':
      return 'Place your wrist above the bottle mouth and upper neck';
    case 'claw_reach_from_above':
      return 'Reach down from above onto the upper neck';
    case 'claw_fingers_not_curled':
      return 'Curl your fingers downward around the upper neck';
    case 'claw_not_pinch_grip':
      return 'Curl multiple fingers around the neck instead of pinching';
    case 'claw_not_side_overhand':
      return 'Use a top-down claw grip, not a side overhand wrap';
    case 'claw_not_reverse_hold':
      return 'Use a top-down claw grip, not a reverse underhand hold';
    case 'claw_palm_over_mouth':
      return 'Reach down from above with your palm over the bottle mouth';
    case 'claw_thumb_support':
      return 'Support the opposite side of the neck with your thumb';
    case 'claw_more_fingers_curled':
      return 'Curl more fingers around the bottle mouth and upper neck';
    case 'claw_grip_locked':
      return 'Maintain a locked-in claw grip';

    // Hand Stall / One Finger Stall
    case 'hand_stall_locked':
      return 'Maintain a locked-in hand stall';
    case 'index_finger_not_extended':
      return 'Extend one index finger straight';
    case 'other_fingers_not_curled':
      return 'Curl your other fingers and keep only the index finger extended';
    case 'prop_base_not_on_index':
      return 'Place the $label base on the tip of your index finger';
    case 'prop_not_centered_on_index':
      return 'Center the $label over your index fingertip';
    case 'one_finger_stall_locked':
      return 'Maintain a locked-in one finger stall';

    // Arm stalls
    case 'forearm_stall_locked':
      return 'Maintain a locked-in forearm stall';
    case 'elbow_stall_locked':
      return 'Maintain a locked-in elbow stall';
    case 'prop_too_near_elbow':
      return 'Move the bottle away from the elbow onto the reverse forearm';
    case 'prop_too_near_mid_forearm':
      return 'Keep the bottle on the reverse forearm, not the mid-forearm';
    case 'prop_not_on_reverse_forearm':
      return 'Balance the bottle on your reverse forearm';
    case 'reverse_forearm_stall_locked':
      return 'Maintain a locked-in reverse forearm stall';
    case 'prop_below_shoulder':
      return 'Rest the bottle on top of your shoulder, not on your chest';
    case 'prop_not_on_shoulder':
      return 'Balance the bottle steadily on either shoulder';
    case 'shoulder_stall_locked':
      return 'Maintain a locked-in shoulder stall';

    // Double Hand Stall
    case 'both_palms_height_mismatch':
      return 'Keep both palms at the same height';
    case 'bottles_not_one_per_palm':
      return 'Position one bottle directly above each palm';
    case 'both_props_not_steady':
      return 'Hold both props steady';
    case 'double_hand_stall_locked':
      return 'Maintain a locked-in double hand stall';

    // Bottle in a tin
    case 'shaker_not_horizontal':
      return 'Hold the cocktail shaker horizontally';
    case 'bottle_not_centered_on_shaker':
      return 'Center the bottle over the shaker';
    case 'bottle_not_on_shaker':
      return 'Place the bottle on top of the shaker';
    case 'bottle_in_tin_locked':
      return 'Maintain a locked-in bottle in a tin';
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

String formatHoldTargetLabel({
  required String movement,
  required TrainingProp prop,
  required int holdTargetMs,
}) {
  final instruction = holdTargetInstructionFor(movement, prop);
  if (holdTargetMs <= 0) {
    return instruction;
  }
  final seconds = holdTargetMs / 1000.0;
  final formatted = seconds == seconds.roundToDouble()
      ? seconds.round().toString()
      : seconds.toStringAsFixed(1);
  return '$instruction ($formatted seconds)';
}
