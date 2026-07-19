from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_hand_bottle_proximity,
    check_hands_visible,
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

    palm = hands.nearest_palm_to(bottle.center_normalized(640, 480))
    proximity = check_hand_bottle_proximity(
        bottle,
        palm,
        far_message="Wrap your hand onto the bottle for a normal grip.",
        near_message="Bottle held securely in normal grip.",
    )
    return proximity, prev_hip_center, movement_state
