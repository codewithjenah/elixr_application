from typing import Optional

from config import (
    WRIST_STALL_FOREARM_ALONG_FRACTION,
    WRIST_STALL_MAX_ALONG_FRACTION,
    WRIST_STALL_PROXIMITY_RATIO,
)
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    along_wrist_to_elbow_fraction,
    check_bottle_visible,
    pose_wrist_arm_landmarks,
    track_bottle_stability,
    uncertain_result,
)
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks


def _dist(a: Point2D, b: Point2D) -> float:
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


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
            locked_code=FeedbackCode.WRIST_STALL_LOCKED.value,
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
    _ = hands
    prop_name = prop_label.strip() or "prop"
    prop_name_lower = prop_name.lower()
    bottle_check = check_bottle_visible(bottle, prop_label=prop_name)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    assert bottle is not None
    arm = pose_wrist_arm_landmarks(pose, bottle)
    if arm is None:
        return (
            uncertain_result(
                "Keep your elbow and wrist visible.",
                code=FeedbackCode.POSE_ARM_NOT_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    elbow, wrist, mid = arm
    center = bottle.center_normalized(640, 480)
    arm_length = _dist(elbow, wrist)
    if arm_length <= 1e-6:
        return (
            uncertain_result(
                "Keep your elbow and wrist visible.",
                code=FeedbackCode.POSE_ARM_NOT_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    along = along_wrist_to_elbow_fraction(center, elbow, wrist)
    dist_wrist = _dist(center, wrist)
    dist_mid = _dist(center, mid)
    max_wrist_dist = WRIST_STALL_PROXIMITY_RATIO * arm_length

    state, stable = track_bottle_stability(movement_state, bottle)
    stability_fail = None if stable else FeedbackCode.PROP_NOT_STEADY.value

    on_forearm = (
        along >= WRIST_STALL_FOREARM_ALONG_FRACTION or dist_mid <= dist_wrist
    )
    too_far = (
        dist_wrist > max_wrist_dist or along > WRIST_STALL_MAX_ALONG_FRACTION
    )

    positioning_fail = None
    if on_forearm:
        positioning_fail = FeedbackCode.PROP_ON_FOREARM_NOT_WRIST.value
    elif too_far:
        positioning_fail = FeedbackCode.PROP_NOT_ON_WRIST.value

    if positioning_fail == FeedbackCode.PROP_ON_FOREARM_NOT_WRIST.value:
        return (
            _credited(
                RuleResult(
                    feedback=(
                        f"Balance the {prop_name_lower} at the wrist, "
                        "not on the forearm."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_ON_FOREARM_NOT_WRIST.value,
                ),
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_NOT_ON_WRIST.value:
        return (
            _credited(
                RuleResult(
                    feedback=f"Balance the {prop_name_lower} at the wrist.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_ON_WRIST.value,
                ),
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            state,
        )

    if stability_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback=f"Hold the {prop_name_lower} steady at the wrist.",
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
            RuleResult(
                feedback="Stable wrist stall.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.WRIST_STALL_LOCKED.value,
            ),
            positioning_fail=None,
            stability_fail=None,
        ),
        prev_hip_center,
        state,
    )
