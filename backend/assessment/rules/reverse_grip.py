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

    bottle_center = bottle.center_normalized(640, 480)
    palm = hands.nearest_palm_to(bottle_center)

    proximity = check_hand_bottle_proximity(
        bottle,
        palm,
        far_message="Wrap your hand onto the bottle for a reverse grip.",
        near_message="Correct underhand reverse grip.",
    )
    if proximity.feedback_type != "positive":
        return proximity, prev_hip_center, movement_state

    # Underhand check: the hand should sit below the bottle center.
    if palm is not None and palm.y < bottle_center.y - 0.02:
        return (
            RuleResult(
                feedback="Rotate to an underhand (reverse) grip.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    return proximity, prev_hip_center, movement_state
