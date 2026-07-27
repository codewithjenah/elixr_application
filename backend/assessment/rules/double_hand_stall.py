from typing import Optional

from config import (
    DOUBLE_HAND_BELOW_REJECT,
    DOUBLE_HAND_BOTTLE_BASE_TO_PALM,
    DOUBLE_HAND_MAX_BOTTLE_HEIGHT_DIFF,
    DOUBLE_HAND_MAX_PALM_HEIGHT_DIFF,
    DOUBLE_HAND_MIN_PALM_SEPARATION,
    DOUBLE_HAND_UPRIGHT_ASPECT_RATIO,
)
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    is_open_palm,
    track_bottle_stability,
    usable_hands_with_palms,
)
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks


def _dist(a: Point2D, b: Point2D) -> float:
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


def _is_upright(bottle: BottleDetection) -> bool:
    width = max(1, bottle.x2 - bottle.x1)
    height = max(0, bottle.y2 - bottle.y1)
    return (height / width) >= DOUBLE_HAND_UPRIGHT_ASPECT_RATIO


def _pair_bottles_to_palms(
    bottles: list[BottleDetection],
    left_palm: Point2D,
    right_palm: Point2D,
) -> tuple[BottleDetection, BottleDetection]:
    """Choose the two-bottle/two-palm assignment with smallest total distance."""
    b0, b1 = bottles[0], bottles[1]
    base0 = b0.bottom_center_normalized(640, 480)
    base1 = b1.bottom_center_normalized(640, 480)

    assignment_a = _dist(base0, left_palm) + _dist(base1, right_palm)
    assignment_b = _dist(base1, left_palm) + _dist(base0, right_palm)

    if assignment_a <= assignment_b:
        return b0, b1
    return b1, b0


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
    *,
    bottles: Optional[list[BottleDetection]] = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    bottle_list = list(bottles) if bottles is not None else (
        [bottle] if bottle is not None else []
    )

    if len(bottle_list) == 0:
        return (
            RuleResult(
                feedback="Keep both bottles visible.",
                feedback_type="error",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    if len(bottle_list) < 2:
        return (
            RuleResult(
                feedback="Use two bottles—one above each open palm.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    # Cap at two detections; pairing below is purely geometric.
    if len(bottle_list) > 2:
        bottle_list = sorted(
            bottle_list, key=lambda b: b.confidence, reverse=True
        )[:2]

    usable = usable_hands_with_palms(hands)
    if len(usable) < 2:
        return (
            RuleResult(
                feedback="Keep both hands fully visible.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    # Spatial palm order — never rely on MediaPipe list order or handedness.
    ordered = sorted(usable, key=lambda item: item[1].x)
    left_hand, left_palm = ordered[0]
    right_hand, right_palm = ordered[-1]

    if not is_open_palm(left_hand) or not is_open_palm(right_hand):
        return (
            RuleResult(
                feedback="Open both palms and extend your fingers.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    separation = _dist(left_palm, right_palm)
    if separation < DOUBLE_HAND_MIN_PALM_SEPARATION:
        return (
            RuleResult(
                feedback="Position one bottle directly above each palm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    height_diff = abs(left_palm.y - right_palm.y)
    if height_diff > DOUBLE_HAND_MAX_PALM_HEIGHT_DIFF:
        return (
            RuleResult(
                feedback="Keep both palms at the same height.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    left_bottle, right_bottle = _pair_bottles_to_palms(
        bottle_list, left_palm, right_palm
    )
    left_base = left_bottle.bottom_center_normalized(640, 480)
    right_base = right_bottle.bottom_center_normalized(640, 480)

    left_to_left = _dist(left_base, left_palm)
    left_to_right = _dist(left_base, right_palm)
    right_to_left = _dist(right_base, left_palm)
    right_to_right = _dist(right_base, right_palm)
    both_prefer_left = left_to_left < left_to_right and right_to_left < right_to_right
    both_prefer_right = left_to_right < left_to_left and right_to_right < right_to_left
    if both_prefer_left or both_prefer_right:
        return (
            RuleResult(
                feedback="Position one bottle directly above each palm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if not _is_upright(left_bottle) or not _is_upright(right_bottle):
        return (
            RuleResult(
                feedback="Keep both bottles upright.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if abs(left_base.y - right_base.y) > DOUBLE_HAND_MAX_BOTTLE_HEIGHT_DIFF:
        return (
            RuleResult(
                feedback="Position one bottle directly above each palm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if (
        left_base.y > left_palm.y + DOUBLE_HAND_BELOW_REJECT
        or right_base.y > right_palm.y + DOUBLE_HAND_BELOW_REJECT
    ):
        return (
            RuleResult(
                feedback="Position one bottle directly above each palm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if (
        left_to_left > DOUBLE_HAND_BOTTLE_BASE_TO_PALM
        or right_to_right > DOUBLE_HAND_BOTTLE_BASE_TO_PALM
    ):
        return (
            RuleResult(
                feedback="Position one bottle directly above each palm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    current = dict(movement_state or {})
    left_sub, left_stable = track_bottle_stability(
        current.get("left_palm"),
        left_bottle,
    )
    right_sub, right_stable = track_bottle_stability(
        current.get("right_palm"),
        right_bottle,
    )
    current["left_palm"] = left_sub
    current["right_palm"] = right_sub

    if not left_stable or not right_stable:
        return (
            RuleResult(
                feedback="Hold both bottles and hands steady.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            current,
        )

    return (
        RuleResult(
            feedback="Double hand stall locked in.",
            feedback_type="positive",
            posture_status="stable",
        ),
        prev_hip_center,
        current,
    )
