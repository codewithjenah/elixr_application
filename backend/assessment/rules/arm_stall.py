from typing import Optional

from config import ARM_STALL_PROXIMITY
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_stall_proximity,
    pose_forearm_point,
    track_bottle_stability,
    uncertain_result,
)
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks


def _credited(
    result: RuleResult,
    *,
    positioning_fail: str | None,
    stability_fail: str | None,
) -> RuleResult:
    return attach_criteria(
        result,
        evaluable_criterion_results(
            positioning_fail=positioning_fail,
            stability_fail=stability_fail,
            locked_code=FeedbackCode.FOREARM_STALL_LOCKED.value,
        ),
    )


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
    *,
    prop_label: str = "Bottle",
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    # Hands are unused once the pose forearm is visible; missing the stall
    # joint is Can't determine even if a palm is in frame.
    _ = hands
    prop_name = prop_label.strip() or "prop"
    prop_name_lower = prop_name.lower()
    bottle_check = check_bottle_visible(bottle, prop_label=prop_name)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    forearm = pose_forearm_point(pose, bottle)
    if forearm is None:
        return (
            uncertain_result(
                "Move back so your elbow and forearm are visible.",
                code=FeedbackCode.POSE_ARM_NOT_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    state, stable = track_bottle_stability(movement_state, bottle)
    stability_fail = None if stable else FeedbackCode.PROP_NOT_STEADY.value

    stall = check_stall_proximity(
        bottle,
        forearm,
        success_message="Stable forearm stall.",
        threshold=ARM_STALL_PROXIMITY,
        prop_label=prop_name,
        success_code=FeedbackCode.FOREARM_STALL_LOCKED.value,
    )

    if stall.feedback_type != "positive":
        return (
            _credited(
                stall,
                positioning_fail=stall.feedback_code,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            state,
        )

    if stability_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback=f"Hold the {prop_name_lower} steady on your forearm.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_STEADY.value,
                ),
                positioning_fail=None,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            state,
        )

    return (
        _credited(
            stall,
            positioning_fail=None,
            stability_fail=None,
        ),
        prev_hip_center,
        state,
    )
