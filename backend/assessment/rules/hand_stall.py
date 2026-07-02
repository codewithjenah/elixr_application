from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_shoulder_alignment,
    check_stall_proximity,
    check_stance_stability,
    dominant_wrist,
)
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

    target: Optional[Point2D] = None
    if hands and bottle:
        target = hands.nearest_palm_to(bottle.center_normalized(640, 480))
    if target is None and pose:
        target = dominant_wrist(pose)

    stall = check_stall_proximity(
        bottle,
        target,
        success_message="Good hand stall position.",
    )

    if stall.feedback_type != "positive":
        return stall, hip_center, movement_state
    if stance_check:
        return stance_check, hip_center, movement_state
    return stall, hip_center, movement_state
