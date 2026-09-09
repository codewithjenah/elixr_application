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
from enum import Enum
from typing import Callable, Optional

from config import (
    MOVEMENT_CONFIG,
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
_POSE_ARM_CHAINS = (
    (11, 13, 15),  # left shoulder → elbow → wrist
    (12, 14, 16),  # right shoulder → elbow → wrist
)
_POSE_ELBOW_INDICES = (13, 14)
_POSE_SHOULDER_INDICES = (11, 12)


class ReadinessItemStatus(str, Enum):
    """Per-item readiness status (matches schemas.readiness.ReadinessStatus)."""

    READY = "ready"
    WAITING = "waiting"
    ERROR = "error"


class DetectorModality(str, Enum):
    HANDS = "hands"
    POSE = "pose"


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


PassFn = Callable[[ReadinessObservation], bool]


@dataclass(frozen=True)
class ReadinessRequirement:
    """One observability check declared on a readiness profile."""

    code: str
    waiting_message: str
    predicate: PassFn
    modalities: frozenset[DetectorModality] = frozenset()


@dataclass(frozen=True)
class ReadinessProfile:
    """Authoritative readiness checklist for one public (or legacy) movement."""

    requirements: tuple[ReadinessRequirement, ...]

    def codes(self) -> tuple[str, ...]:
        return tuple(r.code for r in self.requirements)

    def needs_hands(self) -> bool:
        return any(DetectorModality.HANDS in r.modalities for r in self.requirements)

    def needs_pose(self) -> bool:
        return any(DetectorModality.POSE in r.modalities for r in self.requirements)


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


def _pose_has_both_shoulders(pose: Optional[PoseLandmarks]) -> bool:
    if pose is None:
        return False
    return all(pose.get(i) is not None for i in _POSE_SHOULDER_INDICES)


def _pose_has_complete_arm_chain(pose: Optional[PoseLandmarks]) -> bool:
    """At least one shoulder→elbow→wrist chain with visibility threshold."""
    if pose is None:
        return False
    for shoulder_i, elbow_i, wrist_i in _POSE_ARM_CHAINS:
        if (
            pose.get(shoulder_i) is not None
            and pose.get(elbow_i) is not None
            and pose.get(wrist_i) is not None
        ):
            return True
    return False


def _pass_upper_body_visible(obs: ReadinessObservation) -> bool:
    """Observability-only: both shoulders plus one complete arm chain."""
    pose = obs.pose
    if not _pose_has_both_shoulders(pose):
        return False
    return _pose_has_complete_arm_chain(pose)


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


def _prop_label(prop_type: str) -> str:
    if prop_type == "shaker":
        return "shaker"
    if prop_type == "bottle_and_shaker":
        return "props"
    return "bottle"


def _req(
    code: str,
    waiting_message: str,
    predicate: PassFn,
    *modalities: DetectorModality,
) -> ReadinessRequirement:
    return ReadinessRequirement(
        code=code,
        waiting_message=waiting_message,
        predicate=predicate,
        modalities=frozenset(modalities),
    )


def _camera_req() -> ReadinessRequirement:
    return _req(
        "camera_frame",
        "Live camera frame received.",
        _pass_camera,
    )


def _single_prop_req(prop_type: str) -> ReadinessRequirement:
    label = _prop_label(prop_type)
    return _req(
        "prop_detected",
        f"Keep the selected {label} fully inside the frame.",
        lambda obs, pt=prop_type: _pass_prop_detected(obs, pt),
    )


def _grip_req() -> ReadinessRequirement:
    return _req(
        "grip_landmarks_visible",
        "Keep the full gripping hand visible.",
        _pass_grip_landmarks,
        DetectorModality.HANDS,
    )


def _palm_req() -> ReadinessRequirement:
    return _req(
        "palm_landmarks_visible",
        "Keep the center of your hand visible.",
        _pass_palm_landmarks,
        DetectorModality.HANDS,
    )


def _index_req() -> ReadinessRequirement:
    return _req(
        "index_landmarks_visible",
        "Keep the index-finger tracking points visible.",
        _pass_index_landmarks,
        DetectorModality.HANDS,
    )


def _upper_body_req() -> ReadinessRequirement:
    return _req(
        "upper_body_visible",
        "Keep both shoulders and at least one complete arm visible.",
        _pass_upper_body_visible,
        DetectorModality.POSE,
    )


def _bottle_req() -> ReadinessRequirement:
    return _req(
        "bottle_detected",
        "Keep the bottle fully inside the frame.",
        _pass_bottle_detected,
    )


def _shaker_req() -> ReadinessRequirement:
    return _req(
        "shaker_detected",
        "Keep the cocktail shaker fully inside the frame.",
        _pass_shaker_detected,
    )


def _two_props_req() -> ReadinessRequirement:
    return _req(
        "prop_count_two",
        "Keep two bottles fully inside the frame.",
        _pass_prop_count_two,
    )


def _two_hands_req() -> ReadinessRequirement:
    return _req(
        "two_hands_visible",
        "Keep both hands fully inside the frame.",
        _pass_two_hands,
        DetectorModality.HANDS,
    )


def _supporting_hand_req() -> ReadinessRequirement:
    return _req(
        "supporting_hand_visible",
        "Keep a supporting hand visible in the frame.",
        _pass_supporting_hand,
        DetectorModality.HANDS,
    )


def _profile(*requirements: ReadinessRequirement) -> ReadinessProfile:
    codes = [r.code for r in requirements]
    if len(codes) != len(set(codes)):
        raise ValueError(f"duplicate readiness requirement codes: {codes}")
    return ReadinessProfile(requirements=requirements)


def _grip_profile(prop_type: str) -> ReadinessProfile:
    return _profile(_camera_req(), _single_prop_req(prop_type), _grip_req())


def _hand_stall_profile(prop_type: str) -> ReadinessProfile:
    return _profile(_camera_req(), _single_prop_req(prop_type), _palm_req())


def _one_finger_profile(prop_type: str) -> ReadinessProfile:
    return _profile(_camera_req(), _single_prop_req(prop_type), _index_req())


def _forearm_elbow_profile(prop_type: str) -> ReadinessProfile:
    # upper_body_visible already requires a complete shoulder→elbow→wrist chain;
    # do not also list a redundant pose_upper_forearm row.
    return _profile(_camera_req(), _single_prop_req(prop_type), _upper_body_req())


def _reverse_forearm_profile() -> ReadinessProfile:
    return _profile(_camera_req(), _bottle_req(), _upper_body_req())


def _shoulder_profile() -> ReadinessProfile:
    return _profile(_camera_req(), _bottle_req(), _upper_body_req())


def _double_hand_profile() -> ReadinessProfile:
    return _profile(_camera_req(), _two_props_req(), _two_hands_req())


def _bottle_in_tin_profile() -> ReadinessProfile:
    return _profile(
        _camera_req(),
        _bottle_req(),
        _shaker_req(),
        _supporting_hand_req(),
    )


def _camera_only_profile() -> ReadinessProfile:
    return _profile(_camera_req())


def readiness_profile_from_activity_spec(
    spec: dict, prop_type: str = "bottle"
) -> ReadinessProfile:
    """Build a visibility-only profile from a Teacher Activity contract."""
    hands = spec.get("hands", "none")
    body = spec.get("body", "none")
    if prop_type not in {"bottle", "shaker", "bottle_and_shaker"} or hands not in {"none", "one_hand", "two_hands"} or body not in {
        "none", "upper_body"
    }:
        raise ValueError("invalid_readiness_spec")

    requirements = [_camera_req()]
    if prop_type == "bottle":
        requirements.append(_bottle_req())
    elif prop_type == "shaker":
        requirements.append(_shaker_req())
    elif prop_type == "bottle_and_shaker":
        requirements.extend((_bottle_req(), _shaker_req()))

    if hands == "one_hand":
        requirements.append(_supporting_hand_req())
    elif hands == "two_hands":
        requirements.append(_two_hands_req())
    if body == "upper_body":
        requirements.append(_upper_body_req())
    return _profile(*requirements)


# Legacy movement names resolve to canonical profiles but are not public catalog
# entries (see enabled_catalog_movements).
_LEGACY_MOVEMENT_ALIASES: dict[str, str] = {
    "Arm Stall": "Forearm Stall",
    "Upper Forearm Stall": "Reverse Forearm Stall",
}


def _canonical_movement_name(movement: str) -> str:
    return _LEGACY_MOVEMENT_ALIASES.get(movement, movement)


def _build_profile(movement: str, prop_type: str) -> ReadinessProfile:
    prop_type = prop_type or "bottle"
    canonical = _canonical_movement_name(movement)

    if canonical in (
        "Normal Grip",
        "Bartender's Grip",
        "Reverse Grip",
        "Claw Grip",
    ):
        return _grip_profile(prop_type)
    if canonical == "Hand Stall":
        return _hand_stall_profile(prop_type)
    if canonical == "One Finger Stall":
        return _one_finger_profile(prop_type)
    if canonical in ("Forearm Stall", "Elbow Stall"):
        return _forearm_elbow_profile(prop_type)
    if canonical == "Reverse Forearm Stall":
        return _reverse_forearm_profile()
    if canonical == "Shoulder Stall":
        return _shoulder_profile()
    if canonical == "Double Hand Stall":
        return _double_hand_profile()
    if canonical == "Bottle in a tin":
        return _bottle_in_tin_profile()
    # Unknown / Free Practice: camera only (Free Practice skips readiness).
    return _camera_only_profile()


def readiness_profile_for(
    movement: str, prop_type: str = "bottle", readiness_spec: dict | None = None
) -> ReadinessProfile:
    """Return the authoritative readiness profile for a movement."""
    if readiness_spec is not None:
        return readiness_profile_from_activity_spec(readiness_spec, prop_type)
    return _build_profile(movement, prop_type)


def requirements_for(
    movement: str, prop_type: str = "bottle"
) -> list[ReadinessRequirement]:
    """Return ordered observability requirements for a catalog movement."""
    return list(readiness_profile_for(movement, prop_type).requirements)


def readiness_needs_hands(
    movement: str, prop_type: str = "bottle", readiness_spec: dict | None = None
) -> bool:
    """Whether the readiness check for *movement* requires a hands detector."""
    return readiness_profile_for(movement, prop_type, readiness_spec).needs_hands()


def readiness_needs_pose(
    movement: str, prop_type: str = "bottle", readiness_spec: dict | None = None
) -> bool:
    """Whether the readiness check for *movement* requires a pose detector."""
    return readiness_profile_for(movement, prop_type, readiness_spec).needs_pose()


def enabled_catalog_movements() -> tuple[str, ...]:
    """Public scored movements derived from MOVEMENT_CONFIG (no internals/legacy)."""
    names: list[str] = []
    for name, cfg in MOVEMENT_CONFIG.items():
        if cfg.get("internal"):
            continue
        if name in _LEGACY_MOVEMENT_ALIASES:
            continue
        names.append(name)
    return tuple(names)


def assert_readiness_profiles_complete() -> None:
    """Fail loudly when an enabled scored movement lacks a declared profile.

    Camera-only profiles are reserved for Free Practice / unknown names. Every
    public catalog movement must declare a richer observability checklist.
    """
    for movement in enabled_catalog_movements():
        profile = readiness_profile_for(movement, "bottle")
        codes = profile.codes()
        if codes == ("camera_frame",):
            raise AssertionError(
                f"enabled movement {movement!r} has camera-only readiness; "
                "declare an explicit profile"
            )
        if len(codes) != len(set(codes)):
            raise AssertionError(
                f"enabled movement {movement!r} has duplicate requirement codes: {codes}"
            )


@dataclass
class _ItemCounter:
    status: ReadinessItemStatus = ReadinessItemStatus.WAITING
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
        profile: ReadinessProfile | None = None,
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
        self._profile = profile or readiness_profile_for(self.movement, self.prop_type)
        self._specs = self._profile.requirements
        self._counters: dict[str, _ItemCounter] = {
            req.code: _ItemCounter() for req in self._specs
        }
        self._stable_started_at: float | None = None

    def reset(self) -> None:
        self._counters = {req.code: _ItemCounter() for req in self._specs}
        self._stable_started_at = None

    def update(self, observation: ReadinessObservation) -> ReadinessSnapshot:
        items: list[ReadinessItem] = []
        for req in self._specs:
            error_message = observation.item_errors.get(req.code)
            counter = self._counters[req.code]

            if error_message:
                counter.status = ReadinessItemStatus.ERROR
                counter.pass_streak = 0
                counter.fail_streak = 0
                items.append(
                    ReadinessItem(
                        code=req.code, status="error", message=error_message
                    )
                )
                continue

            passed = bool(req.predicate(observation))
            if passed:
                counter.pass_streak += 1
                counter.fail_streak = 0
                if counter.status != ReadinessItemStatus.READY:
                    if counter.pass_streak >= self.pass_frames:
                        counter.status = ReadinessItemStatus.READY
            else:
                counter.fail_streak += 1
                counter.pass_streak = 0
                if counter.status == ReadinessItemStatus.READY:
                    if counter.fail_streak >= self.fail_frames:
                        counter.status = ReadinessItemStatus.WAITING
                elif counter.status == ReadinessItemStatus.ERROR:
                    counter.status = ReadinessItemStatus.WAITING

            message = (
                "Ready."
                if counter.status == ReadinessItemStatus.READY
                else req.waiting_message
            )
            items.append(
                ReadinessItem(
                    code=req.code,
                    status=counter.status.value,
                    message=message,
                )
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
