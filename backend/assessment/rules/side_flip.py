from typing import Optional

from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    bottle_hand_distance,
    check_bottle_visible,
    check_shoulder_alignment,
    check_stance_stability,
    detect_lateral_flip,
    nearest_hand_to_bottle,
    update_bottle_history,
)
from config import TAP_CONTACT_THRESHOLD
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

    if bottle is None:
        return (
            RuleResult(
                feedback="Keep the bottle visible for the side flip.",
                feedback_type="error",
                posture_status="unknown",
            ),
            hip_center,
            movement_state,
        )

    state = update_bottle_history(movement_state, bottle)
    flip_detected = detect_lateral_flip(state)

    near_hand = False
    if hands is not None:
        _, palm = nearest_hand_to_bottle(hands, bottle)
        if palm is not None:
            near_hand = bottle_hand_distance(bottle, palm) <= TAP_CONTACT_THRESHOLD

    phase = state.get("flip_phase", "ready")
    if flip_detected and not near_hand:
        phase = "air"
    elif phase == "air" and near_hand:
        phase = "caught"
    elif near_hand and phase == "ready":
        phase = "hold"

    state["flip_phase"] = phase

    if phase == "caught":
        result = RuleResult(
            feedback="Side flip caught cleanly.",
            feedback_type="positive",
            posture_status="stable",
        )
    elif phase == "air":
        result = RuleResult(
            feedback="Bottle flipping sideways. Prepare to catch.",
            feedback_type="warning",
            posture_status="stable",
        )
    elif near_hand:
        result = RuleResult(
            feedback="Release with a sideways flip motion.",
            feedback_type="warning",
            posture_status="stable",
        )
    else:
        result = RuleResult(
            feedback="Flip the bottle sideways and catch.",
            feedback_type="warning",
            posture_status="unstable",
        )

    if result.feedback_type != "positive" and stance_check:
        return stance_check, hip_center, state
    return result, hip_center, state
