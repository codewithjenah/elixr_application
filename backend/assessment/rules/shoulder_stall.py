from typing import Optional

from config import (
    SHOULDER_ABOVE_OFFSET,
    SHOULDER_BELOW_REJECT,
    SHOULDER_STALL_PROXIMITY,
)
from assessment.feedback_codes import FeedbackCode
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    pose_nearest_shoulder,
    pose_shoulder_point,
    track_bottle_stability,
)
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks


def _dist(a: Point2D, b: Point2D) -> float:
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


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

    shoulder = pose_nearest_shoulder(pose, bottle)
    target = pose_shoulder_point(
        pose, bottle, above_offset=SHOULDER_ABOVE_OFFSET
    )
    if shoulder is None or target is None:
        return (
            RuleResult(
                feedback="Show your shoulders so the stall point can be tracked.",
                feedback_type="warning",
                posture_status="unknown",
                feedback_code=FeedbackCode.SHOULDERS_NOT_VISIBLE.value,
            ),
            prev_hip_center,
            movement_state,
        )

    state, stable = track_bottle_stability(movement_state, bottle)
    bottle_center = bottle.center_normalized(640, 480)

    # Image y increases downward: larger y than the shoulder means below/chest.
    if bottle_center.y > shoulder.y + SHOULDER_BELOW_REJECT:
        return (
            RuleResult(
                feedback="Rest the bottle on top of your shoulder, not on your chest.",
                feedback_type="warning",
                posture_status="unstable",
                feedback_code=FeedbackCode.PROP_BELOW_SHOULDER.value,
            ),
            prev_hip_center,
            state,
        )

    dist_target = _dist(bottle_center, target)
    if dist_target > SHOULDER_STALL_PROXIMITY:
        return (
            RuleResult(
                feedback="Balance the bottle steadily on either shoulder.",
                feedback_type="warning",
                posture_status="unstable",
                feedback_code=FeedbackCode.PROP_NOT_ON_SHOULDER.value,
            ),
            prev_hip_center,
            state,
        )

    if not stable:
        return (
            RuleResult(
                feedback="Hold the bottle steady on your shoulder.",
                feedback_type="warning",
                posture_status="unstable",
                feedback_code=FeedbackCode.PROP_NOT_STEADY.value,
            ),
            prev_hip_center,
            state,
        )

    return (
        RuleResult(
            feedback="Shoulder stall locked in.",
            feedback_type="positive",
            posture_status="stable",
            feedback_code=FeedbackCode.SHOULDER_STALL_LOCKED.value,
        ),
        prev_hip_center,
        state,
    )
