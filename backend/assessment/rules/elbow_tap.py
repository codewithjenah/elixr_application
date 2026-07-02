from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    bottle_elbow_distance,
    check_bottle_visible,
    check_shoulder_alignment,
    check_stance_stability,
    detect_tap_pulse,
)
from config import ELBOW_TAP_CONTACT_THRESHOLD
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

    if bottle is None or pose is None:
        return (
            RuleResult(
                feedback="Keep the bottle and your arm visible for the elbow tap.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    dist = bottle_elbow_distance(bottle, pose)
    if dist is None:
        return (
            RuleResult(
                feedback="Keep your elbow visible for the tap.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    state, tapped = detect_tap_pulse(
        movement_state,
        dist,
        threshold=ELBOW_TAP_CONTACT_THRESHOLD,
    )
    tap_count = int(state.get("tap_count", 0))

    if tapped:
        result = RuleResult(
            feedback="Good elbow tap contact. Keep the rhythm going.",
            feedback_type="positive",
            posture_status="stable",
        )
    elif dist <= ELBOW_TAP_CONTACT_THRESHOLD:
        result = RuleResult(
            feedback="Hold brief contact on your elbow, then release.",
            feedback_type="warning",
            posture_status="stable",
        )
    elif tap_count > 0:
        result = RuleResult(
            feedback=f"Nice rhythm ({tap_count} taps). Tap the elbow again.",
            feedback_type="warning",
            posture_status="stable",
        )
    else:
        result = RuleResult(
            feedback="Tap the bottle against your elbow with controlled contact.",
            feedback_type="warning",
            posture_status="unstable",
        )

    if result.feedback_type != "positive" and stance_check:
        return stance_check, hip_center, state
    return result, hip_center, state
