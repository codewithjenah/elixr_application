from typing import Optional

from config import (
    SHOULDER_ABOVE_OFFSET,
    SHOULDER_BELOW_REJECT,
    SHOULDER_STALL_CONTACT_DISTANCE,
    SHOULDER_STALL_MAX_SCALED_CONTACT_DISTANCE,
)
from assessment.calibration import scaled_proximity
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    pose_nearest_shoulder_to_point,
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
            locked_code=FeedbackCode.SHOULDER_STALL_LOCKED.value,
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

    # The upright bottle rests on the shoulder at its bbox bottom-center; its
    # bbox center can be well above the actual support region.
    contact = bottle.bottom_center_normalized(640, 480)
    shoulder = pose_nearest_shoulder_to_point(pose, contact)
    if shoulder is None:
        return (
            uncertain_result(
                "Move back so your shoulder is visible.",
                code=FeedbackCode.SHOULDERS_NOT_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    state, stable = track_bottle_stability(movement_state, bottle)
    stability_fail = None if stable else FeedbackCode.PROP_NOT_STEADY.value
    target = Point2D(
        x=shoulder.x,
        y=shoulder.y - SHOULDER_ABOVE_OFFSET,
    )
    contact_tolerance = min(
        scaled_proximity(SHOULDER_STALL_CONTACT_DISTANCE, state),
        SHOULDER_STALL_MAX_SCALED_CONTACT_DISTANCE,
    )

    positioning_fail = None
    if contact.y > shoulder.y + SHOULDER_BELOW_REJECT:
        positioning_fail = FeedbackCode.PROP_BELOW_SHOULDER.value
    elif _dist(contact, target) > contact_tolerance:
        positioning_fail = FeedbackCode.PROP_NOT_ON_SHOULDER.value

    # Headline coaching still uses the original first-failure order.
    if positioning_fail == FeedbackCode.PROP_BELOW_SHOULDER.value:
        return (
            _credited(
                RuleResult(
                    feedback="Rest the bottle on top of your shoulder, not on your chest.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_BELOW_SHOULDER.value,
                ),
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_NOT_ON_SHOULDER.value:
        return (
            _credited(
                RuleResult(
                    feedback="Balance the bottle steadily on either shoulder.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_ON_SHOULDER.value,
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
                    feedback="Hold the bottle steady on your shoulder.",
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
                feedback="Shoulder stall locked in.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.SHOULDER_STALL_LOCKED.value,
            ),
            positioning_fail=None,
            stability_fail=None,
        ),
        prev_hip_center,
        state,
    )
