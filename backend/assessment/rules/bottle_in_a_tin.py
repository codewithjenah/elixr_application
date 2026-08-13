"""Bottle in a tin: upright bottle balanced on a horizontally held shaker.

Geometry checks operate on axis-aligned YOLO boxes only. Aspect-ratio checks
approximate "upright" / "horizontal" orientation; they do not measure a true
physical rotation angle.
"""

import math
from typing import Optional

from config import (
    BOTTLE_IN_A_TIN_BOTTLE_UPRIGHT_ASPECT_RATIO,
    BOTTLE_IN_A_TIN_CONTACT_VERTICAL_TOLERANCE,
    BOTTLE_IN_A_TIN_HORIZONTAL_MARGIN_RATIO,
    BOTTLE_IN_A_TIN_MAX_PALM_DISTANCE,
    BOTTLE_IN_A_TIN_SHAKER_HORIZONTAL_ASPECT_RATIO,
)
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    track_bottle_stability,
    usable_hands_with_palms,
)
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks

_FRAME_W = 640
_FRAME_H = 480


def _dist(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _is_bottle_upright(bottle: BottleDetection) -> bool:
    width = max(1, bottle.x2 - bottle.x1)
    height = max(0, bottle.y2 - bottle.y1)
    return (height / width) >= BOTTLE_IN_A_TIN_BOTTLE_UPRIGHT_ASPECT_RATIO


def _is_shaker_horizontal(shaker: BottleDetection) -> bool:
    height = max(1, shaker.y2 - shaker.y1)
    width = max(0, shaker.x2 - shaker.x1)
    return (width / height) >= BOTTLE_IN_A_TIN_SHAKER_HORIZONTAL_ASPECT_RATIO


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
            locked_code=FeedbackCode.BOTTLE_IN_TIN_LOCKED.value,
        ),
    )


def evaluate(
    bottle: Optional[BottleDetection],
    shaker: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    # Pose is unused: this movement is evaluated from bottle/shaker/hand geometry.
    _ = pose

    # A. Visibility.
    if bottle is None and shaker is None:
        return (
            RuleResult(
                feedback="Keep the bottle and cocktail shaker visible.",
                feedback_type="error",
                posture_status="unknown",
                feedback_code=FeedbackCode.BOTH_PROPS_NOT_DETECTED.value,
            ),
            prev_hip_center,
            movement_state,
        )
    if bottle is None:
        return (
            RuleResult(
                feedback="Keep the bottle visible above the shaker.",
                feedback_type="error",
                posture_status="unknown",
                feedback_code=FeedbackCode.BOTTLE_NOT_DETECTED.value,
            ),
            prev_hip_center,
            movement_state,
        )
    if shaker is None:
        return (
            RuleResult(
                feedback="Keep the cocktail shaker visible under the bottle.",
                feedback_type="error",
                posture_status="unknown",
                feedback_code=FeedbackCode.SHAKER_NOT_DETECTED.value,
            ),
            prev_hip_center,
            movement_state,
        )

    # B–E. Independent technique, positioning, support, and stability checks.
    technique_fail = None
    if not _is_bottle_upright(bottle):
        technique_fail = FeedbackCode.PROP_NOT_UPRIGHT.value
    elif not _is_shaker_horizontal(shaker):
        technique_fail = FeedbackCode.SHAKER_NOT_HORIZONTAL.value

    bottle_base = bottle.bottom_center_normalized(_FRAME_W, _FRAME_H)
    shaker_x1 = shaker.x1 / _FRAME_W
    shaker_x2 = shaker.x2 / _FRAME_W
    shaker_top_y = shaker.y1 / _FRAME_H
    shaker_width = max(0.0, shaker_x2 - shaker_x1)
    margin = shaker_width * BOTTLE_IN_A_TIN_HORIZONTAL_MARGIN_RATIO
    usable_left = shaker_x1 + margin
    usable_right = shaker_x2 - margin

    positioning_fail = None
    if bottle_base.x < usable_left or bottle_base.x > usable_right:
        positioning_fail = FeedbackCode.BOTTLE_NOT_CENTERED_ON_SHAKER.value
    elif abs(bottle_base.y - shaker_top_y) > BOTTLE_IN_A_TIN_CONTACT_VERTICAL_TOLERANCE:
        positioning_fail = FeedbackCode.BOTTLE_NOT_ON_SHAKER.value

    usable = usable_hands_with_palms(hands)
    support_visible = True
    if not usable:
        support_visible = False
    else:
        shaker_center = shaker.center_normalized(_FRAME_W, _FRAME_H)
        shaker_bottom_y = shaker.y2 / _FRAME_H
        grip_target = Point2D(
            x=shaker_center.x,
            y=(shaker_center.y + shaker_bottom_y) / 2.0,
        )
        nearest_palm_dist = min(_dist(palm, grip_target) for _hand, palm in usable)
        if nearest_palm_dist > BOTTLE_IN_A_TIN_MAX_PALM_DISTANCE:
            support_visible = False

    current = dict(movement_state or {})
    bottle_sub, bottle_stable = track_bottle_stability(
        current.get("bottle"), bottle
    )
    shaker_sub, shaker_stable = track_bottle_stability(
        current.get("shaker"), shaker
    )
    current["bottle"] = bottle_sub
    current["shaker"] = shaker_sub
    stability_fail = (
        None
        if bottle_stable and shaker_stable
        else FeedbackCode.BOTH_PROPS_NOT_STEADY.value
    )

    if technique_fail == FeedbackCode.PROP_NOT_UPRIGHT.value:
        return (
            _credited(
                RuleResult(
                    feedback="Keep the bottle upright.",
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
    if technique_fail == FeedbackCode.SHAKER_NOT_HORIZONTAL.value:
        return (
            _credited(
                RuleResult(
                    feedback="Hold the cocktail shaker horizontally.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.SHAKER_NOT_HORIZONTAL.value,
                ),
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    if positioning_fail == FeedbackCode.BOTTLE_NOT_CENTERED_ON_SHAKER.value:
        return (
            _credited(
                RuleResult(
                    feedback="Center the bottle over the shaker.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.BOTTLE_NOT_CENTERED_ON_SHAKER.value,
                ),
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    if positioning_fail == FeedbackCode.BOTTLE_NOT_ON_SHAKER.value:
        return (
            _credited(
                RuleResult(
                    feedback="Place the bottle on top of the shaker.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.BOTTLE_NOT_ON_SHAKER.value,
                ),
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                stability_fail=stability_fail,
            ),
            prev_hip_center,
            current,
        )

    if not support_visible:
        # Visibility headline, but technique/positioning were already evaluable.
        return (
            _credited(
                RuleResult(
                    feedback="Keep one hand visible while supporting the shaker.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.HAND_NOT_SUPPORTING_SHAKER.value,
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
                    feedback="Hold the bottle and shaker steady.",
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
                feedback="Bottle in a tin locked in.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.BOTTLE_IN_TIN_LOCKED.value,
            )
        ),
        prev_hip_center,
        current,
    )
