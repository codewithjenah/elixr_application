from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_pinch_grip,
    check_shoulder_alignment,
    check_stance_stability,
    nearest_hand_to_bottle,
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

    if hands is None or bottle is None:
        return (
            RuleResult(
                feedback="Keep your hand in frame for the clip.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    hand, _ = nearest_hand_to_bottle(hands, bottle)
    if hand is None:
        return (
            RuleResult(
                feedback="Keep your hand in frame for the clip.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    pinch = check_pinch_grip(hand, bottle)
    if pinch.feedback_type != "positive":
        return pinch, hip_center, movement_state
    if stance_check:
        return stance_check, hip_center, movement_state
    return pinch, hip_center, movement_state
