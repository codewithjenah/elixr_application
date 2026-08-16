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

_NECK_TERMINAL_BAND_FRACTION = 0.35
_NECK_ZONE_END_MARGIN_FRACTION = 0.50
_NECK_ZONE_HORIZONTAL_MARGIN_FRACTION = 0.75
_MIN_TOP_MARGIN = 0.02
_MIN_HORIZONTAL_MARGIN = 0.04
_MIN_HAND_SCALE = 0.01
# An axis-aligned detector box is a coarse proxy for a strongly tilted bottle.
# Reject only a clearly opposing wrist direction; hand-local pinky/thumb
# geometry provides the stricter reverse-grip orientation check below.
_MIN_REVERSE_ORIENTATION_ALIGNMENT = -0.65
_PINKY_THUMB_INWARD_RATIO = 0.12
_FINGERTIP_INDICES = (8, 12, 16, 20)
_REQUIRED_FINGERTIPS = 3

ContactZone = tuple[float, float, float, float]


def _distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _terminal_anchors(bottle: BottleDetection) -> tuple[Point2D, Point2D]:
    center_x = ((bottle.x1 + bottle.x2) / 2.0) / FRAME_WIDTH
    return Point2D(
        x=center_x,
        y=bottle.y1 / FRAME_HEIGHT,
    ), Point2D(
        x=center_x,
        y=bottle.y2 / FRAME_HEIGHT,
    )


def _neck_contact_zone(
    bottle: BottleDetection,
    terminal: Point2D,
) -> ContactZone:
    left = bottle.x1 / FRAME_WIDTH
    top = bottle.y1 / FRAME_HEIGHT
    right = bottle.x2 / FRAME_WIDTH
    bottle_width = (bottle.x2 - bottle.x1) / FRAME_WIDTH
    bottle_height = (bottle.y2 - bottle.y1) / FRAME_HEIGHT

    horizontal_margin = max(
        _MIN_HORIZONTAL_MARGIN,
        bottle_width * _NECK_ZONE_HORIZONTAL_MARGIN_FRACTION,
    )
    end_margin = max(
        _MIN_TOP_MARGIN,
        bottle_height * _NECK_ZONE_END_MARGIN_FRACTION,
    )
    terminal_band = bottle_height * _NECK_TERMINAL_BAND_FRACTION
    is_top_terminal = terminal.y <= (top + bottle_height / 2.0)

    if is_top_terminal:
        zone_top = top - end_margin
        zone_bottom = top + terminal_band
    else:
        zone_top = top + bottle_height - terminal_band
        zone_bottom = top + bottle_height + end_margin

    return (
        left - horizontal_margin,
        zone_top,
        right + horizontal_margin,
        zone_bottom,
    )


def _is_in_zone(
    point: Optional[Point2D],
    zone: ContactZone,
) -> bool:
    if point is None:
        return False
    left, top, right, bottom = zone
    return left <= point.x <= right and top <= point.y <= bottom


def _nearest_hand_to_terminal(
    hands: HandsResult,
    terminals: tuple[Point2D, Point2D],
) -> tuple[Optional[HandLandmarks], Optional[Point2D], Optional[Point2D]]:
    nearest_hand: Optional[HandLandmarks] = None
    nearest_palm: Optional[Point2D] = None
    nearest_terminal: Optional[Point2D] = None
    nearest_distance = float("inf")

    for hand in hands.hands:
        palm = hand.palm_center()
        if palm is None:
            continue
        for terminal in terminals:
            distance = _distance(palm, terminal)
            if distance < nearest_distance:
                nearest_hand = hand
                nearest_palm = palm
                nearest_terminal = terminal
                nearest_distance = distance

    return nearest_hand, nearest_palm, nearest_terminal


def _direction(a: Point2D, b: Point2D) -> tuple[float, float, float]:
    dx = b.x - a.x
    dy = b.y - a.y
    return dx, dy, math.hypot(dx, dy)


def _is_underhand(
    hand: HandLandmarks,
    terminal: Point2D,
    palm: Point2D,
) -> Optional[bool]:
    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    if wrist is None or middle_mcp is None:
        return None

    hand_dx, hand_dy, hand_scale = _direction(wrist, middle_mcp)
    grip_dx, grip_dy, grip_scale = _direction(terminal, palm)
    if hand_scale < _MIN_HAND_SCALE or grip_scale < _MIN_HAND_SCALE:
        return None

    alignment = (hand_dx * grip_dx + hand_dy * grip_dy) / (
        hand_scale * grip_scale
    )
    return alignment >= _MIN_REVERSE_ORIENTATION_ALIGNMENT


def _is_pinky_toward_terminal(
    hand: HandLandmarks,
) -> Optional[bool]:
    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    thumb_tip = hand.points.get(4)
    pinky_tip = hand.points.get(20)
    if (
        wrist is None
        or middle_mcp is None
        or thumb_tip is None
        or pinky_tip is None
    ):
        return None

    hand_dx, hand_dy, hand_scale = _direction(wrist, middle_mcp)
    if hand_scale < _MIN_HAND_SCALE:
        return None

    pinky_to_thumb_dx, pinky_to_thumb_dy, _ = _direction(pinky_tip, thumb_tip)
    inward_projection = (
        pinky_to_thumb_dx * hand_dx + pinky_to_thumb_dy * hand_dy
    ) / hand_scale
    return inward_projection >= hand_scale * _PINKY_THUMB_INWARD_RATIO


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

    hand, palm, terminal = _nearest_hand_to_terminal(
        hands,
        _terminal_anchors(bottle),
    )
    if hand is None or palm is None or terminal is None:
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

    contact_zone = _neck_contact_zone(bottle, terminal)
    positioning_fail = None
    if not _is_in_zone(palm, contact_zone):
        positioning_fail = FeedbackCode.HAND_NOT_AT_NECK.value

    underhand = _is_underhand(hand, terminal, palm)
    if underhand is None:
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

    pinky_toward_terminal = _is_pinky_toward_terminal(hand)
    if pinky_toward_terminal is None:
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
    if not underhand:
        technique_fail = FeedbackCode.UNDERHAND_GRIP_REQUIRED.value
    elif not pinky_toward_terminal:
        technique_fail = FeedbackCode.REVERSE_PINKY_THUMB_ORIENTATION.value
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
                locked_code=FeedbackCode.REVERSE_GRIP_LOCKED.value,
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

    if technique_fail == FeedbackCode.UNDERHAND_GRIP_REQUIRED.value:
        return (
            _credited(
                RuleResult(
                    feedback="Rotate your wrist into a reverse grip.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.UNDERHAND_GRIP_REQUIRED.value,
                )
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.REVERSE_PINKY_THUMB_ORIENTATION.value:
        return (
            _credited(
                RuleResult(
                    feedback=(
                        "Point your pinky toward the bottle mouth "
                        "and thumb toward the base."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.REVERSE_PINKY_THUMB_ORIENTATION.value,
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
                    "Bottle held securely with a full reverse neck grip."
                ),
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.REVERSE_GRIP_LOCKED.value,
            )
        ),
        prev_hip_center,
        movement_state,
    )
