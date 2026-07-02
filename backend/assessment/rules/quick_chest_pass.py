from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_shoulder_alignment,
    check_stance_stability,
    track_hand_transfer,
)
from config import CHEST_LEVEL_MARGIN, HAND_SWITCH_PROXIMITY
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

    if hands is None or bottle is None or pose is None:
        return (
            RuleResult(
                feedback="Keep both hands and the bottle visible for the chest pass.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    if len(hands.hands) < 2:
        return (
            RuleResult(
                feedback="Show both hands so the chest pass can be tracked.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    state, switched = track_hand_transfer(
        movement_state,
        hands,
        bottle,
        pose,
        switch_threshold=HAND_SWITCH_PROXIMITY,
        require_chest_level=True,
        chest_margin=CHEST_LEVEL_MARGIN,
    )

    if switched and state.get("at_chest"):
        result = RuleResult(
            feedback="Quick chest pass complete. Smooth transfer.",
            feedback_type="positive",
            posture_status="stable",
        )
    elif state.get("at_chest") and state.get("holding_hand"):
        result = RuleResult(
            feedback="Good chest position. Finish the pass to your other hand.",
            feedback_type="warning",
            posture_status="stable",
        )
    elif state.get("holding_hand"):
        result = RuleResult(
            feedback="Pass the bottle across your chest to the other hand.",
            feedback_type="warning",
            posture_status="stable",
        )
    else:
        result = RuleResult(
            feedback="Hold the bottle in one hand to begin the chest pass.",
            feedback_type="warning",
            posture_status="unstable",
        )

    if result.feedback_type != "positive" and stance_check:
        return stance_check, hip_center, state
    return result, hip_center, state
