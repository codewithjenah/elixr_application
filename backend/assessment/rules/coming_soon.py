from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import check_bottle_visible, check_shoulder_alignment
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

    return (
        RuleResult(
            feedback="Advanced movement rules coming soon. Maintain stable posture.",
            feedback_type="warning",
            posture_status="stable" if pose else "unknown",
        ),
        prev_hip_center,
        movement_state,
    )
