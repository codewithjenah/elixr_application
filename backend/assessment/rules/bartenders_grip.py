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
from vision.grip_geometry import (
    BARTENDER_CONTACT_BOTTOM_FRACTION,
    BARTENDER_WRAP_BOTTOM_FRACTION,
    ContactZone,
    bartender_contact_zone,
    bartender_control_anchor,
    bartender_control_point,
    point_in_zone,
)
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
)

_MAX_CONTROL_GAP_RATIO = 0.45
_MIN_SIDEWAYS_RATIO = 1.10
_MIN_INDEX_EXTENSION = 0.55
_INDEX_CHAIN = (5, 6, 7, 8)
_OTHER_FINGERTIPS = (12, 16, 20)
_REQUIRED_OTHER_FINGERTIPS = 2


def _pixel_distance(a: Point2D, b: Point2D) -> float:
    return math.hypot(
        (a.x - b.x) * FRAME_WIDTH,
        (a.y - b.y) * FRAME_HEIGHT,
    )

def _nearest_hand_to_control_anchor(
    hands: HandsResult,
    anchor: Point2D,
    contact_zone: ContactZone,
) -> Optional[HandLandmarks]:
    nearest_in_zone: Optional[HandLandmarks] = None
    nearest_in_zone_distance = float("inf")
    nearest_overall: Optional[HandLandmarks] = None
    nearest_overall_distance = float("inf")

    for hand in hands.hands:
        control = bartender_control_point(hand)
        if control is None:
            continue
        distance = _pixel_distance(control, anchor)
        if distance < nearest_overall_distance:
            nearest_overall = hand
            nearest_overall_distance = distance
        if (
            point_in_zone(control, contact_zone)
            and distance < nearest_in_zone_distance
        ):
            nearest_in_zone = hand
            nearest_in_zone_distance = distance

    return nearest_in_zone if nearest_in_zone is not None else nearest_overall


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
            locked_code=FeedbackCode.BARTENDER_GRIP_LOCKED.value,
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

    contact_zone = bartender_contact_zone(
        bottle,
        frame_width=FRAME_WIDTH,
        frame_height=FRAME_HEIGHT,
        bottom_fraction=BARTENDER_CONTACT_BOTTOM_FRACTION,
    )
    hand = _nearest_hand_to_control_anchor(
        hands,
        bartender_control_anchor(
            bottle,
            frame_width=FRAME_WIDTH,
            frame_height=FRAME_HEIGHT,
        ),
        contact_zone,
    )
    if hand is None:
        return (
            uncertain_result(
                "Keep your full gripping hand visible.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    wrist = hand.points.get(0)
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    middle_mcp = hand.points.get(9)
    index_extension = _index_extension(hand)
    other_tips = [
        hand.points.get(index)
        for index in _OTHER_FINGERTIPS
    ]

    if (
        wrist is None
        or thumb is None
        or index is None
        or middle_mcp is None
        or index_extension is None
        or sum(point is not None for point in other_tips)
        < _REQUIRED_OTHER_FINGERTIPS
    ):
        return (
            uncertain_result(
                "Keep your full gripping hand visible.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    hand_scale = _pixel_distance(wrist, middle_mcp)
    if hand_scale <= 0:
        return (
            uncertain_result(
                "Keep your full gripping hand visible.",
                code=FeedbackCode.HAND_NOT_FULLY_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    control = bartender_control_point(hand)
    assert control is not None

    positioning_fail = None
    if not point_in_zone(control, contact_zone):
        positioning_fail = FeedbackCode.BARTENDER_GRIP_POSITION.value
    else:
        palm = hand.palm_center()
        assert palm is not None
        bottle_center = bottle.center_normalized(FRAME_WIDTH, FRAME_HEIGHT)
        if palm.y > bottle_center.y:
            positioning_fail = FeedbackCode.BARTENDER_PALM_TOO_LOW.value

    technique_fail = None
    if _pixel_distance(thumb, index) > (hand_scale * _MAX_CONTROL_GAP_RATIO):
        technique_fail = FeedbackCode.BARTENDER_PINCH_REQUIRED.value
    else:
        horizontal = abs(middle_mcp.x - wrist.x) * FRAME_WIDTH
        vertical = abs(middle_mcp.y - wrist.y) * FRAME_HEIGHT
        if horizontal < vertical * _MIN_SIDEWAYS_RATIO:
            technique_fail = FeedbackCode.BARTENDER_HAND_ORIENTATION.value
        elif index_extension < _MIN_INDEX_EXTENSION:
            technique_fail = FeedbackCode.BARTENDER_INDEX_EXTENSION.value
        else:
            wrap_zone = bartender_contact_zone(
                bottle,
                frame_width=FRAME_WIDTH,
                frame_height=FRAME_HEIGHT,
                bottom_fraction=BARTENDER_WRAP_BOTTOM_FRACTION,
            )
            wrapped_fingers = sum(
                point_in_zone(point, wrap_zone)
                for point in other_tips
            )
            if wrapped_fingers < _REQUIRED_OTHER_FINGERTIPS:
                technique_fail = FeedbackCode.BARTENDER_WRAP_FINGERS.value

    if positioning_fail == FeedbackCode.BARTENDER_GRIP_POSITION.value:
        return (
            _warning(
                "Grip the bottle at the upper neck and shoulder.",
                "unstable",
                FeedbackCode.BARTENDER_GRIP_POSITION.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.BARTENDER_PINCH_REQUIRED.value:
        return (
            _warning(
                "Secure the neck between your thumb and index finger.",
                "unstable",
                FeedbackCode.BARTENDER_PINCH_REQUIRED.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.BARTENDER_HAND_ORIENTATION.value:
        return (
            _warning(
                "Turn your hand sideways for a bartender's grip.",
                "unstable",
                FeedbackCode.BARTENDER_HAND_ORIENTATION.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if positioning_fail == FeedbackCode.BARTENDER_PALM_TOO_LOW.value:
        return (
            _warning(
                (
                    "Raise your palm above the bottle center for "
                    "a bartender's grip."
                ),
                "unstable",
                FeedbackCode.BARTENDER_PALM_TOO_LOW.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.BARTENDER_INDEX_EXTENSION.value:
        return (
            _warning(
                "Extend your index finger along the bottle neck.",
                "unstable",
                FeedbackCode.BARTENDER_INDEX_EXTENSION.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    if technique_fail == FeedbackCode.BARTENDER_WRAP_FINGERS.value:
        return (
            _warning(
                "Wrap your other fingers around the bottle shoulder.",
                "unstable",
                FeedbackCode.BARTENDER_WRAP_FINGERS.value,
                technique_fail=technique_fail,
                positioning_fail=positioning_fail,
            ),
            prev_hip_center,
            movement_state,
        )

    return (
        attach_criteria(
            RuleResult(
                feedback="Good bartender's grip on the neck and shoulder.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.BARTENDER_GRIP_LOCKED.value,
            ),
            evaluable_criterion_results(
                locked_code=FeedbackCode.BARTENDER_GRIP_LOCKED.value,
            ),
        ),
        prev_hip_center,
        movement_state,
    )
