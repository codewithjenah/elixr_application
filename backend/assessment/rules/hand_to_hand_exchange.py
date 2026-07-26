from typing import Optional

from config import (
    EXCHANGE_AIRBORNE_FRAMES,
    EXCHANGE_CATCH_HOLD_FRAMES,
    EXCHANGE_HOLD_PROXIMITY,
    EXCHANGE_MIN_TRAVEL,
    EXCHANGE_TIMEOUT_FRAMES,
)
from assessment.rules.base import RuleResult
from assessment.rules.common_checks import check_bottle_visible
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D, PoseLandmarks

_PHASE_WAITING = "waiting_for_start"
_PHASE_RELEASED = "released"
_PHASE_CATCHING = "catching"
_PHASE_CONFIRMED = "confirmed"


def _dist(a: Point2D, b: Point2D) -> float:
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


def _hand_id(hand: HandLandmarks, palm: Point2D, peers: list[tuple[str, Point2D]]) -> str:
    """Stable-enough hand identity without relying only on list order."""
    label = (hand.handedness or "Unknown").strip().lower()
    if label in ("left", "right"):
        return label
    if len(peers) >= 2:
        ordered = sorted(peers, key=lambda item: item[1].x)
        if abs(palm.x - ordered[0][1].x) <= abs(palm.x - ordered[-1][1].x):
            return "image_left"
        return "image_right"
    return f"x:{palm.x:.3f}"


def _visible_palms(
    hands: Optional[HandsResult],
) -> list[tuple[str, Point2D]]:
    if hands is None or not hands.hands:
        return []
    raw: list[tuple[HandLandmarks, Point2D]] = []
    for hand in hands.hands:
        palm = hand.palm_center()
        if palm is None:
            continue
        raw.append((hand, palm))
    if not raw:
        return []

    peer_points = [("tmp", palm) for _, palm in raw]
    labeled = [
        (_hand_id(hand, palm, peer_points), palm) for hand, palm in raw
    ]

    # Force spatial distinction when Unknown handedness collapses identities.
    unique_ids = {hand_id for hand_id, _ in labeled}
    if len(unique_ids) < 2 and len(labeled) >= 2:
        ordered = sorted(labeled, key=lambda item: item[1].x)
        return [
            ("image_left", ordered[0][1]),
            ("image_right", ordered[-1][1]),
        ]
    return labeled


def _reset_state(extra: Optional[dict] = None) -> dict:
    state = {
        "phase": _PHASE_WAITING,
        "start_hand": None,
        "start_palm": None,
        "catch_hand": None,
        "airborne_frames": 0,
        "catch_frames": 0,
        "sequence_frames": 0,
    }
    if extra:
        state.update(extra)
    return state


def _near(
    bottle_center: Point2D,
    palm: Point2D,
    threshold: float = EXCHANGE_HOLD_PROXIMITY,
) -> bool:
    return _dist(bottle_center, palm) <= threshold


def evaluate(
    bottle: Optional[BottleDetection],
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    prev_hip_center: Optional[Point2D],
    movement_state: Optional[dict] = None,
) -> tuple[RuleResult, Optional[Point2D], Optional[dict]]:
    bottle_check = check_bottle_visible(bottle)
    if bottle_check:
        return bottle_check, prev_hip_center, _reset_state()

    palms = _visible_palms(hands)
    if len(palms) < 2:
        return (
            RuleResult(
                feedback="Keep both hands visible for a hand-to-hand exchange.",
                feedback_type="warning",
                posture_status="unknown",
            ),
            prev_hip_center,
            _reset_state(),
        )

    bottle_center = bottle.center_normalized(640, 480)
    state = dict(movement_state or _reset_state())
    phase = str(state.get("phase", _PHASE_WAITING))
    sequence_frames = int(state.get("sequence_frames", 0)) + 1
    state["sequence_frames"] = sequence_frames

    if phase != _PHASE_WAITING and sequence_frames > EXCHANGE_TIMEOUT_FRAMES:
        return (
            RuleResult(
                feedback="Exchange timed out. Hold the bottle in one hand to restart.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            _reset_state(),
        )

    near_hands = [
        (hand_id, palm) for hand_id, palm in palms if _near(bottle_center, palm)
    ]
    far_from_all = len(near_hands) == 0

    if phase == _PHASE_WAITING:
        start_hand = state.get("start_hand")

        # Already armed with a start hand: wait for a clean release.
        if start_hand is not None:
            still_on_start = any(
                hand_id == start_hand and _near(bottle_center, palm)
                for hand_id, palm in palms
            )
            if still_on_start:
                return (
                    RuleResult(
                        feedback="Ready. Release the bottle toward your other hand.",
                        feedback_type="positive",
                        posture_status="stable",
                    ),
                    prev_hip_center,
                    state,
                )
            if far_from_all:
                state["phase"] = _PHASE_RELEASED
                state["airborne_frames"] = 1
                return (
                    RuleResult(
                        feedback="Bottle released. Keep it airborne toward the other hand.",
                        feedback_type="positive",
                        posture_status="stable",
                    ),
                    prev_hip_center,
                    state,
                )
            return (
                RuleResult(
                    feedback="Release the bottle fully before catching with the other hand.",
                    feedback_type="warning",
                    posture_status="unstable",
                ),
                prev_hip_center,
                _reset_state(),
            )

        if len(near_hands) == 1:
            hand_id, palm = near_hands[0]
            state = _reset_state(
                {
                    "phase": _PHASE_WAITING,
                    "start_hand": hand_id,
                    "start_palm": (palm.x, palm.y),
                    "sequence_frames": sequence_frames,
                }
            )
            return (
                RuleResult(
                    feedback="Ready. Release the bottle toward your other hand.",
                    feedback_type="positive",
                    posture_status="stable",
                ),
                prev_hip_center,
                state,
            )
        if len(near_hands) > 1:
            return (
                RuleResult(
                    feedback="Hold the bottle in one hand before exchanging.",
                    feedback_type="warning",
                    posture_status="unstable",
                ),
                prev_hip_center,
                _reset_state({"sequence_frames": sequence_frames}),
            )
        return (
            RuleResult(
                feedback="Hold the bottle near one palm to start the exchange.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            _reset_state({"sequence_frames": sequence_frames}),
        )

    start_hand = state.get("start_hand")
    start_palm_raw = state.get("start_palm")
    if start_hand is None or start_palm_raw is None:
        return (
            RuleResult(
                feedback="Hold the bottle near one palm to start the exchange.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            _reset_state(),
        )
    start_palm = Point2D(x=float(start_palm_raw[0]), y=float(start_palm_raw[1]))

    if phase == _PHASE_RELEASED:
        if far_from_all:
            state["airborne_frames"] = int(state.get("airborne_frames", 0)) + 1
            return (
                RuleResult(
                    feedback="Bottle released. Keep it airborne toward the other hand.",
                    feedback_type="positive",
                    posture_status="stable",
                ),
                prev_hip_center,
                state,
            )

        if int(state.get("airborne_frames", 0)) < EXCHANGE_AIRBORNE_FRAMES:
            return (
                RuleResult(
                    feedback="Keep the bottle away from both hands briefly after the release.",
                    feedback_type="warning",
                    posture_status="unstable",
                ),
                prev_hip_center,
                _reset_state(),
            )

        catch_candidates = [
            (hand_id, palm)
            for hand_id, palm in near_hands
            if hand_id != start_hand
        ]
        if not catch_candidates:
            return (
                RuleResult(
                    feedback="Catch with the opposite hand, not the same hand.",
                    feedback_type="warning",
                    posture_status="unstable",
                ),
                prev_hip_center,
                _reset_state(),
            )

        catch_hand, catch_palm = catch_candidates[0]
        if _dist(start_palm, catch_palm) < EXCHANGE_MIN_TRAVEL:
            return (
                RuleResult(
                    feedback="Move the bottle farther between hands for a clear exchange.",
                    feedback_type="warning",
                    posture_status="unstable",
                ),
                prev_hip_center,
                _reset_state(),
            )

        state["phase"] = _PHASE_CATCHING
        state["catch_hand"] = catch_hand
        state["catch_frames"] = 1
        return (
            RuleResult(
                feedback="Catching — hold the bottle in the opposite hand.",
                feedback_type="positive",
                posture_status="stable",
            ),
            prev_hip_center,
            state,
        )

    if phase == _PHASE_CATCHING:
        catch_hand = state.get("catch_hand")
        if catch_hand is None or catch_hand == start_hand:
            return (
                RuleResult(
                    feedback="Catch with the opposite hand, not the same hand.",
                    feedback_type="warning",
                    posture_status="unstable",
                ),
                prev_hip_center,
                _reset_state(),
            )

        catch_palm = next(
            (palm for hand_id, palm in palms if hand_id == catch_hand),
            None,
        )
        if catch_palm is None or not _near(bottle_center, catch_palm):
            return (
                RuleResult(
                    feedback="Keep the bottle near the catching hand to finish the exchange.",
                    feedback_type="warning",
                    posture_status="unstable",
                ),
                prev_hip_center,
                _reset_state(),
            )

        catch_frames = int(state.get("catch_frames", 0)) + 1
        state["catch_frames"] = catch_frames
        if catch_frames < EXCHANGE_CATCH_HOLD_FRAMES:
            return (
                RuleResult(
                    feedback="Catching — hold the bottle in the opposite hand.",
                    feedback_type="positive",
                    posture_status="stable",
                ),
                prev_hip_center,
                state,
            )

        state["phase"] = _PHASE_CONFIRMED
        return (
            RuleResult(
                feedback="Hand-to-hand exchange complete.",
                feedback_type="positive",
                posture_status="stable",
            ),
            prev_hip_center,
            state,
        )

    if phase == _PHASE_CONFIRMED:
        catch_hand = state.get("catch_hand")
        still_held = any(
            hand_id == catch_hand and _near(bottle_center, palm)
            for hand_id, palm in palms
        )
        if still_held:
            return (
                RuleResult(
                    feedback="Hand-to-hand exchange complete.",
                    feedback_type="positive",
                    posture_status="stable",
                ),
                prev_hip_center,
                state,
            )
        return (
            RuleResult(
                feedback="Hold the bottle near one palm to start the exchange.",
                feedback_type="warning",
                posture_status="unstable",
            ),
            prev_hip_center,
            _reset_state(),
        )

    return (
        RuleResult(
            feedback="Hold the bottle near one palm to start the exchange.",
            feedback_type="warning",
            posture_status="unstable",
        ),
        prev_hip_center,
        _reset_state(),
    )
