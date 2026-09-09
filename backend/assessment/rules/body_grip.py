import math
from typing import Optional

from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_hands_visible,
    uncertain_result,
)
from config import FRAME_HEIGHT, FRAME_WIDTH
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
)

_UPRIGHT_ASPECT_RATIO = 1.25
_NECK_BOTTOM_FRACTION = 0.42
_BODY_TOP_FRACTION = 0.45
_BODY_BOTTOM_FRACTION = 0.78
_BASE_TOP_FRACTION = 0.82
_HORIZONTAL_MARGIN_FRACTION = 0.85
_MIN_HORIZONTAL_MARGIN = 0.04
_REQUIRED_WRAP_FINGERTIPS = 3
_FINGERTIP_INDICES = (8, 12, 16, 20)
_OPEN_PALM_MIN_EXTENDED_UP = 3
_MIN_TIP_ABOVE_MCP = 0.008
_MAX_THUMB_INDEX_GAP_RATIO = 0.38
_MIN_SIDEWAYS_RATIO = 1.10
_MIN_INDEX_EXTENSION = 0.70
_INDEX_CHAIN = (5, 6, 7, 8)
_OVERHAND_RISE_RATIO = 0.20
_MIN_OVERHAND_RISE = 0.01
_UNDERHAND_DROP_RATIO = 0.20
_MIN_UNDERHAND_DROP = 0.01
_MIN_PINKY_THUMB_SEPARATION = 0.01
_PINKY_THUMB_SEPARATION_RATIO = 0.15
_NORMAL_REQUIRED_FINGERTIPS = 3

ContactZone = tuple[float, float, float, float]


def _pixel_distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(
        (a.x - b.x) * FRAME_WIDTH,
        (a.y - b.y) * FRAME_HEIGHT,
    )


def _normalized_distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _is_upright(bottle: BottleDetection) -> bool:
    width = bottle.x2 - bottle.x1
    height = bottle.y2 - bottle.y1
    if width <= 0:
        return False
    return (height / width) >= _UPRIGHT_ASPECT_RATIO


def _fraction_y(bottle: BottleDetection, fraction: float) -> float:
    height = (bottle.y2 - bottle.y1) / FRAME_HEIGHT
    return bottle.y1 / FRAME_HEIGHT + height * fraction


def _vertical_zone(bottle: BottleDetection, top_frac: float, bottom_frac: float) -> ContactZone:
    left = bottle.x1 / FRAME_WIDTH
    right = bottle.x2 / FRAME_WIDTH
    bottle_width = (bottle.x2 - bottle.x1) / FRAME_WIDTH
    horizontal_margin = max(
        _MIN_HORIZONTAL_MARGIN,
        bottle_width * _HORIZONTAL_MARGIN_FRACTION,
    )
    return (
        left - horizontal_margin,
        _fraction_y(bottle, top_frac),
        right + horizontal_margin,
        _fraction_y(bottle, bottom_frac),
    )


def _neck_zone(bottle: BottleDetection) -> ContactZone:
    return _vertical_zone(bottle, 0.0, _NECK_BOTTOM_FRACTION)


def _body_zone(bottle: BottleDetection) -> ContactZone:
    return _vertical_zone(bottle, _BODY_TOP_FRACTION, _BODY_BOTTOM_FRACTION)


def _base_zone(bottle: BottleDetection) -> ContactZone:
    return _vertical_zone(bottle, _BASE_TOP_FRACTION, 1.0)


def _is_in_zone(point: Optional[Point2D], zone: ContactZone) -> bool:
    if point is None:
        return False
    left, top, right, bottom = zone
    return left <= point.x <= right and top <= point.y <= bottom


def _hand_scale(hand: HandLandmarks) -> Optional[float]:
    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    if wrist is None or middle_mcp is None:
        return None
    return _pixel_distance(wrist, middle_mcp)


def _is_overhand(hand: HandLandmarks) -> Optional[bool]:
    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    if wrist is None or middle_mcp is None:
        return None
    required_rise = max(
        _MIN_OVERHAND_RISE,
        _normalized_distance(wrist, middle_mcp) * _OVERHAND_RISE_RATIO,
    )
    return wrist.y - middle_mcp.y >= required_rise


def _is_underhand(hand: HandLandmarks) -> Optional[bool]:
    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    if wrist is None or middle_mcp is None:
        return None
    required_drop = max(
        _MIN_UNDERHAND_DROP,
        _normalized_distance(wrist, middle_mcp) * _UNDERHAND_DROP_RATIO,
    )
    return middle_mcp.y - wrist.y >= required_drop


def _is_pinky_above_thumb(hand: HandLandmarks) -> Optional[bool]:
    thumb_tip = hand.points.get(4)
    pinky_tip = hand.points.get(20)
    if thumb_tip is None or pinky_tip is None:
        return None
    required_separation = max(
        _MIN_PINKY_THUMB_SEPARATION,
        _normalized_distance(thumb_tip, pinky_tip) * _PINKY_THUMB_SEPARATION_RATIO,
    )
    return pinky_tip.y + required_separation <= thumb_tip.y


def _index_extension(hand: HandLandmarks) -> Optional[float]:
    points = [hand.points.get(index) for index in _INDEX_CHAIN]
    if any(point is None for point in points):
        return None
    complete = [point for point in points if point is not None]
    path_length = sum(_pixel_distance(a, b) for a, b in zip(complete, complete[1:]))
    if path_length <= 0:
        return None
    return _pixel_distance(complete[0], complete[-1]) / path_length


def _fingers_extended_upward(hand: HandLandmarks, *, hand_scale: float) -> bool:
    margin = _MIN_TIP_ABOVE_MCP * hand_scale / FRAME_HEIGHT
    extended = 0
    for mcp_index, tip_index in ((5, 8), (9, 12), (13, 16), (17, 20)):
        mcp = hand.points.get(mcp_index)
        tip = hand.points.get(tip_index)
        if mcp is None or tip is None:
            continue
        if tip.y + margin <= mcp.y:
            extended += 1
    return extended >= _OPEN_PALM_MIN_EXTENDED_UP


def _engaged_fingertips(hand: HandLandmarks, zone: ContactZone) -> int:
    return sum(_is_in_zone(hand.points.get(index), zone) for index in _FINGERTIP_INDICES)


def _unexpanded_body_zone(bottle: BottleDetection) -> ContactZone:
    return (
        bottle.x1 / FRAME_WIDTH,
        _fraction_y(bottle, _BODY_TOP_FRACTION),
        bottle.x2 / FRAME_WIDTH,
        _fraction_y(bottle, _BODY_BOTTOM_FRACTION),
    )


def _wraps_around_body(hand: HandLandmarks, bottle: BottleDetection) -> bool:
    """Fingertips must reach the far side of the bottle, not hover on one face."""
    wrist = hand.points.get(0)
    if wrist is None:
        return False
    bottle_cx = ((bottle.x1 + bottle.x2) / 2.0) / FRAME_WIDTH
    wrist_left = wrist.x < bottle_cx
    opposite = 0
    for index in _FINGERTIP_INDICES:
        tip = hand.points.get(index)
        if tip is None:
            continue
        if wrist_left and tip.x > bottle_cx:
            opposite += 1
        elif (not wrist_left) and tip.x < bottle_cx:
            opposite += 1
    return opposite >= 2


def _chain_extension(hand: HandLandmarks, chain: tuple[int, ...]) -> Optional[float]:
    points = [hand.points.get(index) for index in chain]
    if any(point is None for point in points):
        return None
    complete = [point for point in points if point is not None]
    path_length = sum(_pixel_distance(a, b) for a, b in zip(complete, complete[1:]))
    if path_length <= 0:
        return None
    return _pixel_distance(complete[0], complete[-1]) / path_length


def _fingers_too_straight_for_wrap(hand: HandLandmarks) -> bool:
    """Reject a flat/open hand covering the body. Missing PIP chains are ignored."""
    straight = 0
    measured = 0
    for chain in ((5, 6, 7, 8), (9, 10, 11, 12), (13, 14, 15, 16), (17, 18, 19, 20)):
        extension = _chain_extension(hand, chain)
        if extension is None:
            continue
        measured += 1
        if extension >= 0.90:
            straight += 1
    if measured == 0:
        return False
    return straight >= 3


def _looks_like_normal_neck(
    hand: HandLandmarks,
    neck_zone: ContactZone,
    palm: Point2D,
) -> bool:
    overhand = _is_overhand(hand)
    if overhand is None or not overhand:
        return False
    if not _is_in_zone(palm, neck_zone):
        return False
    return _engaged_fingertips(hand, neck_zone) >= _NORMAL_REQUIRED_FINGERTIPS


def _looks_like_reverse_neck(hand: HandLandmarks, neck_zone: ContactZone) -> bool:
    underhand = _is_underhand(hand)
    if underhand is None or not underhand:
        return False
    pinky_above_thumb = _is_pinky_above_thumb(hand)
    if pinky_above_thumb is None or not pinky_above_thumb:
        return False
    return _engaged_fingertips(hand, neck_zone) >= _NORMAL_REQUIRED_FINGERTIPS


def _looks_like_bartender_pinch(hand: HandLandmarks, hand_scale: float) -> bool:
    wrist = hand.points.get(0)
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    middle_mcp = hand.points.get(9)
    if wrist is None or thumb is None or index is None or middle_mcp is None:
        return False
    if _pixel_distance(thumb, index) > hand_scale * _MAX_THUMB_INDEX_GAP_RATIO:
        return False
    horizontal = abs(middle_mcp.x - wrist.x) * FRAME_WIDTH
    vertical = abs(middle_mcp.y - wrist.y) * FRAME_HEIGHT
    if horizontal < vertical * _MIN_SIDEWAYS_RATIO:
        return False
    index_extension = _index_extension(hand)
    if index_extension is None or index_extension < _MIN_INDEX_EXTENSION:
        return False
    return True


def _looks_like_claw_from_above(hand: HandLandmarks, bottle: BottleDetection) -> bool:
    wrist = hand.points.get(0)
    if wrist is None:
        return False
    bottle_top = bottle.y1 / FRAME_HEIGHT
    return wrist.y < bottle_top


def _nearest_hand(
    hands: HandsResult, bottle: BottleDetection
) -> tuple[Optional[HandLandmarks], Optional[Point2D]]:
    bottle_center = bottle.center_normalized(FRAME_WIDTH, FRAME_HEIGHT)
    best_hand: Optional[HandLandmarks] = None
    best_palm: Optional[Point2D] = None
    best_dist = float("inf")
    for hand in hands.hands:
        palm = hand.palm_center()
        if palm is None:
            continue
        dist = _normalized_distance(palm, bottle_center)
        if dist < best_dist:
            best_dist = dist
            best_hand = hand
            best_palm = palm
    return best_hand, best_palm


def _warning(
    feedback: str,
    feedback_code: str,
    *,
    technique_fail: str | None = None,
    positioning_fail: str | None = None,
) -> RuleResult:
    result = RuleResult(
        feedback=feedback,
        feedback_type="warning",
        posture_status="unstable",
        feedback_code=feedback_code,
    )
    return attach_criteria(
        result,
        evaluable_criterion_results(
            technique_fail=technique_fail,
            positioning_fail=positioning_fail,
            locked_code=FeedbackCode.BODY_GRIP_LOCKED.value,
        ),
    )


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    _ = pose
    bottle_check = check_bottle_visible(bottle)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    hands_check = check_hands_visible(hands)
    if hands_check:
        return hands_check, prev_hip_center, movement_state

    assert bottle is not None
    assert hands is not None

    hand, palm = _nearest_hand(hands, bottle)
    if hand is None or palm is None:
        return (
            uncertain_result(
                "Keep your full hand visible around the bottle body.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    thumb = hand.points.get(4)
    if wrist is None or middle_mcp is None or thumb is None:
        return (
            uncertain_result(
                "Keep your full hand visible around the bottle body.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    hand_scale = _hand_scale(hand)
    if hand_scale is None or hand_scale <= 0:
        return (
            uncertain_result(
                "Keep your full hand visible around the bottle body.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    if sum(hand.points.get(index) is not None for index in _FINGERTIP_INDICES) < (
        _REQUIRED_WRAP_FINGERTIPS
    ):
        return (
            uncertain_result(
                "Keep your full hand visible around the bottle body.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    neck_zone = _neck_zone(bottle)
    body_zone = _body_zone(bottle)
    base_zone = _base_zone(bottle)
    wrap_count = _engaged_fingertips(hand, body_zone)

    if not _is_upright(bottle):
        return (
            _warning(
                "Hold the bottle upright for a body grip.",
                FeedbackCode.PROP_NOT_UPRIGHT.value,
                technique_fail=FeedbackCode.PROP_NOT_UPRIGHT.value,
            ),
            prev_hip_center,
            movement_state,
        )

    if _looks_like_claw_from_above(hand, bottle):
        return (
            _warning(
                "Wrap your hand around the bottle body, not a top-down claw on the neck.",
                FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
                technique_fail=FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
            ),
            prev_hip_center,
            movement_state,
        )

    if _looks_like_bartender_pinch(hand, hand_scale):
        return (
            _warning(
                "Wrap your hand around the bottle body; do not pinch the neck.",
                FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
                technique_fail=FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
            ),
            prev_hip_center,
            movement_state,
        )

    if _looks_like_reverse_neck(hand, neck_zone):
        return (
            _warning(
                "Wrap your hand around the bottle body, not a reverse neck grip.",
                FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
                technique_fail=FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
            ),
            prev_hip_center,
            movement_state,
        )

    if _looks_like_normal_neck(hand, neck_zone, palm):
        return (
            _warning(
                "Wrap your hand around the bottle body, not the upper neck.",
                FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
                technique_fail=FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
            ),
            prev_hip_center,
            movement_state,
        )

    if _engaged_fingertips(hand, neck_zone) >= _REQUIRED_WRAP_FINGERTIPS:
        return (
            _warning(
                "Wrap your hand around the bottle body, not the upper neck.",
                FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
                technique_fail=FeedbackCode.BODY_GRIP_NOT_NECK_GRIP.value,
            ),
            prev_hip_center,
            movement_state,
        )

    if _is_in_zone(palm, neck_zone) or _is_in_zone(palm, base_zone):
        return (
            _warning(
                "Place your hand around the middle of the bottle body.",
                FeedbackCode.HAND_NOT_AT_BODY.value,
                positioning_fail=FeedbackCode.HAND_NOT_AT_BODY.value,
            ),
            prev_hip_center,
            movement_state,
        )

    if not _is_in_zone(palm, body_zone):
        return (
            _warning(
                "Place your hand around the middle of the bottle body.",
                FeedbackCode.HAND_NOT_AT_BODY.value,
                positioning_fail=FeedbackCode.HAND_NOT_AT_BODY.value,
            ),
            prev_hip_center,
            movement_state,
        )

    if _fingers_extended_upward(hand, hand_scale=hand_scale) or wrap_count < (
        _REQUIRED_WRAP_FINGERTIPS
    ):
        return (
            _warning(
                "Wrap your fingers around the bottle body; proximity alone is not a grip.",
                FeedbackCode.INSUFFICIENT_BODY_FINGER_WRAP.value,
                technique_fail=FeedbackCode.INSUFFICIENT_BODY_FINGER_WRAP.value,
            ),
            prev_hip_center,
            movement_state,
        )

    if (
        _engaged_fingertips(hand, _unexpanded_body_zone(bottle)) < 2
        or not _wraps_around_body(hand, bottle)
        or _fingers_too_straight_for_wrap(hand)
        or not _is_in_zone(thumb, body_zone)
    ):
        return (
            _warning(
                "Wrap your fingers around the bottle body; proximity alone is not a grip.",
                FeedbackCode.INSUFFICIENT_BODY_FINGER_WRAP.value,
                technique_fail=FeedbackCode.INSUFFICIENT_BODY_FINGER_WRAP.value,
            ),
            prev_hip_center,
            movement_state,
        )

    return (
        attach_criteria(
            RuleResult(
                feedback="Good body grip around the bottle.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.BODY_GRIP_LOCKED.value,
            ),
            evaluable_criterion_results(
                locked_code=FeedbackCode.BODY_GRIP_LOCKED.value,
            ),
        ),
        prev_hip_center,
        movement_state,
    )
