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
_NECK_ANCHOR_FRACTION = 0.22
_UPPER_NECK_BOTTOM_FRACTION = 0.42
_NECK_ZONE_TOP_MARGIN_FRACTION = 0.05
_NECK_ZONE_HORIZONTAL_MARGIN_FRACTION = 0.75
_MIN_TOP_MARGIN = 0.02
_MIN_HORIZONTAL_MARGIN = 0.04

_MIN_WRIST_ABOVE_NECK = 0.01
_WRIST_ABOVE_NECK_RATIO = 0.12
_BODY_GRIP_FRACTION = 0.55

_OVERHAND_RISE_RATIO = 0.20
_MIN_OVERHAND_RISE = 0.01
_UNDERHAND_DROP_RATIO = 0.20
_MIN_UNDERHAND_DROP = 0.01
_MIN_PINKY_THUMB_SEPARATION = 0.01
_PINKY_THUMB_SEPARATION_RATIO = 0.15

_MIN_SIDEWAYS_RATIO = 1.10
_MAX_THUMB_INDEX_GAP_RATIO = 0.38
_MIN_INDEX_EXTENSION = 0.70
_INDEX_CHAIN = (5, 6, 7, 8)

_MIN_CURLED_FINGERS = 2
_REQUIRED_CURLED_CONTACTING = 3
_FINGER_CHAINS = (
    (5, 6, 7, 8),
    (9, 10, 11, 12),
    (13, 14, 15, 16),
    (17, 18, 19, 20),
)
_FINGERTIP_INDICES = (8, 12, 16, 20)
_MIN_CURL_TIP_BELOW_PIP = 0.006
_MIN_CURL_TIP_BELOW_MCP = 0.010

_OPEN_PALM_MIN_EXTENDED_UP = 3
_MIN_TIP_ABOVE_MCP = 0.008
_NORMAL_REQUIRED_FINGERTIPS = 3

ContactZone = tuple[float, float, float, float]


def _pixel_distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(
        (a.x - b.x) * FRAME_WIDTH,
        (a.y - b.y) * FRAME_HEIGHT,
    )


def _normalized_distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _upper_neck_anchor(bottle: BottleDetection) -> Point2D:
    bottle_height = bottle.y2 - bottle.y1
    return Point2D(
        x=((bottle.x1 + bottle.x2) / 2.0) / FRAME_WIDTH,
        y=(
            bottle.y1 + bottle_height * _NECK_ANCHOR_FRACTION
        ) / FRAME_HEIGHT,
    )


def _upper_neck_contact_zone(bottle: BottleDetection) -> ContactZone:
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
    bottom = top + bottle_height * _UPPER_NECK_BOTTOM_FRACTION

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


def _is_upright(bottle: BottleDetection) -> bool:
    width = bottle.x2 - bottle.x1
    height = bottle.y2 - bottle.y1
    if width <= 0:
        return False
    return (height / width) >= _UPRIGHT_ASPECT_RATIO


def _nearest_hand_to_anchor(
    hands: HandsResult,
    anchor: Point2D,
    contact_zone: ContactZone,
) -> tuple[Optional[HandLandmarks], Optional[Point2D]]:
    nearest_in_zone: Optional[HandLandmarks] = None
    nearest_in_zone_palm: Optional[Point2D] = None
    nearest_in_zone_distance = float("inf")
    nearest_overall: Optional[HandLandmarks] = None
    nearest_overall_palm: Optional[Point2D] = None
    nearest_overall_distance = float("inf")

    for hand in hands.hands:
        palm = hand.palm_center()
        if palm is None:
            continue
        distance = _normalized_distance(palm, anchor)
        if distance < nearest_overall_distance:
            nearest_overall = hand
            nearest_overall_palm = palm
            nearest_overall_distance = distance
        if (
            _is_in_zone(palm, contact_zone)
            and distance < nearest_in_zone_distance
        ):
            nearest_in_zone = hand
            nearest_in_zone_palm = palm
            nearest_in_zone_distance = distance

    if nearest_in_zone is not None:
        return nearest_in_zone, nearest_in_zone_palm
    return nearest_overall, nearest_overall_palm


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
    path_length = sum(
        _pixel_distance(a, b)
        for a, b in zip(complete, complete[1:])
    )
    if path_length <= 0:
        return None
    return _pixel_distance(complete[0], complete[-1]) / path_length


def _observable_fingertip_count(hand: HandLandmarks) -> int:
    return sum(
        1 for index in _FINGERTIP_INDICES if hand.points.get(index) is not None
    )


def _finger_curled_down(
    hand: HandLandmarks,
    chain: tuple[int, int, int, int],
    *,
    hand_scale: float,
) -> bool:
    mcp = hand.points.get(chain[0])
    pip = hand.points.get(chain[1])
    dip = hand.points.get(chain[2])
    tip = hand.points.get(chain[3])
    if mcp is None or pip is None or dip is None or tip is None:
        return False

    tip_below_pip = tip.y >= pip.y + (
        _MIN_CURL_TIP_BELOW_PIP * hand_scale / FRAME_HEIGHT
    )
    tip_below_mcp = tip.y >= mcp.y + (
        _MIN_CURL_TIP_BELOW_MCP * hand_scale / FRAME_HEIGHT
    )
    if not tip_below_pip or not tip_below_mcp:
        return False

    return True


def _fingers_extended_upward(
    hand: HandLandmarks,
    *,
    hand_scale: float,
) -> bool:
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


def _curled_contacting_fingers(
    hand: HandLandmarks,
    zone: ContactZone,
    *,
    hand_scale: float,
) -> int:
    count = 0
    for chain in _FINGER_CHAINS:
        tip = hand.points.get(chain[3])
        curled = _finger_curled_down(hand, chain, hand_scale=hand_scale)
        contacting = tip is not None and _is_in_zone(tip, zone)
        if curled and contacting:
            count += 1
    return count


def _engaged_fingertips(hand: HandLandmarks, zone: ContactZone) -> int:
    return sum(
        _is_in_zone(hand.points.get(index), zone)
        for index in _FINGERTIP_INDICES
    )


def _looks_like_normal_overhand(
    hand: HandLandmarks,
    zone: ContactZone,
    palm: Point2D,
) -> bool:
    overhand = _is_overhand(hand)
    if overhand is None or not overhand:
        return False
    if not _is_in_zone(palm, zone):
        return False
    return _engaged_fingertips(hand, zone) >= _NORMAL_REQUIRED_FINGERTIPS


def _looks_like_reverse_grip(
    hand: HandLandmarks,
    zone: ContactZone,
) -> bool:
    underhand = _is_underhand(hand)
    if underhand is None or not underhand:
        return False
    pinky_above_thumb = _is_pinky_above_thumb(hand)
    if pinky_above_thumb is None or not pinky_above_thumb:
        return False
    return _engaged_fingertips(hand, zone) >= _NORMAL_REQUIRED_FINGERTIPS


def _looks_like_bartenders_grip(hand: HandLandmarks, hand_scale: float) -> bool:
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


def _warning(
    feedback: str,
    posture_status: str,
    feedback_code: str,
    *,
    technique_fail: str | None = None,
    positioning_fail: str | None = None,
) -> RuleResult:
    result = RuleResult(
        feedback=feedback,
        feedback_type="warning",
        posture_status=posture_status,
        feedback_code=feedback_code,
    )
    if technique_fail is None and positioning_fail is None:
        return result
    return attach_criteria(
        result,
        evaluable_criterion_results(
            technique_fail=technique_fail,
            positioning_fail=positioning_fail,
            locked_code=FeedbackCode.CLAW_GRIP_LOCKED.value,
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

    hands_check = check_hands_visible(hands)
    if hands_check:
        return hands_check, prev_hip_center, movement_state

    assert bottle is not None
    assert hands is not None

    contact_zone = _upper_neck_contact_zone(bottle)
    neck_anchor = _upper_neck_anchor(bottle)
    hand, palm = _nearest_hand_to_anchor(hands, neck_anchor, contact_zone)
    if hand is None or palm is None:
        return (
            uncertain_result(
                "Keep your full hand visible above the bottle neck.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    if wrist is None or middle_mcp is None or thumb is None or index is None:
        return (
            uncertain_result(
                "Keep your full hand visible above the bottle neck.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    hand_scale = _hand_scale(hand)
    if hand_scale is None or hand_scale <= 0:
        return (
            uncertain_result(
                "Keep your full hand visible above the bottle neck.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    if _observable_fingertip_count(hand) < _REQUIRED_CURLED_CONTACTING:
        return (
            uncertain_result(
                "Keep your full hand visible above the bottle neck.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    zone_top = contact_zone[1]
    bottle_height = (bottle.y2 - bottle.y1) / FRAME_HEIGHT
    body_grip_y = (
        bottle.y1 / FRAME_HEIGHT + bottle_height * _BODY_GRIP_FRACTION
    )
    required_wrist_above = max(
        _MIN_WRIST_ABOVE_NECK,
        _normalized_distance(wrist, neck_anchor) * _WRIST_ABOVE_NECK_RATIO,
    )

    technique_fail = None
    if not _is_upright(bottle):
        technique_fail = FeedbackCode.PROP_NOT_UPRIGHT.value
    elif _fingers_extended_upward(hand, hand_scale=hand_scale):
        technique_fail = FeedbackCode.CLAW_FINGERS_NOT_CURLED.value
    elif _looks_like_bartenders_grip(hand, hand_scale):
        technique_fail = FeedbackCode.CLAW_NOT_PINCH_GRIP.value
    elif _looks_like_normal_overhand(hand, contact_zone, palm):
        technique_fail = FeedbackCode.CLAW_NOT_SIDE_OVERHAND.value
    elif _looks_like_reverse_grip(hand, contact_zone):
        technique_fail = FeedbackCode.CLAW_NOT_REVERSE_HOLD.value
    elif not _is_in_zone(thumb, contact_zone):
        technique_fail = FeedbackCode.CLAW_THUMB_SUPPORT.value
    else:
        curled_contacting = _curled_contacting_fingers(
            hand,
            contact_zone,
            hand_scale=hand_scale,
        )
        if curled_contacting < _MIN_CURLED_FINGERS:
            technique_fail = FeedbackCode.CLAW_FINGERS_NOT_CURLED.value
        elif curled_contacting < _REQUIRED_CURLED_CONTACTING:
            technique_fail = FeedbackCode.CLAW_MORE_FINGERS_CURLED.value

    positioning_fail = None
    if wrist.y > neck_anchor.y - required_wrist_above:
        positioning_fail = FeedbackCode.CLAW_WRIST_ABOVE_NECK.value
    elif palm.y > body_grip_y:
        positioning_fail = FeedbackCode.CLAW_REACH_FROM_ABOVE.value
    elif palm.y >= zone_top:
        positioning_fail = FeedbackCode.CLAW_PALM_OVER_MOUTH.value

    if technique_fail == FeedbackCode.PROP_NOT_UPRIGHT.value:
        return (
            _warning(
                "Hold the bottle upright for a claw grip.",
                "unstable",
                FeedbackCode.PROP_NOT_UPRIGHT.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if positioning_fail == FeedbackCode.CLAW_WRIST_ABOVE_NECK.value:
        return (
            _warning(
                "Place your wrist above the bottle mouth and upper neck.",
                "unstable",
                FeedbackCode.CLAW_WRIST_ABOVE_NECK.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if positioning_fail == FeedbackCode.CLAW_REACH_FROM_ABOVE.value:
        return (
            _warning(
                "Reach down from above onto the upper neck, "
                "not the bottle body.",
                "unstable",
                FeedbackCode.CLAW_REACH_FROM_ABOVE.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.CLAW_FINGERS_NOT_CURLED.value and (
        _fingers_extended_upward(hand, hand_scale=hand_scale)
    ):
        return (
            _warning(
                "Curl your fingers downward around the upper neck.",
                "unstable",
                FeedbackCode.CLAW_FINGERS_NOT_CURLED.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.CLAW_NOT_PINCH_GRIP.value:
        return (
            _warning(
                "Curl multiple fingers around the neck; "
                "do not pinch with thumb and index.",
                "unstable",
                FeedbackCode.CLAW_NOT_PINCH_GRIP.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.CLAW_NOT_SIDE_OVERHAND.value:
        return (
            _warning(
                "Use a top-down claw grip, not a side overhand wrap.",
                "unstable",
                FeedbackCode.CLAW_NOT_SIDE_OVERHAND.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.CLAW_NOT_REVERSE_HOLD.value:
        return (
            _warning(
                "Use a top-down claw grip, not a reverse underhand hold.",
                "unstable",
                FeedbackCode.CLAW_NOT_REVERSE_HOLD.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if positioning_fail == FeedbackCode.CLAW_PALM_OVER_MOUTH.value:
        return (
            _warning(
                "Reach down from above with your palm over the bottle mouth.",
                "unstable",
                FeedbackCode.CLAW_PALM_OVER_MOUTH.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.CLAW_THUMB_SUPPORT.value:
        return (
            _warning(
                "Support the opposite side of the neck with your thumb.",
                "unstable",
                FeedbackCode.CLAW_THUMB_SUPPORT.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.CLAW_FINGERS_NOT_CURLED.value:
        return (
            _warning(
                "Curl at least two fingers downward around the upper neck.",
                "unstable",
                FeedbackCode.CLAW_FINGERS_NOT_CURLED.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.CLAW_MORE_FINGERS_CURLED.value:
        return (
            _warning(
                "Curl more fingers around the bottle mouth and upper neck.",
                "unstable",
                FeedbackCode.CLAW_MORE_FINGERS_CURLED.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    return (
        attach_criteria(
            RuleResult(
                feedback="Good claw grip curled over the upper neck.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.CLAW_GRIP_LOCKED.value,
            ),
            evaluable_criterion_results(
                locked_code=FeedbackCode.CLAW_GRIP_LOCKED.value,
            ),
        ),
        prev_hip_center,
        movement_state,
    )
