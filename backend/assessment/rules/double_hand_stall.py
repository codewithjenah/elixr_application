from typing import Optional

from config import (
    DOUBLE_HAND_BELOW_REJECT,
    DOUBLE_HAND_BOTTLE_BASE_TO_PALM,
    DOUBLE_HAND_MAX_BOTTLE_HEIGHT_DIFF,
    DOUBLE_HAND_MAX_PALM_HEIGHT_DIFF,
    DOUBLE_HAND_MIN_PALM_SEPARATION,
    DOUBLE_HAND_UPRIGHT_ASPECT_RATIO,
)
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    is_open_palm,
    track_bottle_stability,
    uncertain_result,
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


def _credited(
    result: RuleResult,
    *,
    technique_fail: str | None = None,
    positioning_fail: str | None = None,
    stability_fail: str | None = None,
) -> RuleResult:
    return attach_criteria(
        result,
        evaluable_criterion_results(
            technique_fail=technique_fail,
            positioning_fail=positioning_fail,
            stability_fail=stability_fail,
            locked_code=FeedbackCode.DOUBLE_HAND_STALL_LOCKED.value,
        ),
    )


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
            uncertain_result(
                "Keep both bottles visible.",
                code=FeedbackCode.BOTH_BOTTLES_NOT_VISIBLE,
                feedback_type="error",
            ),
            prev_hip_center,
            movement_state,
        )

    if len(bottle_list) < 2:
        return (
            uncertain_result(
                "Use two bottles—one above each open palm.",
                code=FeedbackCode.NEED_TWO_BOTTLES,
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
            uncertain_result(
                "Keep both hands fully visible.",
                code=FeedbackCode.BOTH_HANDS_NOT_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    # Spatial palm order — never rely on MediaPipe list order or handedness.
    ordered = sorted(usable, key=lambda item: item[1].x)
    left_hand, left_palm = ordered[0]
    right_hand, right_palm = ordered[-1]

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

    technique_fail = None
    if not is_open_palm(left_hand) or not is_open_palm(right_hand):
        technique_fail = FeedbackCode.BOTH_PALMS_NOT_OPEN.value
    elif abs(left_palm.y - right_palm.y) > DOUBLE_HAND_MAX_PALM_HEIGHT_DIFF:
        technique_fail = FeedbackCode.BOTH_PALMS_HEIGHT_MISMATCH.value
    elif not _is_upright(left_bottle) or not _is_upright(right_bottle):
        technique_fail = FeedbackCode.PROP_NOT_UPRIGHT.value

    positioning_fail = None
    if _dist(left_palm, right_palm) < DOUBLE_HAND_MIN_PALM_SEPARATION:
        positioning_fail = FeedbackCode.BOTTLES_NOT_ONE_PER_PALM.value
    elif both_prefer_left or both_prefer_right:
        positioning_fail = FeedbackCode.BOTTLES_NOT_ONE_PER_PALM.value
    elif abs(left_base.y - right_base.y) > DOUBLE_HAND_MAX_BOTTLE_HEIGHT_DIFF:
        positioning_fail = FeedbackCode.BOTTLES_NOT_ONE_PER_PALM.value
    elif (
        left_base.y > left_palm.y + DOUBLE_HAND_BELOW_REJECT
        or right_base.y > right_palm.y + DOUBLE_HAND_BELOW_REJECT
    ):
        positioning_fail = FeedbackCode.BOTTLES_NOT_ONE_PER_PALM.value
    elif (
        left_to_left > DOUBLE_HAND_BOTTLE_BASE_TO_PALM
        or right_to_right > DOUBLE_HAND_BOTTLE_BASE_TO_PALM
    ):
        positioning_fail = FeedbackCode.BOTTLES_NOT_ONE_PER_PALM.value

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
    stability_fail = (
        None
        if left_stable and right_stable
        else FeedbackCode.BOTH_PROPS_NOT_STEADY.value
    )

    if technique_fail == FeedbackCode.BOTH_PALMS_NOT_OPEN.value:
        return (
            _credited(
                RuleResult(
                    feedback="Open both palms and extend your fingers.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.BOTH_PALMS_NOT_OPEN.value,
                ),
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    if positioning_fail is not None and _dist(
        left_palm, right_palm
    ) < DOUBLE_HAND_MIN_PALM_SEPARATION:
        return (
            _credited(
                RuleResult(
                    feedback="Position one bottle directly above each palm.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.BOTTLES_NOT_ONE_PER_PALM.value,
                ),
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    if technique_fail == FeedbackCode.BOTH_PALMS_HEIGHT_MISMATCH.value:
        return (
            _credited(
                RuleResult(
                    feedback="Keep both palms at the same height.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.BOTH_PALMS_HEIGHT_MISMATCH.value,
                ),
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    if technique_fail == FeedbackCode.PROP_NOT_UPRIGHT.value:
        # Keep original headline order: pairing/height mismatches before upright.
        if positioning_fail is not None:
            return (
                _credited(
                    RuleResult(
                        feedback="Position one bottle directly above each palm.",
                        feedback_type="warning",
                        posture_status="unstable",
                        feedback_code=FeedbackCode.BOTTLES_NOT_ONE_PER_PALM.value,
                    ),
                    technique_fail=technique_fail,
                    positioning_fail=positioning_fail,
                    stability_fail=stability_fail,
                ),
                prev_hip_center,
                current,
            )
        return (
            _credited(
                RuleResult(
                    feedback="Keep both bottles upright.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_UPRIGHT.value,
                ),
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    if positioning_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback="Position one bottle directly above each palm.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.BOTTLES_NOT_ONE_PER_PALM.value,
                ),
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    if stability_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback="Hold both bottles and hands steady.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.BOTH_PROPS_NOT_STEADY.value,
                ),
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    return (
        _credited(
            RuleResult(
                feedback="Double hand stall locked in.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.DOUBLE_HAND_STALL_LOCKED.value,
            )
        ),
        prev_hip_center,
        current,
    )
