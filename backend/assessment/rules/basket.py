from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_basket_hold,
    check_bottle_visible,
    check_hands_visible,
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
        return (
            RuleResult(
                feedback="Keep your cupped hand in frame for the basket catch.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    basket = check_basket_hold(hand, bottle)
    return basket, prev_hip_center, movement_state
