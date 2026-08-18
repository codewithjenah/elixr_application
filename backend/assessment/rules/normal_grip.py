import math
from dataclasses import dataclass
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

_NECK_ANCHOR_FRACTION = 0.25
_NECK_ZONE_BOTTOM_FRACTION = 0.50
_NECK_ZONE_TOP_MARGIN_FRACTION = 0.05
_NECK_ZONE_HORIZONTAL_MARGIN_FRACTION = 0.75
_MIN_TOP_MARGIN = 0.02
_MIN_HORIZONTAL_MARGIN = 0.04
_MIN_OVERHAND_RISE = 0.01
_OVERHAND_RISE_RATIO = 0.20
_MIN_UPRIGHT_RATIO = 1.00
_MIN_THUMB_PINKY_SEPARATION = 0.01
_THUMB_PINKY_SEPARATION_RATIO = 0.15
_FINGER_MCP_AND_TIP = ((5, 8), (9, 12), (13, 16), (17, 20))
_REQUIRED_FINGERTIPS = 3
_NORMAL_GRIP_FINGER_CHAINS = (
    (5, 6, 7, 8),
    (9, 10, 11, 12),
    (13, 14, 15, 16),
    (17, 18, 19, 20),
)
_NORMAL_GRIP_MIN_OBSERVABLE_FINGERS = 3
_NORMAL_GRIP_MIN_ENGAGED_FINGERS = 3
_NORMAL_GRIP_PALM_NECK_BOTTLE_WIDTH_RATIO = 1.20
_NORMAL_GRIP_PALM_NECK_HAND_SCALE_RATIO = 1.25
_NORMAL_GRIP_MIN_FINGER_CURL = 0.08
_NORMAL_GRIP_MIN_FINGER_ARC_RATIO = 0.18
_NORMAL_GRIP_ARC_CURL_COMPACTNESS_RATIO = 0.45
_NORMAL_GRIP_ENVELOPE_NECK_PADDING_RATIO = 0.30
_NORMAL_GRIP_ENVELOPE_HAND_SCALE_PADDING_RATIO = 0.15

ContactZone = tuple[float, float, float, float]


@dataclass(frozen=True)
class NormalGripContactSignals:
    observable: bool
    palm_near_neck: bool
    engaged_finger_count: int
    grip_envelope_contact: bool
    final_contact_gate: bool


def _distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _pixel_distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(
        (a.x - b.x) * FRAME_WIDTH,
        (a.y - b.y) * FRAME_HEIGHT,
    )


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
    if wrist.y - middle_mcp.y < required_rise:
        return False

    horizontal = abs(middle_mcp.x - wrist.x) * FRAME_WIDTH
    vertical = abs(middle_mcp.y - wrist.y) * FRAME_HEIGHT
    return vertical >= horizontal * _MIN_UPRIGHT_RATIO


def _is_thumb_toward_mouth(hand: HandLandmarks) -> Optional[bool]:
    thumb_tip = hand.points.get(4)
    pinky_tip = hand.points.get(20)
    if thumb_tip is None or pinky_tip is None:
        return None

    required_separation = max(
        _MIN_THUMB_PINKY_SEPARATION,
        _distance(thumb_tip, pinky_tip) * _THUMB_PINKY_SEPARATION_RATIO,
    )
    return thumb_tip.y + required_separation <= pinky_tip.y


def _is_top_down_clutch(
    wrist: Optional[Point2D],
    palm: Point2D,
    bottle: BottleDetection,
) -> bool:
    if wrist is None:
        return False
    bottle_top = bottle.y1 / FRAME_HEIGHT
    return wrist.y < bottle_top or palm.y < bottle_top


def _finger_wraps_neck(
    hand: HandLandmarks,
    mcp_index: int,
    tip_index: int,
    zone: ContactZone,
    anchor: Point2D,
) -> bool:
    tip = hand.points.get(tip_index)
    if not _is_in_zone(tip, zone):
        return False
    mcp = hand.points.get(mcp_index)
    if mcp is None or tip is None:
        return True
    toward_bottle = (tip.x - mcp.x) * (anchor.x - mcp.x) + (
        tip.y - mcp.y
    ) * (anchor.y - mcp.y)
    return toward_bottle > 0


def _wrapped_finger_count(
    hand: HandLandmarks,
    zone: ContactZone,
    anchor: Point2D,
) -> int:
    return sum(
        _finger_wraps_neck(hand, mcp_index, tip_index, zone, anchor)
        for mcp_index, tip_index in _FINGER_MCP_AND_TIP
    )


def _hand_scale_px(hand: HandLandmarks) -> Optional[float]:
    wrist = hand.points.get(0)
    middle_mcp = hand.points.get(9)
    if wrist is None or middle_mcp is None:
        return None
    scale = _pixel_distance(wrist, middle_mcp)
    if scale <= 1e-6:
        return None
    return scale


def _finger_chain_points(
    hand: HandLandmarks,
    chain: tuple[int, int, int, int],
) -> list[Point2D]:
    return [
        point
        for index in chain
        if (point := hand.points.get(index)) is not None
    ]


def _finger_compactness(
    hand: HandLandmarks,
    chain: tuple[int, int, int, int],
) -> Optional[float]:
    mcp = hand.points.get(chain[0])
    tip = hand.points.get(chain[3])
    if mcp is None or tip is None:
        return None
    points = _finger_chain_points(hand, chain)
    if len(points) < 3:
        return 0.0
    path = sum(
        _pixel_distance(start, end)
        for start, end in zip(points, points[1:])
    )
    if path <= 1e-6:
        return 0.0
    return 1.0 - (_pixel_distance(points[0], points[-1]) / path)


def _finger_arc_ratio(
    hand: HandLandmarks,
    chain: tuple[int, int, int, int],
) -> float:
    mcp = hand.points.get(chain[0])
    pip = hand.points.get(chain[1])
    tip = hand.points.get(chain[3])
    if mcp is None or pip is None or tip is None:
        return 0.0
    chord = _pixel_distance(mcp, tip)
    if chord <= 1e-6:
        return 0.0
    return _point_to_segment_px(pip, mcp, tip) / chord


def _finger_is_engaged(
    hand: HandLandmarks,
    chain: tuple[int, int, int, int],
) -> Optional[bool]:
    compactness = _finger_compactness(hand, chain)
    if compactness is None:
        return None
    if compactness >= _NORMAL_GRIP_MIN_FINGER_CURL:
        return True
    arc_ratio = _finger_arc_ratio(hand, chain)
    return (
        compactness >= (
            _NORMAL_GRIP_MIN_FINGER_CURL * _NORMAL_GRIP_ARC_CURL_COMPACTNESS_RATIO
        )
        and arc_ratio >= _NORMAL_GRIP_MIN_FINGER_ARC_RATIO
    )


def _convex_hull(points: list[Point2D]) -> list[Point2D]:
    unique: list[Point2D] = []
    seen: set[tuple[float, float]] = set()
    for point in points:
        key = (round(point.x, 6), round(point.y, 6))
        if key in seen:
            continue
        seen.add(key)
        unique.append(point)
    if len(unique) <= 2:
        return unique

    ordered = sorted(unique, key=lambda point: (point.x, point.y))

    def cross(origin: Point2D, a: Point2D, b: Point2D) -> float:
        return (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (
            b.x - origin.x
        )

    lower: list[Point2D] = []
    for point in ordered:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], point) <= 0:
            lower.pop()
        lower.append(point)

    upper: list[Point2D] = []
    for point in reversed(ordered):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], point) <= 0:
            upper.pop()
        upper.append(point)

    return lower[:-1] + upper[:-1]


def _point_in_polygon(point: Point2D, polygon: list[Point2D]) -> bool:
    if len(polygon) < 3:
        return False
    inside = False
    previous = polygon[-1]
    for current in polygon:
        intersects = (current.y > point.y) != (previous.y > point.y)
        if intersects:
            span = previous.y - current.y
            if abs(span) > 1e-12:
                x_at_y = (
                    (previous.x - current.x) * (point.y - current.y) / span
                    + current.x
                )
                if point.x < x_at_y:
                    inside = not inside
        previous = current
    return inside


def _point_to_segment_px(point: Point2D, start: Point2D, end: Point2D) -> float:
    dx = (end.x - start.x) * FRAME_WIDTH
    dy = (end.y - start.y) * FRAME_HEIGHT
    length_sq = dx * dx + dy * dy
    if length_sq <= 1e-12:
        return _pixel_distance(point, start)
    px = (point.x - start.x) * FRAME_WIDTH
    py = (point.y - start.y) * FRAME_HEIGHT
    projection = max(0.0, min(1.0, (px * dx + py * dy) / length_sq))
    closest = Point2D(
        x=start.x + (end.x - start.x) * projection,
        y=start.y + (end.y - start.y) * projection,
    )
    return _pixel_distance(point, closest)


def _polygon_distance_px(point: Point2D, polygon: list[Point2D]) -> float:
    if not polygon:
        return float("inf")
    if len(polygon) == 1:
        return _pixel_distance(point, polygon[0])
    if len(polygon) == 2:
        return _point_to_segment_px(point, polygon[0], polygon[1])
    if _point_in_polygon(point, polygon):
        return 0.0
    return min(
        _point_to_segment_px(point, start, end)
        for start, end in zip(polygon, polygon[1:] + polygon[:1])
    )


def inspect_contact_geometry(
    hand: HandLandmarks,
    bottle: BottleDetection,
    palm: Optional[Point2D] = None,
) -> NormalGripContactSignals:
    """Test-visible Normal Grip contact sub-signals. Not a live log."""
    if palm is None:
        palm = hand.palm_center()
    scale = _hand_scale_px(hand)
    wrist = hand.points.get(0)
    if palm is None or scale is None or wrist is None:
        return NormalGripContactSignals(
            observable=False,
            palm_near_neck=False,
            engaged_finger_count=0,
            grip_envelope_contact=False,
            final_contact_gate=False,
        )

    observable_fingers = 0
    engaged_chains: list[tuple[int, int, int, int]] = []
    for chain in _NORMAL_GRIP_FINGER_CHAINS:
        engaged = _finger_is_engaged(hand, chain)
        if engaged is None:
            continue
        observable_fingers += 1
        if engaged:
            engaged_chains.append(chain)

    if observable_fingers < _NORMAL_GRIP_MIN_OBSERVABLE_FINGERS:
        return NormalGripContactSignals(
            observable=False,
            palm_near_neck=False,
            engaged_finger_count=0,
            grip_envelope_contact=False,
            final_contact_gate=False,
        )

    anchor = _neck_anchor(bottle)
    bottle_width_px = max(1.0, float(bottle.x2 - bottle.x1))
    proximity_limit = max(
        bottle_width_px * _NORMAL_GRIP_PALM_NECK_BOTTLE_WIDTH_RATIO,
        scale * _NORMAL_GRIP_PALM_NECK_HAND_SCALE_RATIO,
    )
    palm_near_neck = _pixel_distance(palm, anchor) <= proximity_limit
    engaged_finger_count = len(engaged_chains)

    envelope_points = [palm, wrist]
    for mcp_index in (5, 9, 13, 17):
        mcp = hand.points.get(mcp_index)
        if mcp is not None:
            envelope_points.append(mcp)
    thumb = hand.points.get(4)
    if thumb is not None:
        envelope_points.append(thumb)
    for chain in engaged_chains:
        envelope_points.extend(_finger_chain_points(hand, chain))

    hull = _convex_hull(envelope_points)
    padding = max(
        bottle_width_px * _NORMAL_GRIP_ENVELOPE_NECK_PADDING_RATIO,
        scale * _NORMAL_GRIP_ENVELOPE_HAND_SCALE_PADDING_RATIO,
    )
    grip_envelope_contact = _polygon_distance_px(anchor, hull) <= padding
    final_contact_gate = (
        palm_near_neck
        and engaged_finger_count >= _NORMAL_GRIP_MIN_ENGAGED_FINGERS
        and grip_envelope_contact
    )
    return NormalGripContactSignals(
        observable=True,
        palm_near_neck=palm_near_neck,
        engaged_finger_count=engaged_finger_count,
        grip_envelope_contact=grip_envelope_contact,
        final_contact_gate=final_contact_gate,
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

    hand, palm = _nearest_hand_to_anchor(hands, _neck_anchor(bottle))
    if hand is None or palm is None:
        return (
            uncertain_result(
                "Keep your full hand visible around the bottle neck.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    contact_zone = _neck_contact_zone(bottle)
    wrist = hand.points.get(0)
    positioning_fail = None
    if not _is_in_zone(palm, contact_zone):
        positioning_fail = FeedbackCode.HAND_NOT_AT_NECK.value
    elif _is_top_down_clutch(wrist, palm, bottle):
        positioning_fail = FeedbackCode.NORMAL_NOT_TOP_DOWN.value

    overhand = _is_overhand(hand)
    if overhand is None:
        return (
            uncertain_result(
                "Keep your full hand visible around the bottle neck.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    thumb_toward_mouth = _is_thumb_toward_mouth(hand)

    technique_fail = None
    contact_signals: Optional[NormalGripContactSignals] = None
    if not overhand:
        technique_fail = FeedbackCode.OVERHAND_GRIP_REQUIRED.value
    elif thumb_toward_mouth is False:
        technique_fail = FeedbackCode.NORMAL_THUMB_PINKY_ORIENTATION.value
    elif thumb_toward_mouth is True:
        engaged_fingertips = _wrapped_finger_count(
            hand,
            contact_zone,
            _neck_anchor(bottle),
        )
        if engaged_fingertips < _REQUIRED_FINGERTIPS:
            technique_fail = FeedbackCode.INSUFFICIENT_NECK_FINGER_WRAP.value
        else:
            contact_signals = inspect_contact_geometry(hand, bottle, palm)
            if contact_signals.observable and not contact_signals.final_contact_gate:
                technique_fail = FeedbackCode.NORMAL_GRIP_NOT_SECURE.value

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

    if positioning_fail == FeedbackCode.NORMAL_NOT_TOP_DOWN.value:
        return (
            _credited(
                RuleResult(
                    feedback="Grip the neck from the side, not from above.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.NORMAL_NOT_TOP_DOWN.value,
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

    if thumb_toward_mouth is None:
        return (
            uncertain_result(
                "Keep your full hand visible around the bottle neck.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.NORMAL_THUMB_PINKY_ORIENTATION.value:
        return (
            _credited(
                RuleResult(
                    feedback=(
                        "Point your thumb toward the bottle mouth "
                        "and pinky toward the base."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.NORMAL_THUMB_PINKY_ORIENTATION.value,
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

    if contact_signals is not None and not contact_signals.observable:
        return (
            uncertain_result(
                "Keep your full hand visible around the bottle neck.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.NORMAL_GRIP_NOT_SECURE.value:
        return (
            _credited(
                RuleResult(
                    feedback="Wrap your hand securely around the bottle neck.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.NORMAL_GRIP_NOT_SECURE.value,
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
