from typing import Optional

from config import (
    UPPER_FOREARM_ELBOW_ZONE,
    UPPER_FOREARM_MID_ZONE,
    UPPER_FOREARM_RATIO,
    UPPER_FOREARM_STALL_PROXIMITY,
)
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    pose_upper_forearm_landmarks,
    track_bottle_stability,
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
            locked_code=FeedbackCode.REVERSE_FOREARM_STALL_LOCKED.value,
        ),
    )


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

    landmarks = pose_upper_forearm_landmarks(
        pose, bottle, ratio=UPPER_FOREARM_RATIO
    )
    if landmarks is None:
        return (
            RuleResult(
                feedback="Show your elbow and wrist so the reverse forearm can be tracked.",
                feedback_type="warning",
                posture_status="unknown",
                feedback_code=FeedbackCode.POSE_ARM_NOT_VISIBLE.value,
            ),
            prev_hip_center,
            movement_state,
        )

    elbow, upper, mid, _wrist = landmarks
    state, stable = track_bottle_stability(movement_state, bottle)
    bottle_center = bottle.center_normalized(640, 480)
    stability_fail = None if stable else FeedbackCode.PROP_NOT_STEADY.value

    dist_elbow = _dist(bottle_center, elbow)
    dist_upper = _dist(bottle_center, upper)
    dist_mid = _dist(bottle_center, mid)

    positioning_fail = None
    if dist_elbow <= UPPER_FOREARM_ELBOW_ZONE and dist_elbow < dist_upper:
        positioning_fail = FeedbackCode.PROP_TOO_NEAR_ELBOW.value
    elif dist_mid <= UPPER_FOREARM_MID_ZONE and dist_mid < dist_upper:
        positioning_fail = FeedbackCode.PROP_TOO_NEAR_MID_FOREARM.value
    elif dist_upper > UPPER_FOREARM_STALL_PROXIMITY:
        positioning_fail = FeedbackCode.PROP_NOT_ON_REVERSE_FOREARM.value

    if positioning_fail == FeedbackCode.PROP_TOO_NEAR_ELBOW.value:
        return (
            _credited(
                RuleResult(
                    feedback="Move the bottle away from the elbow onto the reverse forearm.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_TOO_NEAR_ELBOW.value,
                ),
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_TOO_NEAR_MID_FOREARM.value:
        return (
            _credited(
                RuleResult(
                    feedback="Keep the bottle on the reverse forearm, not the mid-forearm or wrist.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_TOO_NEAR_MID_FOREARM.value,
                ),
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_NOT_ON_REVERSE_FOREARM.value:
        return (
            _credited(
                RuleResult(
                    feedback="Balance the bottle on your reverse forearm between elbow and mid-arm.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_ON_REVERSE_FOREARM.value,
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
                    feedback="Hold the bottle steady on your reverse forearm.",
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
                feedback="Reverse forearm stall locked in.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.REVERSE_FOREARM_STALL_LOCKED.value,
            ),
            positioning_fail=None,
            stability_fail=None,
        ),
        prev_hip_center,
        state,
    )
