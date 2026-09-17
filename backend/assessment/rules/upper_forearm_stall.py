from typing import Optional

from config import (
    REVERSE_FOREARM_MAX_ALONG_FRACTION,
    REVERSE_FOREARM_MAX_CONTACT_DISTANCE,
    REVERSE_FOREARM_MIN_ALONG_FRACTION,
    UPPER_FOREARM_RATIO,
)
from assessment.calibration import scaled_proximity
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    pose_nearest_forearm_segment,
    project_point_to_segment_axis,
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

    # Use the bbox support point: its center is not the point resting on the
    # forearm and can shift classification toward the elbow for upright props.
    contact = bottle.bottom_center_normalized(640, 480)
    segment = pose_nearest_forearm_segment(
        pose,
        contact,
        target_fraction_from_elbow=UPPER_FOREARM_RATIO,
    )
    if segment is None:
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

    elbow, wrist = segment
    geometry = project_point_to_segment_axis(contact, elbow, wrist)
    contact_tolerance = scaled_proximity(
        REVERSE_FOREARM_MAX_CONTACT_DISTANCE,
        state,
    )
    positioning_fail = None
    if (
        geometry is None
        or geometry.perpendicular_distance > contact_tolerance
        or geometry.along_fraction < 0.0
        or geometry.along_fraction > 1.0
    ):
        positioning_fail = FeedbackCode.PROP_NOT_ON_REVERSE_FOREARM.value
    elif geometry.along_fraction < REVERSE_FOREARM_MIN_ALONG_FRACTION:
        positioning_fail = FeedbackCode.PROP_TOO_NEAR_ELBOW.value
    elif geometry.along_fraction > REVERSE_FOREARM_MAX_ALONG_FRACTION:
        positioning_fail = FeedbackCode.PROP_TOO_NEAR_MID_FOREARM.value

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
