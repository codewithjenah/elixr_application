from typing import Optional

from config import (
    WRIST_STALL_CONTACT_DISTANCE,
    WRIST_STALL_FOREARM_ALONG_FRACTION,
    WRIST_STALL_MAX_ALONG_FRACTION,
    WRIST_STALL_MAX_SCALED_CONTACT_DISTANCE,
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
    # Both catalog variants are presented upright. Their bottom bbox edge is
    # therefore the only defensible 2D support anchor available from YOLO.
    contact = bottle.bottom_center_normalized(640, 480)
    segment = pose_nearest_forearm_segment(
        pose,
        contact,
        target_fraction_from_elbow=1.0,
    )
    if segment is None:
        return (
            uncertain_result(
                "Keep your elbow and wrist visible.",
                code=FeedbackCode.POSE_ARM_NOT_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    state, stable = track_bottle_stability(movement_state, bottle)
    stability_fail = None if stable else FeedbackCode.PROP_NOT_STEADY.value

    elbow, wrist = segment
    geometry = project_point_to_segment_axis(contact, elbow, wrist)
    contact_tolerance = min(
        scaled_proximity(WRIST_STALL_CONTACT_DISTANCE, state),
        WRIST_STALL_MAX_SCALED_CONTACT_DISTANCE,
    )

    positioning_fail = None
    if (
        geometry is None
        or geometry.perpendicular_distance > contact_tolerance
        or geometry.along_fraction < 0.0
        or geometry.along_fraction > 1.0
    ):
        positioning_fail = FeedbackCode.PROP_NOT_ON_WRIST.value
    elif geometry.along_fraction <= 1.0 - WRIST_STALL_FOREARM_ALONG_FRACTION:
        positioning_fail = FeedbackCode.PROP_ON_FOREARM_NOT_WRIST.value
    elif geometry.along_fraction < 1.0 - WRIST_STALL_MAX_ALONG_FRACTION:
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
