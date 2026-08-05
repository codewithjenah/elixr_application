"""Pre-practice readiness: observability-only input checks + stabilization.

Readiness answers whether camera / prop / hand / pose inputs are visible and
complete enough to *evaluate* a movement. It must never require technique
correctness (open palm, grip orientation, proximity, steadiness, etc.).

Pass/fail counters and the global stable timer live only in ReadinessTracker
ephemeral state — never in movement_state, scorer, or HoldValidator.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Callable, Optional

from config import (
    READINESS_ITEM_FAIL_FRAMES,
    READINESS_ITEM_PASS_FRAMES,
    READINESS_STABLE_DURATION_S,
)
from schemas.readiness import ReadinessItem
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    PoseLandmarks,
)

# Landmark index sets copied from what rule modules *read* for presence,
# without importing technique predicates (open-palm, pinch, curl, etc.).
_GRIP_LANDMARKS = (0, 4, 8, 9, 12, 16, 20)
_PALM_LANDMARKS = (0, 9)
_INDEX_LANDMARKS = (0, 5, 6, 7, 8)
_POSE_ARM_PAIRS = ((13, 15), (14, 16))
_POSE_ELBOW_INDICES = (13, 14)
_POSE_SHOULDER_INDICES = (11, 12)

Status = str  # "ready" | "waiting" | "error"


@dataclass(frozen=True)
class ReadinessObservation:
    """One frame of vision inputs for readiness (no technique flags)."""

    has_camera_frame: bool
    bottles: list[BottleDetection] = field(default_factory=list)
    shakers: list[BottleDetection] = field(default_factory=list)
    hands: Optional[HandsResult] = None
    pose: Optional[PoseLandmarks] = None
    # Fatal model/camera errors for checklist items (code -> message).
    item_errors: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class ReadinessSnapshot:
    items: tuple[ReadinessItem, ...]
    readiness_complete: bool
    readiness_stable: bool
    readiness_stable_progress: float


def _hand_has_landmarks(hand: HandLandmarks, indices: tuple[int, ...]) -> bool:
    return all(hand.points.get(i) is not None for i in indices)


def _usable_hands(hands: Optional[HandsResult]) -> list[HandLandmarks]:
    if hands is None or not hands.hands:
        return []
    usable: list[HandLandmarks] = []
    for hand in hands.hands:
        if hand.palm_center() is not None:
            usable.append(hand)
    return usable


def _hands_with_landmarks(
    hands: Optional[HandsResult], indices: tuple[int, ...]
) -> list[HandLandmarks]:
    if hands is None or not hands.hands:
        return []
    return [h for h in hands.hands if _hand_has_landmarks(h, indices)]


def _pose_has_any_arm(pose: Optional[PoseLandmarks]) -> bool:
    if pose is None:
        return False
    for elbow_i, wrist_i in _POSE_ARM_PAIRS:
        if pose.get(elbow_i) is not None and pose.get(wrist_i) is not None:
            return True
    return False


def _pose_has_any_elbow(pose: Optional[PoseLandmarks]) -> bool:
    if pose is None:
        return False
    return any(pose.get(i) is not None for i in _POSE_ELBOW_INDICES)


def _pose_has_any_shoulder(pose: Optional[PoseLandmarks]) -> bool:
    if pose is None:
        return False
    return any(pose.get(i) is not None for i in _POSE_SHOULDER_INDICES)


def _pass_camera(obs: ReadinessObservation) -> bool:
    return obs.has_camera_frame


def _pass_prop_detected(obs: ReadinessObservation, prop_type: str) -> bool:
    if prop_type == "shaker":
        return len(obs.shakers) >= 1
    return len(obs.bottles) >= 1


def _pass_bottle_detected(obs: ReadinessObservation) -> bool:
    return len(obs.bottles) >= 1


def _pass_shaker_detected(obs: ReadinessObservation) -> bool:
    return len(obs.shakers) >= 1


def _pass_prop_count_two(obs: ReadinessObservation) -> bool:
    return len(obs.bottles) >= 2


def _pass_grip_landmarks(obs: ReadinessObservation) -> bool:
    return len(_hands_with_landmarks(obs.hands, _GRIP_LANDMARKS)) >= 1


def _pass_palm_landmarks(obs: ReadinessObservation) -> bool:
    return len(_hands_with_landmarks(obs.hands, _PALM_LANDMARKS)) >= 1


def _pass_index_landmarks(obs: ReadinessObservation) -> bool:
    return len(_hands_with_landmarks(obs.hands, _INDEX_LANDMARKS)) >= 1


def _pass_two_hands(obs: ReadinessObservation) -> bool:
    return len(_hands_with_landmarks(obs.hands, _PALM_LANDMARKS)) >= 2


def _pass_supporting_hand(obs: ReadinessObservation) -> bool:
    return len(_usable_hands(obs.hands)) >= 1


def _pass_pose_forearm_or_hand(obs: ReadinessObservation) -> bool:
    if _pose_has_any_arm(obs.pose) or _pose_has_any_elbow(obs.pose):
        return True
    return len(_usable_hands(obs.hands)) >= 1


def _pass_pose_upper_forearm(obs: ReadinessObservation) -> bool:
    return _pose_has_any_arm(obs.pose)


def _pass_pose_shoulder(obs: ReadinessObservation) -> bool:
    return _pose_has_any_shoulder(obs.pose)


# (code, default_waiting_message, pass_fn factory keyed by prop_type)
RequirementSpec = tuple[str, str, Callable[[ReadinessObservation], bool]]


def _prop_label(prop_type: str) -> str:
    if prop_type == "shaker":
        return "shaker"
    if prop_type == "bottle_and_shaker":
        return "props"
    return "bottle"


def requirements_for(movement: str, prop_type: str = "bottle") -> list[RequirementSpec]:
    """Return ordered observability requirements for a catalog movement."""
    prop_type = prop_type or "bottle"
    label = _prop_label(prop_type)

    camera: RequirementSpec = (
        "camera_frame",
        "Waiting for a usable camera frame.",
        _pass_camera,
    )

    grip_hands: list[RequirementSpec] = [
        (
            "grip_landmarks_visible",
            "Show your gripping hand with fingers visible.",
            _pass_grip_landmarks,
        ),
    ]

    single_prop: RequirementSpec = (
        "prop_detected",
        f"Show the {label} in frame.",
        lambda obs, pt=prop_type: _pass_prop_detected(obs, pt),
    )

    if movement in (
        "Normal Grip",
        "Bartender's Grip",
        "Reverse Grip",
        "Claw Grip",
    ):
        return [camera, single_prop, *grip_hands]

    if movement == "Hand Stall":
        return [
            camera,
            single_prop,
            (
                "palm_landmarks_visible",
                "Show your hand palm landmarks in frame.",
                _pass_palm_landmarks,
            ),
        ]

    if movement == "One Finger Stall":
        return [
            camera,
            single_prop,
            (
                "index_landmarks_visible",
                "Show your index finger landmarks in frame.",
                _pass_index_landmarks,
            ),
        ]

    if movement in ("Forearm Stall", "Elbow Stall", "Arm Stall"):
        return [
            camera,
            single_prop,
            (
                "pose_forearm_or_hand",
                "Show your arm pose landmarks or hand in frame.",
                _pass_pose_forearm_or_hand,
            ),
        ]

    if movement in ("Reverse Forearm Stall", "Upper Forearm Stall"):
        return [
            camera,
            (
                "bottle_detected",
                "Show the bottle in frame.",
                _pass_bottle_detected,
            ),
            (
                "pose_upper_forearm",
                "Show your upper-arm pose landmarks in frame.",
                _pass_pose_upper_forearm,
            ),
        ]

    if movement == "Shoulder Stall":
        return [
            camera,
            (
                "bottle_detected",
                "Show the bottle in frame.",
                _pass_bottle_detected,
            ),
            (
                "pose_shoulder",
                "Show your shoulder landmarks in frame.",
                _pass_pose_shoulder,
            ),
        ]

    if movement == "Double Hand Stall":
        return [
            camera,
            (
                "prop_count_two",
                "Show two bottles in frame.",
                _pass_prop_count_two,
            ),
            (
                "two_hands_visible",
                "Show both hands with landmarks visible.",
                _pass_two_hands,
            ),
        ]

    if movement == "Bottle in a tin":
        return [
            camera,
            (
                "bottle_detected",
                "Show the bottle in frame.",
                _pass_bottle_detected,
            ),
            (
                "shaker_detected",
                "Show the cocktail shaker in frame.",
                _pass_shaker_detected,
            ),
            (
                "supporting_hand_visible",
                "Show your supporting hand in frame.",
                _pass_supporting_hand,
            ),
        ]

    # Unknown / Free Practice: camera only (Free Practice skips readiness).
    return [camera]


_HANDS_REQUIREMENT_CODES: frozenset[str] = frozenset({
    "grip_landmarks_visible",
    "palm_landmarks_visible",
    "index_landmarks_visible",
    "two_hands_visible",
    "supporting_hand_visible",
    # pose_forearm_or_hand accepts either pose OR hand; open both detectors.
    "pose_forearm_or_hand",
})

_POSE_REQUIREMENT_CODES: frozenset[str] = frozenset({
    "pose_forearm_or_hand",
    "pose_upper_forearm",
    "pose_shoulder",
})


def readiness_needs_hands(movement: str, prop_type: str = "bottle") -> bool:
    """Whether the readiness check for *movement* requires a hands detector."""
    specs = requirements_for(movement, prop_type)
    return any(code in _HANDS_REQUIREMENT_CODES for code, _, _ in specs)


def readiness_needs_pose(movement: str, prop_type: str = "bottle") -> bool:
    """Whether the readiness check for *movement* requires a pose detector."""
    specs = requirements_for(movement, prop_type)
    return any(code in _POSE_REQUIREMENT_CODES for code, _, _ in specs)


def enabled_catalog_movements() -> tuple[str, ...]:
    """The twelve user-selectable scored movements."""
    return (
        "Normal Grip",
        "Bartender's Grip",
        "Reverse Grip",
        "Claw Grip",
        "Hand Stall",
        "One Finger Stall",
        "Forearm Stall",
        "Elbow Stall",
        "Reverse Forearm Stall",
        "Shoulder Stall",
        "Double Hand Stall",
        "Bottle in a tin",
    )


@dataclass
class _ItemCounter:
    status: Status = "waiting"
    pass_streak: int = 0
    fail_streak: int = 0


class ReadinessTracker:
    """Per-session readiness hysteresis + monotonic global stable timer.

    Completely separate from movement_state / scorer / hold.
    """

    def __init__(
        self,
        movement: str,
        prop_type: str = "bottle",
        *,
        pass_frames: int | None = None,
        fail_frames: int | None = None,
        stable_duration_s: float | None = None,
        monotonic: Callable[[], float] | None = None,
    ) -> None:
        self.movement = movement
        self.prop_type = prop_type or "bottle"
        self.pass_frames = (
            READINESS_ITEM_PASS_FRAMES if pass_frames is None else pass_frames
        )
        self.fail_frames = (
            READINESS_ITEM_FAIL_FRAMES if fail_frames is None else fail_frames
        )
        self.stable_duration_s = (
            READINESS_STABLE_DURATION_S
            if stable_duration_s is None
            else stable_duration_s
        )
        self._monotonic = monotonic or time.monotonic
        self._specs = requirements_for(self.movement, self.prop_type)
        self._counters: dict[str, _ItemCounter] = {
            code: _ItemCounter() for code, _, _ in self._specs
        }
        self._stable_started_at: float | None = None

    def reset(self) -> None:
        self._counters = {code: _ItemCounter() for code, _, _ in self._specs}
        self._stable_started_at = None

    def update(self, observation: ReadinessObservation) -> ReadinessSnapshot:
        items: list[ReadinessItem] = []
        for code, waiting_message, pass_fn in self._specs:
            error_message = observation.item_errors.get(code)
            counter = self._counters[code]

            if error_message:
                counter.status = "error"
                counter.pass_streak = 0
                counter.fail_streak = 0
                items.append(
                    ReadinessItem(
                        code=code, status="error", message=error_message
                    )
                )
                continue

            passed = bool(pass_fn(observation))
            if passed:
                counter.pass_streak += 1
                counter.fail_streak = 0
                if counter.status != "ready":
                    if counter.pass_streak >= self.pass_frames:
                        counter.status = "ready"
            else:
                counter.fail_streak += 1
                counter.pass_streak = 0
                if counter.status == "ready":
                    if counter.fail_streak >= self.fail_frames:
                        counter.status = "waiting"
                elif counter.status == "error":
                    counter.status = "waiting"

            message = (
                "Ready."
                if counter.status == "ready"
                else waiting_message
            )
            items.append(
                ReadinessItem(code=code, status=counter.status, message=message)
            )

        all_ready = bool(items) and all(i.status == "ready" for i in items)
        now = self._monotonic()

        if not all_ready:
            self._stable_started_at = None
            progress = 0.0
            stable = False
        else:
            if self._stable_started_at is None:
                self._stable_started_at = now
            elapsed = max(0.0, now - self._stable_started_at)
            if self.stable_duration_s <= 0:
                progress = 1.0
            else:
                progress = min(1.0, elapsed / self.stable_duration_s)
            stable = progress >= 1.0

        return ReadinessSnapshot(
            items=tuple(items),
            readiness_complete=all_ready,
            readiness_stable=stable,
            readiness_stable_progress=progress,
        )
