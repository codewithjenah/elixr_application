import math
from typing import Optional

from config import (
    ONE_FINGER_STALL_BASE_TO_INDEX_TIP,
    ONE_FINGER_STALL_BELOW_FINGERTIP_REJECT,
    ONE_FINGER_STALL_INDEX_EXTENSION_RATIO,
    ONE_FINGER_STALL_MAX_HORIZONTAL_OFFSET,
    ONE_FINGER_STALL_MAX_OTHER_EXTENDED_FINGERS,
    ONE_FINGER_STALL_MIN_STRAIGHT_ANGLE_DEG,
    ONE_FINGER_STALL_OTHER_FINGER_EXTENSION_RATIO,
    ONE_FINGER_STALL_UPRIGHT_ASPECT_RATIO,
)
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import (
    check_bottle_visible,
    track_bottle_stability,
)
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
)

_REQUIRED_INDEX_LANDMARKS = (0, 5, 6, 7, 8)
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


def _index_support_point(hand: HandLandmarks) -> Optional[Point2D]:
    if any(index not in hand.points for index in _REQUIRED_INDEX_LANDMARKS):
        return None
    return hand.points[8]


def _usable_hands_with_index(
    hands: Optional[HandsResult],
) -> list[tuple[HandLandmarks, Point2D]]:
    if hands is None or not hands.hands:
        return []

    usable: list[tuple[HandLandmarks, Point2D]] = []
    for hand in hands.hands:
        index_tip = _index_support_point(hand)
        if index_tip is not None:
            usable.append((hand, index_tip))
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

    usable = _usable_hands_with_index(hands)
    if not usable:
        return (
            RuleResult(
                feedback="Keep your index finger fully visible.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    prop_base = bottle.bottom_center_normalized(640, 480)
    hand, index_tip = _nearest_usable_hand_to_prop_base(usable, prop_base)

    if not _index_is_extended_and_straight(hand):
        return (
            RuleResult(
                feedback="Extend one index finger straight.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if (
        _count_other_extended_fingers(hand)
        > ONE_FINGER_STALL_MAX_OTHER_EXTENDED_FINGERS
    ):
        return (
            RuleResult(
                feedback=(
                    "Curl your other fingers and keep only the index finger "
                    "extended."
                ),
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if not _is_upright(bottle):
        return (
            RuleResult(
                feedback=f"Keep the {prop_name_lower} upright on your index finger.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    # Image y increases downward: a prop bottom clearly below the fingertip
    # cannot be resting on the index finger.
    if prop_base.y > index_tip.y + ONE_FINGER_STALL_BELOW_FINGERTIP_REJECT:
        return (
            RuleResult(
                feedback=(
                    f"Place the {prop_name_lower} base on the tip of your "
                    "index finger."
                ),
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if abs(prop_base.x - index_tip.x) > ONE_FINGER_STALL_MAX_HORIZONTAL_OFFSET:
        return (
            RuleResult(
                feedback=(
                    f"Center the {prop_name_lower} over your index fingertip."
                ),
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if _dist(prop_base, index_tip) > ONE_FINGER_STALL_BASE_TO_INDEX_TIP:
        return (
            RuleResult(
                feedback=(
                    f"Place the {prop_name_lower} base on the tip of your "
                    "index finger."
                ),
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    # Geometry is valid — only then update stability history for this movement.
    state, stable = track_bottle_stability(movement_state, bottle)
    if not stable:
        return (
            RuleResult(
                feedback=f"Hold the {prop_name_lower} steady on one finger.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    return (
        RuleResult(
            feedback="One finger stall locked in.",
            feedback_type="positive",
            posture_status="stable",
        ),
        prev_hip_center,
        state,
    )
