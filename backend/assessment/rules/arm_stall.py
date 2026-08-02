from typing import Optional

from config import ARM_STALL_PROXIMITY
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_hands_visible,
    check_stall_proximity,
    pose_forearm_point,
    track_bottle_stability,
)
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
    *,
    prop_label: str = "Bottle",
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    prop_name = prop_label.strip() or "prop"
    prop_name_lower = prop_name.lower()
    bottle_check = check_bottle_visible(bottle, prop_label=prop_name)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    state, stable = track_bottle_stability(movement_state, bottle)

    # Prefer the pose forearm (elbow-wrist midpoint); fall back to the hand palm.
    forearm = pose_forearm_point(pose, bottle)
    if forearm is not None:
        stall = check_stall_proximity(
            bottle,
            forearm,
            success_message="Stable forearm stall.",
            threshold=ARM_STALL_PROXIMITY,
            prop_label=prop_name,
        )
    else:
        hands_check = check_hands_visible(hands)
        if hands_check:
            return hands_check, prev_hip_center, state
        palm = hands.nearest_palm_to(bottle.center_normalized(640, 480))
        stall = check_stall_proximity(
            bottle,
            palm,
            success_message="Stable forearm stall.",
            threshold=ARM_STALL_PROXIMITY,
            prop_label=prop_name,
        )
    if stall.feedback_type != "positive":
        return stall, prev_hip_center, state

    if not stable:
        return (
            RuleResult(
                feedback=f"Hold the {prop_name_lower} steady on your forearm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    return stall, prev_hip_center, state
