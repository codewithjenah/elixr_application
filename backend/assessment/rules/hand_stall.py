from typing import Optional

from config import (
    HAND_STALL_BASE_TO_PALM,
    HAND_STALL_BELOW_PALM_REJECT,
    HAND_STALL_MAX_HORIZONTAL_OFFSET,
    HAND_STALL_MIN_EXTENDED_FINGERS,
    HAND_STALL_OPEN_PALM_EXTENSION_RATIO,
    HAND_STALL_UPRIGHT_ASPECT_RATIO,
)
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    is_open_palm,
    track_bottle_stability,
    usable_hands_with_palms,
)
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D, PoseLandmarks


def _dist(a: Point2D, b: Point2D) -> float:
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


def _is_upright(bottle: BottleDetection) -> bool:
    width = max(1, bottle.x2 - bottle.x1)
    height = max(0, bottle.y2 - bottle.y1)
    return (height / width) >= HAND_STALL_UPRIGHT_ASPECT_RATIO


def _nearest_hand_to_bottle_base(
    usable: list[tuple[HandLandmarks, Point2D]],
    bottle_base: Point2D,
) -> tuple[HandLandmarks, Point2D]:
    """Pick the usable palm nearest the bottle bottom-center (not bbox center).

    MediaPipe list order and Left/Right labels are intentionally ignored.
    """
    best_hand, best_palm = usable[0]
    best_dist = _dist(best_palm, bottle_base)
    for hand, palm in usable[1:]:
        dist = _dist(palm, bottle_base)
        if dist < best_dist:
            best_dist = dist
            best_hand = hand
            best_palm = palm
    return best_hand, best_palm


def _with_criteria(
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
            locked_code=FeedbackCode.HAND_STALL_LOCKED.value,
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
    # Pose is unused: Hand Stall requires MediaPipe Hands + bottle geometry.
    _ = pose
    prop_name = prop_label.strip() or "prop"
    prop_name_lower = prop_name.lower()

    bottle_check = check_bottle_visible(bottle, prop_label=prop_name)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    usable = usable_hands_with_palms(hands)
    if not usable:
        return (
            RuleResult(
                feedback="Keep your hand fully visible.",
                feedback_type="warning",
                posture_status="unknown",
                feedback_code=FeedbackCode.HAND_NOT_FULLY_VISIBLE.value,
            ),
            prev_hip_center,
            movement_state,
        )

    bottle_base = bottle.bottom_center_normalized(640, 480)
    hand, palm = _nearest_hand_to_bottle_base(usable, bottle_base)

    technique_fail = None
    if not is_open_palm(
        hand,
        extension_ratio=HAND_STALL_OPEN_PALM_EXTENSION_RATIO,
        min_extended=HAND_STALL_MIN_EXTENDED_FINGERS,
    ):
        technique_fail = FeedbackCode.PALM_NOT_OPEN.value
    elif not _is_upright(bottle):
        technique_fail = FeedbackCode.PROP_NOT_UPRIGHT.value

    positioning_fail = None
    if bottle_base.y > palm.y + HAND_STALL_BELOW_PALM_REJECT:
        positioning_fail = FeedbackCode.PROP_BASE_NOT_ON_PALM.value
    elif abs(bottle_base.x - palm.x) > HAND_STALL_MAX_HORIZONTAL_OFFSET:
        positioning_fail = FeedbackCode.PROP_NOT_ABOVE_PALM.value
    elif _dist(bottle_base, palm) > HAND_STALL_BASE_TO_PALM:
        positioning_fail = FeedbackCode.PROP_BASE_NOT_ON_PALM.value

    if technique_fail is None and positioning_fail is None:
        state, stable = track_bottle_stability(movement_state, bottle)
    else:
        _, stable = track_bottle_stability(
            dict(movement_state) if movement_state else None,
            bottle,
        )
        state = movement_state
    stability_fail = None if stable else FeedbackCode.PROP_NOT_STEADY.value

    def _credited(result: RuleResult) -> RuleResult:
        return _with_criteria(
            result,
            technique_fail=technique_fail,
            positioning_fail=positioning_fail,
            stability_fail=stability_fail,
        )

    # Headline coaching still uses the original first-failure order.
    if technique_fail == FeedbackCode.PALM_NOT_OPEN.value:
        return (
            _credited(
                RuleResult(
                    feedback="Open your palm and extend your fingers.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PALM_NOT_OPEN.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if technique_fail == FeedbackCode.PROP_NOT_UPRIGHT.value:
        return (
            _credited(
                RuleResult(
                    feedback=f"Keep the {prop_name_lower} upright on your palm.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_UPRIGHT.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_BASE_NOT_ON_PALM.value and (
        bottle_base.y > palm.y + HAND_STALL_BELOW_PALM_REJECT
    ):
        return (
            _credited(
                RuleResult(
                    feedback=(
                        f"Place the {prop_name_lower} base directly on your open palm."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_BASE_NOT_ON_PALM.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_NOT_ABOVE_PALM.value:
        return (
            _credited(
                RuleResult(
                    feedback=f"Move the {prop_name_lower} directly above your palm.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_ABOVE_PALM.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_BASE_NOT_ON_PALM.value:
        return (
            _credited(
                RuleResult(
                    feedback=(
                        f"Place the {prop_name_lower} base directly on your open palm."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_BASE_NOT_ON_PALM.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if stability_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback=f"Hold the {prop_name_lower} steady on your open palm.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_STEADY.value,
                )
            ),
            prev_hip_center,
            state,
        )

    return (
        _credited(
            RuleResult(
                feedback="Hand stall locked in.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
            )
        ),
        prev_hip_center,
        state,
    )
