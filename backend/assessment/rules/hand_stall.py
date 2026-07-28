from typing import Optional

from config import (
    HAND_STALL_BASE_TO_PALM,
    HAND_STALL_BELOW_PALM_REJECT,
    HAND_STALL_MAX_HORIZONTAL_OFFSET,
    HAND_STALL_MIN_EXTENDED_FINGERS,
    HAND_STALL_OPEN_PALM_EXTENSION_RATIO,
    HAND_STALL_UPRIGHT_ASPECT_RATIO,
)
from assessment.rules.base import RuleResult
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


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    # Pose is unused: Hand Stall requires MediaPipe Hands + bottle geometry.
    _ = pose

    bottle_check = check_bottle_visible(bottle)
    if bottle_check:
        return bottle_check, prev_hip_center, movement_state

    usable = usable_hands_with_palms(hands)
    if not usable:
        return (
            RuleResult(
                feedback="Keep your hand fully visible.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            movement_state,
        )

    bottle_base = bottle.bottom_center_normalized(640, 480)
    hand, palm = _nearest_hand_to_bottle_base(usable, bottle_base)

    if not is_open_palm(
        hand,
        extension_ratio=HAND_STALL_OPEN_PALM_EXTENSION_RATIO,
        min_extended=HAND_STALL_MIN_EXTENDED_FINGERS,
    ):
        return (
            RuleResult(
                feedback="Open your palm and extend your fingers.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if not _is_upright(bottle):
        return (
            RuleResult(
                feedback="Keep the bottle upright on your palm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    # Image y increases downward: bottom clearly below the palm is not a stall.
    if bottle_base.y > palm.y + HAND_STALL_BELOW_PALM_REJECT:
        return (
            RuleResult(
                feedback="Place the bottle base directly on your open palm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if abs(bottle_base.x - palm.x) > HAND_STALL_MAX_HORIZONTAL_OFFSET:
        return (
            RuleResult(
                feedback="Move the bottle directly above your palm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            movement_state,
        )

    if _dist(bottle_base, palm) > HAND_STALL_BASE_TO_PALM:
        return (
            RuleResult(
                feedback="Place the bottle base directly on your open palm.",
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
                feedback="Hold the bottle steady on your open palm.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            state,
        )

    return (
        RuleResult(
            feedback="Hand stall locked in.",
            feedback_type="positive",
            posture_status="stable",
        ),
        prev_hip_center,
        state,
    )
