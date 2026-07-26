from typing import Optional

from config import (
    DOUBLE_HAND_BALANCE_TOLERANCE,
    DOUBLE_HAND_BELOW_REJECT,
    DOUBLE_HAND_HORIZONTAL_MARGIN,
    DOUBLE_HAND_MAX_HEIGHT_DIFFERENCE,
    DOUBLE_HAND_MAX_SEPARATION,
    DOUBLE_HAND_MAX_SUPPORT_DISTANCE,
    DOUBLE_HAND_MIN_SEPARATION,
    DOUBLE_HAND_STALL_PROXIMITY,
    DOUBLE_HAND_TARGET_ABOVE_OFFSET,
)
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    track_bottle_stability,
    visible_palm_centers,
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

    palms = visible_palm_centers(hands)
    if len(palms) < 2:
        return (
            RuleResult(
                feedback="Keep both hands visible for the double hand stall.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    # Spatial order — never rely on MediaPipe list order or handedness labels.
    ordered = sorted(palms, key=lambda p: p.x)
    left_palm, right_palm = ordered[0], ordered[-1]

    separation = _dist(left_palm, right_palm)
    if separation < DOUBLE_HAND_MIN_SEPARATION:
        return (
            RuleResult(
                feedback="Separate your palms slightly under the bottle.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )
    if separation > DOUBLE_HAND_MAX_SEPARATION:
        return (
            RuleResult(
                feedback="Bring your palms closer together under the bottle.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    height_diff = abs(left_palm.y - right_palm.y)
    if height_diff > DOUBLE_HAND_MAX_HEIGHT_DIFFERENCE:
        return (
            RuleResult(
                feedback="Keep both palms at the same height.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    target = Point2D(
        x=(left_palm.x + right_palm.x) / 2.0,
        y=(left_palm.y + right_palm.y) / 2.0
        - DOUBLE_HAND_TARGET_ABOVE_OFFSET,
    )
    bottle_center = bottle.center_normalized(640, 480)
    state, stable = track_bottle_stability(movement_state, bottle)

    palm_line_y = max(left_palm.y, right_palm.y)
    if bottle_center.y > palm_line_y + DOUBLE_HAND_BELOW_REJECT:
        return (
            RuleResult(
                feedback="Position both palms underneath the bottle.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    left_bound = left_palm.x - DOUBLE_HAND_HORIZONTAL_MARGIN
    right_bound = right_palm.x + DOUBLE_HAND_HORIZONTAL_MARGIN
    if bottle_center.x < left_bound or bottle_center.x > right_bound:
        return (
            RuleResult(
                feedback="Center the bottle evenly between both palms.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    dist_left = _dist(bottle_center, left_palm)
    dist_right = _dist(bottle_center, right_palm)
    if (
        dist_left > DOUBLE_HAND_MAX_SUPPORT_DISTANCE
        or dist_right > DOUBLE_HAND_MAX_SUPPORT_DISTANCE
    ):
        return (
            RuleResult(
                feedback="Center the bottle evenly between both palms.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    if abs(dist_left - dist_right) > DOUBLE_HAND_BALANCE_TOLERANCE:
        return (
            RuleResult(
                feedback="Center the bottle evenly between both palms.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    if _dist(bottle_center, target) > DOUBLE_HAND_STALL_PROXIMITY:
        return (
            RuleResult(
                feedback="Center the bottle evenly between both palms.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    if not stable:
        return (
            RuleResult(
                feedback="Hold both hands and the bottle steady.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    return (
        RuleResult(
            feedback="Double hand stall locked in.",
            feedback_type="positive",
            posture_status="stable",
        ),
        prev_hip_center,
        state,
    )
