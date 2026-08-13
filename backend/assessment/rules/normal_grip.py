import math
from typing import Optional

from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_hands_visible,
)
from config import FRAME_HEIGHT, FRAME_WIDTH
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
)

_NECK_ANCHOR_FRACTION = 0.25
_NECK_ZONE_BOTTOM_FRACTION = 0.50
_NECK_ZONE_TOP_MARGIN_FRACTION = 0.05
_NECK_ZONE_HORIZONTAL_MARGIN_FRACTION = 0.75
_MIN_TOP_MARGIN = 0.02
_MIN_HORIZONTAL_MARGIN = 0.04
_MIN_OVERHAND_RISE = 0.01
_OVERHAND_RISE_RATIO = 0.20
_FINGERTIP_INDICES = (8, 12, 16, 20)
_REQUIRED_FINGERTIPS = 3

ContactZone = tuple[float, float, float, float]


def _distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _neck_anchor(bottle: BottleDetection) -> Point2D:
    bottle_height = bottle.y2 - bottle.y1
    return Point2D(
        x=((bottle.x1 + bottle.x2) / 2.0) / FRAME_WIDTH,
        y=(
            bottle.y1 + bottle_height * _NECK_ANCHOR_FRACTION
        ) / FRAME_HEIGHT,
    )


def _neck_contact_zone(bottle: BottleDetection) -> ContactZone:
    left = bottle.x1 / FRAME_WIDTH
    top = bottle.y1 / FRAME_HEIGHT
    right = bottle.x2 / FRAME_WIDTH
    bottle_width = (bottle.x2 - bottle.x1) / FRAME_WIDTH
    bottle_height = (bottle.y2 - bottle.y1) / FRAME_HEIGHT

    horizontal_margin = max(
        _MIN_HORIZONTAL_MARGIN,
        bottle_width * _NECK_ZONE_HORIZONTAL_MARGIN_FRACTION,
    )
    top_margin = max(
        _MIN_TOP_MARGIN,
        bottle_height * _NECK_ZONE_TOP_MARGIN_FRACTION,
    )
    bottom = top + bottle_height * _NECK_ZONE_BOTTOM_FRACTION

    return (
        left - horizontal_margin,
        top - top_margin,
        right + horizontal_margin,
        bottom,
    )


def _is_in_zone(
    point: Optional[Point2D],
    zone: ContactZone,
) -> bool:
    if point is None:
        return False
    left, top, right, bottom = zone
    return left <= point.x <= right and top <= point.y <= bottom


def _nearest_hand_to_anchor(
    hands: HandsResult,
    anchor: Point2D,
) -> tuple[Optional[HandLandmarks], Optional[Point2D]]:
    nearest_hand: Optional[HandLandmarks] = None
    nearest_palm: Optional[Point2D] = None
    nearest_distance = float("inf")

    for hand in hands.hands:
        palm = hand.palm_center()
        if palm is None:
            continue
        distance = _distance(palm, anchor)
        if distance < nearest_distance:
            nearest_hand = hand
            nearest_palm = palm
            nearest_distance = distance

    return nearest_hand, nearest_palm


def _is_overhand(hand: HandLandmarks) -> Optional[bool]:
    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    if wrist is None or middle_mcp is None:
        return None

    required_rise = max(
        _MIN_OVERHAND_RISE,
        _distance(wrist, middle_mcp) * _OVERHAND_RISE_RATIO,
    )
    return wrist.y - middle_mcp.y >= required_rise


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

    hands_check = check_hands_visible(hands)
    if hands_check:
        return hands_check, prev_hip_center, movement_state

    assert bottle is not None
    assert hands is not None

    hand, palm = _nearest_hand_to_anchor(hands, _neck_anchor(bottle))
    if hand is None or palm is None:
        return (
            RuleResult(
                feedback="Keep your full hand visible around the bottle neck.",
                feedback_type="warning",
                posture_status="unknown",
                feedback_code=FeedbackCode.HAND_NOT_FULLY_VISIBLE.value,
            ),
            prev_hip_center,
            movement_state,
        )

    contact_zone = _neck_contact_zone(bottle)
    positioning_fail = None
    if not _is_in_zone(palm, contact_zone):
        positioning_fail = FeedbackCode.HAND_NOT_AT_NECK.value

    overhand = _is_overhand(hand)
    if overhand is None:
        return (
            RuleResult(
                feedback="Keep your full hand visible around the bottle neck.",
                feedback_type="warning",
                posture_status="unknown",
                feedback_code=FeedbackCode.HAND_NOT_FULLY_VISIBLE.value,
            ),
            prev_hip_center,
            movement_state,
        )

    technique_fail = None
    if not overhand:
        technique_fail = FeedbackCode.OVERHAND_GRIP_REQUIRED.value
    else:
        engaged_fingertips = sum(
            _is_in_zone(hand.points.get(index), contact_zone)
            for index in _FINGERTIP_INDICES
        )
        if engaged_fingertips < _REQUIRED_FINGERTIPS:
            technique_fail = FeedbackCode.INSUFFICIENT_NECK_FINGER_WRAP.value

    def _credited(result: RuleResult) -> RuleResult:
        return attach_criteria(
            result,
            evaluable_criterion_results(
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
                locked_code=FeedbackCode.NORMAL_GRIP_LOCKED.value,
            ),
        )

    if positioning_fail == FeedbackCode.HAND_NOT_AT_NECK.value:
        return (
            _credited(
                RuleResult(
                    feedback="Move your hand to the upper bottle neck.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.HAND_NOT_AT_NECK.value,
                )
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.OVERHAND_GRIP_REQUIRED.value:
        return (
            _credited(
                RuleResult(
                    feedback="Rotate your wrist into an overhand grip.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.OVERHAND_GRIP_REQUIRED.value,
                )
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.INSUFFICIENT_NECK_FINGER_WRAP.value:
        return (
            _credited(
                RuleResult(
                    feedback=(
                        "Wrap at least three fingers around the bottle neck."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.INSUFFICIENT_NECK_FINGER_WRAP.value,
                )
            ),
            prev_hip_center,
            movement_state,
        )

    return (
        _credited(
            RuleResult(
                feedback=(
                    "Bottle held securely with a full overhand neck grip."
                ),
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.NORMAL_GRIP_LOCKED.value,
            )
        ),
        prev_hip_center,
        movement_state,
    )
