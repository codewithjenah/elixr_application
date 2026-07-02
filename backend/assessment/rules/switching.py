from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_shoulder_alignment,
    check_stance_stability,
    detect_hand_switch,
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
                feedback="Keep both hands visible for switching.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    if len(hands.hands) < 2:
        return (
            RuleResult(
                feedback="Show both hands so the transfer can be tracked.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    state, switched = detect_hand_switch(movement_state, hands, bottle)
    hand, _ = nearest_hand_to_bottle(hands, bottle)

    if switched:
        result = RuleResult(
            feedback="Smooth hand switch. Keep the bottle controlled.",
            feedback_type="positive",
            posture_status="stable",
        )
    elif hand is not None and state.get("holding_hand"):
        result = RuleResult(
            feedback="Transfer the bottle to your other hand.",
            feedback_type="warning",
            posture_status="stable",
        )
    else:
        result = RuleResult(
            feedback="Hold the bottle in one hand to begin switching.",
            feedback_type="warning",
            posture_status="unstable",
        )

    if result.feedback_type != "positive" and stance_check:
        return stance_check, hip_center, state
    return result, hip_center, state
