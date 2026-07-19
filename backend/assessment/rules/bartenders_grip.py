from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_hands_visible,
    check_pinch_grip,
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

    hands_check = check_hands_visible(hands)
    if hands_check:
        return hands_check, prev_hip_center, movement_state

    hand, _ = nearest_hand_to_bottle(hands, bottle)
    if hand is None:
        return hands_check or RuleResult(
            feedback="Keep your hand in frame.",
            feedback_type="warning",
            posture_status="unknown",
        ), prev_hip_center, movement_state

    grip = check_pinch_grip(
        hand,
        bottle,
        success_message="Good bartender's grip on the neck.",
    )
    return grip, prev_hip_center, movement_state
