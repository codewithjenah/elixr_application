from typing import Optional

from config import (
    FOREARM_STALL_MAX_ALONG_FRACTION,
    FOREARM_STALL_MAX_CONTACT_DISTANCE,
    FOREARM_STALL_MIN_ALONG_FRACTION,
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

    # An upright prop rests on the arm at the bottom-center of its detection;
    # the bbox center can sit well above the actual support/contact point.
    contact = bottle.bottom_center_normalized(640, 480)
    segment = pose_nearest_forearm_segment(
        pose,
        contact,
        target_fraction_from_elbow=0.5,
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
    positioned = geometry is not None and (
        FOREARM_STALL_MIN_ALONG_FRACTION
        <= geometry.along_fraction
        <= FOREARM_STALL_MAX_ALONG_FRACTION
        and geometry.perpendicular_distance
        <= scaled_proximity(FOREARM_STALL_MAX_CONTACT_DISTANCE, state)
    )
    stall = (
        RuleResult(
            feedback="Stable forearm stall.",
            feedback_type="positive",
            posture_status="stable",
            feedback_code=FeedbackCode.FOREARM_STALL_LOCKED.value,
        )
        if positioned
        else RuleResult(
            feedback=f"Align the {prop_name_lower} over the stall point.",
            feedback_type="warning",
            posture_status="unstable",
            feedback_code=FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value,
        )
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
