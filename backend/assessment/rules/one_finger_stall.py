import math
from typing import Optional

from config import (
    FRAME_HEIGHT,
    FRAME_WIDTH,
    ONE_FINGER_STALL_BASE_TO_THENAR,
    ONE_FINGER_STALL_BELOW_THENAR_REJECT,
    ONE_FINGER_STALL_INDEX_EXTENSION_RATIO,
    ONE_FINGER_STALL_INDEX_HORIZONTAL_RATIO,
    ONE_FINGER_STALL_MAX_HORIZONTAL_OFFSET,
    ONE_FINGER_STALL_MAX_OTHER_EXTENDED_FINGERS,
    ONE_FINGER_STALL_MIN_STRAIGHT_ANGLE_DEG,
    ONE_FINGER_STALL_OTHER_FINGER_EXTENSION_RATIO,
    ONE_FINGER_STALL_UPRIGHT_ASPECT_RATIO,
)
from assessment.feedback_codes import FeedbackCode, evaluable_criterion_results
from assessment.rules.base import RuleResult, attach_criteria
from assessment.rules.common_checks import (
    check_bottle_visible,
    track_bottle_stability,
    uncertain_result,
)
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
)

_REQUIRED_INDEX_LANDMARKS = (0, 5, 6, 7, 8)
_THENAR_LANDMARKS = (1, 2, 5)
_OTHER_FINGER_LANDMARKS = ((9, 12), (13, 16), (17, 20))


def _dist(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _angle_degrees(first: Point2D, vertex: Point2D, last: Point2D) -> float:
    first_vector = (first.x - vertex.x, first.y - vertex.y)
    last_vector = (last.x - vertex.x, last.y - vertex.y)
    first_length = math.hypot(*first_vector)
    last_length = math.hypot(*last_vector)
    if first_length < 1e-6 or last_length < 1e-6:
        return 0.0

    cosine = (
        first_vector[0] * last_vector[0]
        + first_vector[1] * last_vector[1]
    ) / (first_length * last_length)
    cosine = max(-1.0, min(1.0, cosine))
    return math.degrees(math.acos(cosine))


def _is_upright(prop: BottleDetection) -> bool:
    width = max(1, prop.x2 - prop.x1)
    height = max(0, prop.y2 - prop.y1)
    return (height / width) >= ONE_FINGER_STALL_UPRIGHT_ASPECT_RATIO


def _index_is_horizontal(hand: HandLandmarks) -> bool:
    mcp = hand.points.get(5)
    tip = hand.points.get(8)
    if mcp is None or tip is None:
        return False
    horizontal = abs(tip.x - mcp.x) * FRAME_WIDTH
    vertical = abs(tip.y - mcp.y) * FRAME_HEIGHT
    return horizontal >= vertical * ONE_FINGER_STALL_INDEX_HORIZONTAL_RATIO


def _index_chain_point(hand: HandLandmarks) -> Optional[Point2D]:
    if any(index not in hand.points for index in _REQUIRED_INDEX_LANDMARKS):
        return None
    return hand.points[8]


def _thenar_support_point(hand: HandLandmarks) -> Optional[Point2D]:
    if any(index not in hand.points for index in _THENAR_LANDMARKS):
        return None
    thumb_cmc = hand.points[1]
    thumb_mcp = hand.points[2]
    index_mcp = hand.points[5]
    return Point2D(
        x=(thumb_cmc.x + thumb_mcp.x + index_mcp.x) / 3.0,
        y=(thumb_cmc.y + thumb_mcp.y + index_mcp.y) / 3.0,
    )


def _usable_hands_with_thenar(
    hands: Optional[HandsResult],
) -> list[tuple[HandLandmarks, Point2D]]:
    if hands is None or not hands.hands:
        return []

    usable: list[tuple[HandLandmarks, Point2D]] = []
    for hand in hands.hands:
        if _index_chain_point(hand) is None:
            continue
        thenar = _thenar_support_point(hand)
        if thenar is not None:
            usable.append((hand, thenar))
    return usable


def _nearest_usable_hand_to_prop_base(
    usable: list[tuple[HandLandmarks, Point2D]],
    prop_base: Point2D,
) -> tuple[HandLandmarks, Point2D]:
    return min(usable, key=lambda item: _dist(item[1], prop_base))


def _index_is_extended_and_straight(hand: HandLandmarks) -> bool:
    wrist = hand.points.get(0)
    mcp = hand.points.get(5)
    pip = hand.points.get(6)
    dip = hand.points.get(7)
    tip = hand.points.get(8)
    if wrist is None or mcp is None or pip is None or dip is None or tip is None:
        return False

    wrist_to_mcp = _dist(wrist, mcp)
    if wrist_to_mcp < 1e-6:
        return False
    if _dist(wrist, tip) < ONE_FINGER_STALL_INDEX_EXTENSION_RATIO * wrist_to_mcp:
        return False

    pip_angle = _angle_degrees(mcp, pip, dip)
    dip_angle = _angle_degrees(pip, dip, tip)
    return (
        pip_angle >= ONE_FINGER_STALL_MIN_STRAIGHT_ANGLE_DEG
        and dip_angle >= ONE_FINGER_STALL_MIN_STRAIGHT_ANGLE_DEG
    )


def _count_other_extended_fingers(hand: HandLandmarks) -> int:
    wrist = hand.points.get(0)
    if wrist is None:
        return 0

    extended = 0
    for mcp_index, tip_index in _OTHER_FINGER_LANDMARKS:
        mcp = hand.points.get(mcp_index)
        tip = hand.points.get(tip_index)
        if mcp is None or tip is None:
            continue
        wrist_to_mcp = _dist(wrist, mcp)
        if wrist_to_mcp < 1e-6:
            continue
        if _dist(wrist, tip) >= (
            ONE_FINGER_STALL_OTHER_FINGER_EXTENSION_RATIO * wrist_to_mcp
        ):
            extended += 1
    return extended


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
            locked_code=FeedbackCode.ONE_FINGER_STALL_LOCKED.value,
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
    # Pose is unused: One Finger Stall requires hand landmarks plus prop geometry.
    _ = pose
    prop_name = prop_label.strip() or "prop"
    prop_name_lower = prop_name.lower()

    bottle_check = check_bottle_visible(bottle, prop_label=prop_name)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    usable = _usable_hands_with_thenar(hands)
    if not usable:
        has_index = False
        if hands is not None:
            has_index = any(
                _index_chain_point(hand) is not None for hand in hands.hands
            )
        if has_index:
            return (
                uncertain_result(
                    "Keep the base of your thumb visible.",
                    code=FeedbackCode.THENAR_NOT_VISIBLE,
                ),
                prev_hip_center,
                movement_state,
            )
        return (
            uncertain_result(
                "Keep your index finger fully visible.",
                code=FeedbackCode.INDEX_FINGER_NOT_VISIBLE,
            ),
            prev_hip_center,
            movement_state,
        )

    prop_base = bottle.bottom_center_normalized(640, 480)
    hand, thenar = _nearest_usable_hand_to_prop_base(usable, prop_base)

    technique_fail = None
    if not _index_is_extended_and_straight(hand):
        technique_fail = FeedbackCode.INDEX_FINGER_NOT_EXTENDED.value
    elif (
        _count_other_extended_fingers(hand)
        > ONE_FINGER_STALL_MAX_OTHER_EXTENDED_FINGERS
    ):
        technique_fail = FeedbackCode.OTHER_FINGERS_NOT_CURLED.value
    elif not _index_is_horizontal(hand):
        technique_fail = FeedbackCode.INDEX_FINGER_NOT_HORIZONTAL.value
    elif not _is_upright(bottle):
        technique_fail = FeedbackCode.PROP_NOT_UPRIGHT.value

    positioning_fail = None
    if prop_base.y > thenar.y + ONE_FINGER_STALL_BELOW_THENAR_REJECT:
        positioning_fail = FeedbackCode.PROP_BASE_NOT_ON_THENAR.value
    elif abs(prop_base.x - thenar.x) > ONE_FINGER_STALL_MAX_HORIZONTAL_OFFSET:
        positioning_fail = FeedbackCode.PROP_NOT_CENTERED_ON_THENAR.value
    elif _dist(prop_base, thenar) > ONE_FINGER_STALL_BASE_TO_THENAR:
        positioning_fail = FeedbackCode.PROP_BASE_NOT_ON_THENAR.value

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

    if technique_fail == FeedbackCode.INDEX_FINGER_NOT_EXTENDED.value:
        return (
            _credited(
                RuleResult(
                    feedback="Extend one index finger straight.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.INDEX_FINGER_NOT_EXTENDED.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if technique_fail == FeedbackCode.OTHER_FINGERS_NOT_CURLED.value:
        return (
            _credited(
                RuleResult(
                    feedback=(
                        "Curl your other fingers and keep only the index finger "
                        "extended."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.OTHER_FINGERS_NOT_CURLED.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if technique_fail == FeedbackCode.INDEX_FINGER_NOT_HORIZONTAL.value:
        return (
            _credited(
                RuleResult(
                    feedback="Hold your index finger horizontally.",
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.INDEX_FINGER_NOT_HORIZONTAL.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if technique_fail == FeedbackCode.PROP_NOT_UPRIGHT.value:
        return (
            _credited(
                RuleResult(
                    feedback=(
                        f"Keep the {prop_name_lower} upright on the "
                        "thenar eminence."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_UPRIGHT.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_BASE_NOT_ON_THENAR.value and (
        prop_base.y > thenar.y + ONE_FINGER_STALL_BELOW_THENAR_REJECT
    ):
        return (
            _credited(
                RuleResult(
                    feedback=(
                        f"Place the {prop_name_lower} on the thenar eminence "
                        "(the pad at the base of your thumb)."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_BASE_NOT_ON_THENAR.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_NOT_CENTERED_ON_THENAR.value:
        return (
            _credited(
                RuleResult(
                    feedback=(
                        f"Center the {prop_name_lower} over the thenar eminence."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_NOT_CENTERED_ON_THENAR.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if positioning_fail == FeedbackCode.PROP_BASE_NOT_ON_THENAR.value:
        return (
            _credited(
                RuleResult(
                    feedback=(
                        f"Place the {prop_name_lower} on the thenar eminence "
                        "(the pad at the base of your thumb)."
                    ),
                    feedback_type="warning",
                    posture_status="unstable",
                    feedback_code=FeedbackCode.PROP_BASE_NOT_ON_THENAR.value,
                )
            ),
            prev_hip_center,
            state,
        )

    if stability_fail is not None:
        return (
            _credited(
                RuleResult(
                    feedback=f"Hold the {prop_name_lower} steady on the thenar eminence.",
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
                feedback="One finger stall locked in.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.ONE_FINGER_STALL_LOCKED.value,
            )
        ),
        prev_hip_center,
        state,
    )
