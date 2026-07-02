from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    bottle_hand_distance,
    check_bottle_visible,
    check_shoulder_alignment,
    check_stance_stability,
    detect_tap_pulse,
    nearest_hand_to_bottle,
)
from config import TAP_CONTACT_THRESHOLD
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    bottle_check = check_bottle_visible(bottle)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    shoulder_check = check_shoulder_alignment(pose)
    if shoulder_check:
        return shoulder_check, prev_hip_center, movement_state

    stance_check, hip_center = check_stance_stability(pose, prev_hip_center)

    if hands is None or bottle is None:
        return (
            RuleResult(
                feedback="Keep your hand in frame to tap the bottle.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    _, palm = nearest_hand_to_bottle(hands, bottle)
    if palm is None:
        return (
            RuleResult(
                feedback="Keep your hand in frame to tap the bottle.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    dist = bottle_hand_distance(bottle, palm)
    state, tapped = detect_tap_pulse(movement_state, dist, threshold=TAP_CONTACT_THRESHOLD)
    tap_count = int(state.get("tap_count", 0))

    if tapped:
        result = RuleResult(
            feedback="Good tap contact. Keep the rhythm going.",
            feedback_type="positive",
            posture_status="stable",
        )
    elif dist <= TAP_CONTACT_THRESHOLD:
        result = RuleResult(
            feedback="Hold controlled contact, then release for the next tap.",
            feedback_type="warning",
            posture_status="stable",
        )
    elif tap_count > 0:
        result = RuleResult(
            feedback=f"Nice rhythm ({tap_count} taps). Tap the bottle again.",
            feedback_type="warning",
            posture_status="stable",
        )
    else:
        result = RuleResult(
            feedback="Tap the bottle with controlled contact.",
            feedback_type="warning",
            posture_status="unstable",
        )

    if result.feedback_type != "positive" and stance_check:
        return stance_check, hip_center, state
    return result, hip_center, state
