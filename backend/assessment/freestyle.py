"""Playground freestyle recognition: shared-observation candidate arbitration.

This module does not run YOLO, Hands, or Pose. Callers supply one frame of
detections and the recognizer evaluates official movement rules plus a generic
Flip lifecycle. Official catalog/progression records are never mutated here.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field, replace
from typing import Callable, Literal, Optional

from assessment.rule_engine import (
    evaluate_movement,
    movement_is_internal,
    movement_required_prop_type,
)
from assessment.rules.base import CriterionCheck, RuleResult
from config import HAND_BOTTLE_PROXIMITY, MOVEMENT_CONFIG
from vision.types import BottleDetection, HandsResult, Point2D, PoseLandmarks, PropDetection

Quality = Literal["perfect", "great", "nice"]
RecognitionKind = Literal["movement", "flip", "advanced_technique", "failed_action"]
RecognitionState = Literal["searching", "candidate", "confirmed", "paused"]

ADVANCED_DISPLAY = "Advanced technique detected"
ADVANCED_HINT = "Keep progressing to discover this movement."
FLIP_DISPLAY = "Flip"
FREESTYLE_MOVEMENT_LABEL = "Freestyle"

CONFIRM_SECONDS = 0.45
EXIT_SECONDS = 0.30
UNKNOWN_GRACE_SECONDS = 0.35
PROP_STABLE_FRAMES = 4
PROP_MISS_GRACE_FRAMES = 6
AMBIGUITY_MARGIN = 0.15

FLIP_GRIP_SECONDS = 0.15
FLIP_MIN_AIRBORNE_SECONDS = 0.12
FLIP_MAX_AIRBORNE_SECONDS = 1.20
FLIP_CATCH_STABLE_SECONDS = 0.12
FLIP_RELEASE_SPEED = 0.55
FLIP_CATCH_SPEED = 0.35
FLIP_AIRBORNE_MISS_GRACE = 0.20

EvaluateFn = Callable[..., tuple[RuleResult, Optional[Point2D], Optional[dict]]]


def official_freestyle_movements() -> tuple[str, ...]:
    """Enabled official movements that Playground may evaluate internally."""
    names: list[str] = []
    for name, cfg in MOVEMENT_CONFIG.items():
        if cfg.get("internal"):
            continue
        if name in {"Arm Stall", "Upper Forearm Stall"}:
            continue
        names.append(name)
    return tuple(names)


def sanitize_allowed_movements(
    entries: list[tuple[str, str]] | None,
) -> frozenset[tuple[str, str]]:
    """Keep only official, non-internal (movement, prop_type) pairs."""
    allowed: set[tuple[str, str]] = set()
    if not entries:
        return frozenset()
    for movement, prop_type in entries:
        if not isinstance(movement, str) or not isinstance(prop_type, str):
            continue
        name = movement.strip()
        prop = prop_type.strip()
        if name not in MOVEMENT_CONFIG:
            continue
        if movement_is_internal(name):
            continue
        if prop not in {"bottle", "shaker", "bottle_and_shaker"}:
            continue
        required = movement_required_prop_type(name)
        if required is not None and prop != required:
            continue
        allowed.add((name, prop))
    return frozenset(allowed)


def static_quality(
    *,
    valid_ratio: float,
    criteria_satisfied: int,
    criteria_observed: int,
) -> Quality:
    """Map confirmation-window evidence to Perfect/Great/Nice."""
    valid_ratio = max(0.0, min(1.0, valid_ratio))
    if criteria_observed > 0:
        sat = criteria_satisfied / criteria_observed
        score = 0.55 * valid_ratio + 0.45 * sat
    else:
        score = valid_ratio
    if score >= 0.90 and valid_ratio >= 0.85:
        return "perfect"
    if score >= 0.72:
        return "great"
    return "nice"


def flip_quality(
    *,
    hang_s: float,
    catch_speed: float,
    catch_stable_s: float,
) -> Quality:
    """Map a successful release-airborne-catch cycle to quality."""
    hang_ok = hang_s >= FLIP_MIN_AIRBORNE_SECONDS
    slow_catch = catch_speed <= FLIP_CATCH_SPEED * 0.55
    stable = catch_stable_s >= FLIP_CATCH_STABLE_SECONDS
    if hang_ok and slow_catch and stable and hang_s >= FLIP_MIN_AIRBORNE_SECONDS * 1.5:
        return "perfect"
    if hang_ok and catch_speed <= FLIP_CATCH_SPEED and stable:
        return "great"
    return "nice"


def _criteria_tally(result: RuleResult) -> tuple[int, int]:
    mapping = result.criterion_results or {}
    observed = 0
    satisfied = 0
    for check in mapping.values():
        if not isinstance(check, CriterionCheck):
            continue
        if check.observed:
            observed += 1
            if check.satisfied:
                satisfied += 1
    return satisfied, observed


def _is_fully_valid(result: RuleResult) -> bool:
    return result.feedback_type == "positive" and result.posture_status == "stable"


def _candidate_score(result: RuleResult, *, allowed: bool) -> float | None:
    if not _is_fully_valid(result):
        return None
    satisfied, observed = _criteria_tally(result)
    ratio = (satisfied / observed) if observed else 1.0
    score = 10.0 + ratio
    if allowed:
        score += 5.0
    return score


def _palm_near_prop(
    prop: PropDetection | None,
    hands: HandsResult | None,
    width: int,
    height: int,
    threshold: float = HAND_BOTTLE_PROXIMITY,
) -> bool:
    if prop is None or hands is None or width <= 0 or height <= 0:
        return False
    center = prop.center_normalized(width, height)
    palm = hands.nearest_palm_to(center)
    if palm is None:
        return False
    dist = math.hypot(palm.x - center.x, palm.y - center.y)
    return dist <= threshold


def _normalized_speed(
    previous: PropDetection,
    current: PropDetection,
    dt: float,
    width: int,
    height: int,
) -> float:
    if dt <= 0 or width <= 0 or height <= 0:
        return 0.0
    dx = (current.center.x - previous.center.x) / float(width)
    dy = (current.center.y - previous.center.y) / float(height)
    return math.hypot(dx, dy) / dt


@dataclass(frozen=True)
class RecognitionEvent:
    kind: RecognitionKind
    display_label: str
    identity_revealed: bool
    quality: Quality | None = None
    movement: str | None = None
    prop_type: str | None = None
    supporting_message: str | None = None


@dataclass(frozen=True)
class FreestyleTick:
    recognition_state: RecognitionState
    recognized_display: str | None
    detected_prop_type: str | None
    event: RecognitionEvent | None = None
    identity_revealed: bool = False


@dataclass
class _StaticSample:
    valid: bool
    satisfied: int
    observed: int


@dataclass
class PropStabilizer:
    stable_frames: int = PROP_STABLE_FRAMES
    miss_grace_frames: int = PROP_MISS_GRACE_FRAMES
    _stable: str | None = None
    _pending: str | None = None
    _pending_count: int = 0
    _miss_count: int = 0

    def reset(self) -> None:
        self._stable = None
        self._pending = None
        self._pending_count = 0
        self._miss_count = 0

    def update(self, bottles: list[PropDetection], shakers: list[PropDetection]) -> str | None:
        raw = _raw_prop_label(bottles, shakers)
        if raw is None:
            self._pending = None
            self._pending_count = 0
            self._miss_count += 1
            if self._miss_count > self.miss_grace_frames:
                self._stable = None
            return self._stable
        self._miss_count = 0
        if raw == self._stable:
            self._pending = None
            self._pending_count = 0
            return self._stable
        if raw == self._pending:
            self._pending_count += 1
        else:
            self._pending = raw
            self._pending_count = 1
        if self._pending_count >= self.stable_frames:
            self._stable = raw
            self._pending = None
            self._pending_count = 0
        return self._stable


def _raw_prop_label(
    bottles: list[PropDetection],
    shakers: list[PropDetection],
) -> str | None:
    has_bottle = any(bottles)
    has_shaker = any(shakers)
    if has_bottle and has_shaker:
        return "bottle_and_shaker"
    if has_bottle:
        return "bottle"
    if has_shaker:
        return "shaker"
    return None


@dataclass
class FlipTracker:
    """Generic release → airborne → catch detector for bottle or shaker."""

    grip_seconds: float = FLIP_GRIP_SECONDS
    min_airborne_seconds: float = FLIP_MIN_AIRBORNE_SECONDS
    max_airborne_seconds: float = FLIP_MAX_AIRBORNE_SECONDS
    catch_stable_seconds: float = FLIP_CATCH_STABLE_SECONDS
    release_speed: float = FLIP_RELEASE_SPEED
    catch_speed: float = FLIP_CATCH_SPEED
    miss_grace_seconds: float = FLIP_AIRBORNE_MISS_GRACE
    _phase: str = "idle"
    _track_id: int | None = None
    _prop_class: str | None = None
    _grip_seconds: float = 0.0
    _airborne_seconds: float = 0.0
    _catch_seconds: float = 0.0
    _last_detection: PropDetection | None = None
    _last_timestamp: float | None = None
    _last_speed: float = 0.0
    _peak_airborne_speed: float = 0.0
    _miss_seconds: float = 0.0
    _armed: bool = True

    def reset(self) -> None:
        self._phase = "idle"
        self._track_id = None
        self._prop_class = None
        self._grip_seconds = 0.0
        self._airborne_seconds = 0.0
        self._catch_seconds = 0.0
        self._last_detection = None
        self._last_timestamp = None
        self._last_speed = 0.0
        self._peak_airborne_speed = 0.0
        self._miss_seconds = 0.0
        self._armed = True

    def update(
        self,
        *,
        timestamp: float,
        bottles: list[PropDetection],
        shakers: list[PropDetection],
        hands: HandsResult | None,
        width: int,
        height: int,
    ) -> RecognitionEvent | None:
        props = _tagged_props(bottles, shakers)
        current, prop_class = self._select_prop(props, hands, width, height)
        dt = 0.0
        if self._last_timestamp is not None:
            dt = max(0.0, timestamp - self._last_timestamp)
        speed = 0.0
        if current is not None and self._last_detection is not None and dt > 0:
            speed = _normalized_speed(
                self._last_detection, current, dt, width, height
            )
        near = _palm_near_prop(current, hands, width, height)
        yolo = bool(current is not None and current.yolo_confirmed)

        event: RecognitionEvent | None = None
        if self._phase == "idle":
            event = self._idle(current, prop_class, near, yolo, dt)
        elif self._phase == "gripped":
            event = self._gripped(current, near, yolo, speed, dt)
        elif self._phase == "airborne":
            event = self._airborne(current, near, yolo, speed, dt)
        elif self._phase == "catching":
            event = self._catching(current, near, yolo, speed, dt)

        if current is not None:
            self._last_detection = current
            if current.track_id is not None:
                self._track_id = current.track_id
        self._last_timestamp = timestamp
        self._last_speed = speed
        return event

    def _select_prop(
        self,
        props: list[tuple[PropDetection, str]],
        hands: HandsResult | None,
        width: int,
        height: int,
    ) -> tuple[PropDetection | None, str | None]:
        if self._track_id is not None:
            for detection, label in props:
                if detection.track_id == self._track_id:
                    return detection, label
            if self._phase in {"airborne", "catching"}:
                return None, self._prop_class
        best: tuple[PropDetection, str] | None = None
        best_dist = float("inf")
        for detection, label in props:
            if hands is None:
                if best is None:
                    best = (detection, label)
                continue
            center = detection.center_normalized(width, height)
            palm = hands.nearest_palm_to(center)
            if palm is None:
                continue
            dist = math.hypot(palm.x - center.x, palm.y - center.y)
            if dist < best_dist:
                best_dist = dist
                best = (detection, label)
        if best is None and props:
            best = props[0]
        if best is None:
            return None, None
        return best[0], best[1]

    def _idle(
        self,
        current: PropDetection | None,
        prop_class: str | None,
        near: bool,
        yolo: bool,
        dt: float,
    ) -> RecognitionEvent | None:
        if current is not None and near and yolo:
            self._phase = "gripped"
            self._prop_class = prop_class
            self._track_id = current.track_id
            self._grip_seconds = dt
            self._armed = True
        return None

    def _gripped(
        self,
        current: PropDetection | None,
        near: bool,
        yolo: bool,
        speed: float,
        dt: float,
    ) -> RecognitionEvent | None:
        if current is None:
            self.reset()
            return None
        if near:
            self._grip_seconds += dt
            return None
        # YOLO miss alone is not a release: require lost proximity AND speed.
        if self._grip_seconds >= self.grip_seconds and speed >= self.release_speed:
            self._phase = "airborne"
            self._airborne_seconds = 0.0
            self._peak_airborne_speed = speed
            self._catch_seconds = 0.0
            self._miss_seconds = 0.0
            return None
        if not yolo and not near and speed < self.release_speed:
            # Short miss / occlusion while still slow: stay gripped.
            return None
        self._phase = "idle"
        self._grip_seconds = 0.0
        return None

    def _airborne(
        self,
        current: PropDetection | None,
        near: bool,
        yolo: bool,
        speed: float,
        dt: float,
    ) -> RecognitionEvent | None:
        if current is None:
            self._miss_seconds += dt
            if self._miss_seconds > self.miss_grace_seconds:
                return self._fail()
            return None
        self._miss_seconds = 0.0
        self._airborne_seconds += dt
        self._peak_airborne_speed = max(self._peak_airborne_speed, speed)
        if self._airborne_seconds > self.max_airborne_seconds:
            return self._fail()
        if self._airborne_seconds < self.min_airborne_seconds:
            return None
        # Reacquisition alone is not a catch.
        if yolo and near and speed <= self.catch_speed:
            self._phase = "catching"
            self._catch_seconds = 0.0
        return None

    def _catching(
        self,
        current: PropDetection | None,
        near: bool,
        yolo: bool,
        speed: float,
        dt: float,
    ) -> RecognitionEvent | None:
        if current is None:
            self._miss_seconds += dt
            if self._miss_seconds > self.miss_grace_seconds:
                return self._fail()
            return None
        self._miss_seconds = 0.0
        if not (yolo and near and speed <= self.catch_speed):
            if not near and speed >= self.release_speed:
                self._phase = "airborne"
                self._catch_seconds = 0.0
                return None
            return self._fail()
        self._catch_seconds += dt
        if self._catch_seconds >= self.catch_stable_seconds:
            quality = flip_quality(
                hang_s=self._airborne_seconds,
                catch_speed=speed,
                catch_stable_s=self._catch_seconds,
            )
            prop_type = self._prop_class
            self._phase = "idle"
            self._grip_seconds = 0.0
            self._airborne_seconds = 0.0
            self._catch_seconds = 0.0
            self._armed = False
            return RecognitionEvent(
                kind="flip",
                display_label=FLIP_DISPLAY,
                identity_revealed=True,
                quality=quality,
                movement=None,
                prop_type=prop_type,
            )
        return None

    def _fail(self) -> RecognitionEvent:
        self._phase = "idle"
        self._grip_seconds = 0.0
        self._airborne_seconds = 0.0
        self._catch_seconds = 0.0
        self._miss_seconds = 0.0
        self._track_id = None
        self._armed = True
        return RecognitionEvent(
            kind="failed_action",
            display_label="",
            identity_revealed=False,
            quality=None,
            movement=None,
            prop_type=self._prop_class,
        )


def _tagged_props(
    bottles: list[PropDetection],
    shakers: list[PropDetection],
) -> list[tuple[PropDetection, str]]:
    tagged: list[tuple[PropDetection, str]] = []
    for detection in bottles:
        tagged.append((detection, "bottle"))
    for detection in shakers:
        tagged.append((detection, "shaker"))
    return tagged


@dataclass
class FreestyleRecognizer:
    allowed_movements: frozenset[tuple[str, str]]
    evaluate_fn: EvaluateFn = evaluate_movement
    confirm_seconds: float = CONFIRM_SECONDS
    exit_seconds: float = EXIT_SECONDS
    unknown_grace_seconds: float = UNKNOWN_GRACE_SECONDS
    _prop: PropStabilizer = field(default_factory=PropStabilizer)
    _flip: FlipTracker = field(default_factory=FlipTracker)
    _states: dict[tuple[str, str], dict] = field(default_factory=dict)
    _prev_hip: Point2D | None = None
    _candidate_key: tuple[str, str] | None = None
    _candidate_seconds: float = 0.0
    _confirmed_key: tuple[str, str] | None = None
    _exit_seconds: float = 0.0
    _unknown_seconds: float = 0.0
    _samples: list[_StaticSample] = field(default_factory=list)
    _paused: bool = False
    _last_timestamp: float | None = None
    _last_tick: FreestyleTick = field(
        default_factory=lambda: FreestyleTick(
            recognition_state="searching",
            recognized_display=None,
            detected_prop_type=None,
        )
    )

    def reset(self) -> None:
        self._prop.reset()
        self._flip.reset()
        self._states.clear()
        self._prev_hip = None
        self._candidate_key = None
        self._candidate_seconds = 0.0
        self._confirmed_key = None
        self._exit_seconds = 0.0
        self._unknown_seconds = 0.0
        self._samples.clear()
        self._paused = False
        self._last_timestamp = None
        self._last_tick = FreestyleTick(
            recognition_state="searching",
            recognized_display=None,
            detected_prop_type=None,
        )

    def set_paused(self, paused: bool) -> None:
        self._paused = paused
        if paused:
            self._flip._last_timestamp = None
            self._last_tick = replace(
                self._last_tick,
                recognition_state="paused",
                event=None,
            )

    def update(
        self,
        *,
        timestamp: float,
        dt: float,
        bottles: list[PropDetection],
        shakers: list[PropDetection],
        hands: HandsResult | None,
        pose: PoseLandmarks | None,
        width: int,
        height: int,
        calibration_scale: float = 1.0,
    ) -> FreestyleTick:
        detected_prop = self._prop.update(bottles, shakers)
        if self._paused:
            self._last_timestamp = timestamp
            return FreestyleTick(
                recognition_state="paused",
                recognized_display=self._last_tick.recognized_display,
                detected_prop_type=detected_prop,
                identity_revealed=self._last_tick.identity_revealed,
            )

        flip_event = self._flip.update(
            timestamp=timestamp,
            bottles=bottles,
            shakers=shakers,
            hands=hands,
            width=width,
            height=height,
        )
        confirmed_bottles = [item for item in bottles if item.yolo_confirmed]
        confirmed_shakers = [item for item in shakers if item.yolo_confirmed]
        scored = self._evaluate_catalog(
            bottles=confirmed_bottles,
            shakers=confirmed_shakers,
            hands=hands,
            pose=pose,
            calibration_scale=calibration_scale,
        )
        chosen = self._arbitrate(scored, detected_prop)
        static_dt = dt
        if self._last_timestamp is not None:
            static_dt = max(0.0, timestamp - self._last_timestamp)
        self._last_timestamp = timestamp
        static_event = self._advance_static(chosen, static_dt)

        if flip_event is not None and flip_event.kind == "flip":
            event = flip_event
            self._clear_static_hold()
        elif static_event is not None:
            event = static_event
        else:
            event = flip_event

        display, revealed, state = self._live_label()
        tick = FreestyleTick(
            recognition_state=state,
            recognized_display=display,
            detected_prop_type=detected_prop,
            event=event,
            identity_revealed=revealed,
        )
        self._last_tick = replace(tick, event=None)
        return tick

    def _evaluate_catalog(
        self,
        *,
        bottles: list[PropDetection],
        shakers: list[PropDetection],
        hands: HandsResult | None,
        pose: PoseLandmarks | None,
        calibration_scale: float,
    ) -> list[tuple[tuple[str, str], RuleResult, float]]:
        scored: list[tuple[tuple[str, str], RuleResult, float]] = []
        for movement in official_freestyle_movements():
            required = movement_required_prop_type(movement)
            jobs: list[tuple[str, BottleDetection | None, list[PropDetection], list[PropDetection] | None, str]] = []
            if required == "bottle_and_shaker":
                if bottles and shakers:
                    jobs.append(
                        (
                            "bottle_and_shaker",
                            bottles[0],
                            bottles,
                            shakers,
                            "Bottle + Cocktail Shaker",
                        )
                    )
            else:
                if bottles:
                    jobs.append(("bottle", bottles[0], bottles, None, "Bottle"))
                if shakers:
                    jobs.append(
                        ("shaker", shakers[0], shakers, None, "Cocktail Shaker")
                    )
            for prop_type, primary, bottle_list, shaker_list, label in jobs:
                key = (movement, prop_type)
                state = self._states.setdefault(key, {})
                result, self._prev_hip, new_state = self.evaluate_fn(
                    movement,
                    primary,
                    pose,
                    hands,
                    self._prev_hip,
                    state,
                    bottles=bottle_list,
                    shakers=shaker_list,
                    prop_type=prop_type,
                    prop_label=label,
                    calibration_scale=calibration_scale,
                )
                if new_state is not None:
                    self._states[key] = new_state
                score = _candidate_score(
                    result, allowed=key in self.allowed_movements
                )
                if score is not None:
                    scored.append((key, result, score))
        return scored

    def _arbitrate(
        self,
        scored: list[tuple[tuple[str, str], RuleResult, float]],
        detected_prop: str | None,
    ) -> tuple[tuple[str, str], RuleResult] | None:
        if not scored:
            return None
        if self._confirmed_key is not None:
            for key, result, _ in scored:
                if key == self._confirmed_key:
                    return key, result
        scored.sort(
            key=lambda item: (
                0 if item[0] in self.allowed_movements else 1,
                -item[2],
                item[0][0],
                item[0][1],
            )
        )
        top_key, top_result, top_score = scored[0]
        close = [
            item
            for item in scored
            if top_score - item[2] < AMBIGUITY_MARGIN
            and (
                (item[0] in self.allowed_movements)
                == (top_key in self.allowed_movements)
            )
        ]
        if len(close) > 1:
            movements = {item[0][0] for item in close}
            if len(movements) > 1:
                return None
            if detected_prop in {"bottle", "shaker"}:
                for key, result, _ in close:
                    if key[1] == detected_prop:
                        return key, result
            allowed_close = [
                item for item in close if item[0] in self.allowed_movements
            ]
            if len(allowed_close) == 1:
                return allowed_close[0][0], allowed_close[0][1]
            if len(allowed_close) > 1:
                return None
            return None
        return top_key, top_result

    def _advance_static(
        self,
        chosen: tuple[tuple[str, str], RuleResult] | None,
        dt: float,
    ) -> RecognitionEvent | None:
        if chosen is None:
            if self._confirmed_key is None and self._candidate_key is None:
                self._unknown_seconds = 0.0
                self._exit_seconds = 0.0
                self._candidate_seconds = 0.0
                return None
            self._unknown_seconds += dt
            if self._unknown_seconds <= self.unknown_grace_seconds:
                return None
            self._exit_seconds += dt
            if self._exit_seconds >= self.exit_seconds:
                self._clear_static_hold()
            return None

        key, result = chosen
        if result.posture_status == "unknown":
            self._unknown_seconds += dt
            if (
                self._unknown_seconds > self.unknown_grace_seconds
                and self._confirmed_key is not None
            ):
                self._exit_seconds += dt
                if self._exit_seconds >= self.exit_seconds:
                    self._clear_static_hold()
            return None

        self._unknown_seconds = 0.0
        if self._confirmed_key == key:
            self._exit_seconds = 0.0
            self._record_sample(result)
            return None
        if self._confirmed_key is not None and self._confirmed_key != key:
            self._exit_seconds += dt
            if self._exit_seconds < self.exit_seconds:
                return None
            self._clear_static_hold()

        if self._candidate_key != key:
            self._candidate_key = key
            self._candidate_seconds = 0.0
            self._samples = [_sample(result)]
            return None

        self._candidate_seconds += dt
        self._record_sample(result)
        if self._candidate_seconds < self.confirm_seconds:
            return None

        self._confirmed_key = key
        self._candidate_key = key
        self._exit_seconds = 0.0
        event = self._emit_static(key)
        self._samples = []
        return event

    def _record_sample(self, result: RuleResult) -> None:
        self._samples.append(_sample(result))
        if len(self._samples) > 48:
            self._samples = self._samples[-48:]

    def _emit_static(self, key: tuple[str, str]) -> RecognitionEvent:
        movement, prop_type = key
        quality = self._quality_from_samples()
        if key in self.allowed_movements:
            return RecognitionEvent(
                kind="movement",
                display_label=movement,
                identity_revealed=True,
                quality=quality,
                movement=movement,
                prop_type=prop_type,
            )
        return RecognitionEvent(
            kind="advanced_technique",
            display_label=ADVANCED_DISPLAY,
            identity_revealed=False,
            quality=quality,
            movement=None,
            prop_type=prop_type,
            supporting_message=ADVANCED_HINT,
        )

    def _quality_from_samples(self) -> Quality:
        if not self._samples:
            return "nice"
        valid = sum(1 for sample in self._samples if sample.valid)
        satisfied = sum(sample.satisfied for sample in self._samples)
        observed = sum(sample.observed for sample in self._samples)
        return static_quality(
            valid_ratio=valid / len(self._samples),
            criteria_satisfied=satisfied,
            criteria_observed=observed,
        )

    def _clear_static_hold(self) -> None:
        self._confirmed_key = None
        self._candidate_key = None
        self._candidate_seconds = 0.0
        self._exit_seconds = 0.0
        self._unknown_seconds = 0.0
        self._samples.clear()

    def _live_label(self) -> tuple[str | None, bool, RecognitionState]:
        if self._paused:
            return (
                self._last_tick.recognized_display,
                self._last_tick.identity_revealed,
                "paused",
            )
        key = self._confirmed_key
        if key is not None:
            if key in self.allowed_movements:
                return key[0], True, "confirmed"
            return ADVANCED_DISPLAY, False, "confirmed"
        if self._candidate_key is not None:
            return None, False, "candidate"
        return None, False, "searching"


def _sample(result: RuleResult) -> _StaticSample:
    satisfied, observed = _criteria_tally(result)
    return _StaticSample(
        valid=_is_fully_valid(result),
        satisfied=satisfied,
        observed=observed,
    )
