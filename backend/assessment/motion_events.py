"""Presentation-only live motion events (airborne / flip / caught).

Observation only: this tracker never feeds RuleResult, RubricTracker,
HoldValidator, or completion. It consumes the detections the guided frame path
already produced (no extra inference) and reports short-lived cue events.

Evidence rules:
- Velocity is measured only between YOLO-confirmed frames so cached/coasted
  boxes on skipped YOLO frames cannot fake motion.
- AIRBORNE needs a held phase, then consecutive confirmed frames where the prop
  is away from every palm and moving upward faster than a release speed.
- FLIP needs an observed box-orientation change (tall <-> wide) during flight;
  a bottle translating without rotation keeps its aspect class.
- CAUGHT needs an airborne phase followed by a slow, palm-near, confirmed prop
  held for a short stable window.
Without Hands landmarks (pose-only movements) nothing is ever emitted.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Literal

from config import HAND_BOTTLE_PROXIMITY
from vision.types import HandsResult, PropDetection

MotionEventKind = Literal["airborne", "flip", "caught"]

MOTION_EVENT_TTL_S = 1.2
MIN_EVENT_CONFIDENCE = 0.35
HELD_MIN_S = 0.15
RELEASE_UP_SPEED = 0.45  # normalized frame-heights / second, upward
RELEASE_CONFIRM_FRAMES = 2
CATCH_MAX_SPEED = 0.35
CATCH_STABLE_S = 0.12
MIN_AIRBORNE_S = 0.10
MAX_AIRBORNE_S = 1.50
MISS_GRACE_S = 0.25
TALL_ASPECT = 1.35  # box height / width
WIDE_ASPECT = 0.85
FLIP_ASPECT_FRAMES = 2  # confirmed frames required in each aspect class
EDGE_MARGIN_PX = 3
# Release needs clear separation, not just leaving the grip radius, so an
# off-center (neck/base) grip moving upward is not mistaken for a toss.
RELEASE_SEPARATION = HAND_BOTTLE_PROXIMITY * 1.5


@dataclass(frozen=True)
class MotionEvent:
    kind: MotionEventKind
    confidence: float
    sequence: int
    emitted_at: float


def _aspect_class(det: PropDetection) -> str | None:
    w = det.x2 - det.x1
    h = det.y2 - det.y1
    if w <= 0 or h <= 0:
        return None
    ratio = h / w
    if ratio >= TALL_ASPECT:
        return "tall"
    if ratio <= WIDE_ASPECT:
        return "wide"
    return None


def _touches_edge(det: PropDetection, width: int, height: int) -> bool:
    return (
        det.x1 <= EDGE_MARGIN_PX
        or det.y1 <= EDGE_MARGIN_PX
        or det.x2 >= width - EDGE_MARGIN_PX
        or det.y2 >= height - EDGE_MARGIN_PX
    )


class MotionEventTracker:
    def __init__(self) -> None:
        self._sequence = 0
        self._latest: MotionEvent | None = None
        self.reset()

    def reset(self) -> None:
        """Clear phase state. The sequence stays monotonic per tracker."""
        self._phase = "idle"
        self._held_s = 0.0
        self._release_frames = 0
        self._airborne_s = 0.0
        self._catch_s = 0.0
        self._miss_s = 0.0
        self._flip_emitted = False
        self._aspects: dict[str, int] = {}
        self._confidences: list[float] = []
        self._last: PropDetection | None = None
        self._last_ts: float | None = None
        self._last_confirmed: PropDetection | None = None
        self._last_confirmed_ts: float | None = None
        self._latest = None

    def current(self, now: float) -> MotionEvent | None:
        """Latest event while still within its display TTL."""
        latest = self._latest
        if latest is None or now - latest.emitted_at > MOTION_EVENT_TTL_S:
            return None
        return latest

    def update(
        self,
        *,
        timestamp: float,
        prop: PropDetection | None,
        hands: HandsResult | None,
        width: int,
        height: int,
    ) -> MotionEvent | None:
        dt = 0.0 if self._last_ts is None else max(0.0, timestamp - self._last_ts)
        self._last_ts = timestamp
        if hands is None or width <= 0 or height <= 0:
            # No hand evidence: separation is unobservable, never guess.
            self.reset_phase()
            return None

        confirmed = prop is not None and prop.yolo_confirmed
        vx = vy = None
        if confirmed and self._last_confirmed is not None:
            cdt = timestamp - (self._last_confirmed_ts or timestamp)
            if cdt > 0:
                vx = (prop.center.x - self._last_confirmed.center.x) / width / cdt
                vy = (prop.center.y - self._last_confirmed.center.y) / height / cdt
        if confirmed:
            self._last_confirmed = prop
            self._last_confirmed_ts = timestamp
        palm_dist = self._palm_distance(prop, hands, width, height)
        near = palm_dist is not None and palm_dist <= HAND_BOTTLE_PROXIMITY

        if self._phase == "idle":
            if confirmed and near:
                self._phase = "held"
                self._held_s = 0.0
        elif self._phase == "held":
            if prop is None:
                self.reset_phase()
            elif palm_dist is None:
                # Hands ran but no palm was found (often the gripping hand is
                # occluded by the bottle). Unobservable, not a release.
                self._release_frames = 0
            elif near:
                self._held_s += dt
                self._release_frames = 0
            elif (
                confirmed
                and vy is not None
                and self._held_s >= HELD_MIN_S
                and palm_dist >= RELEASE_SEPARATION
                and -vy >= RELEASE_UP_SPEED
                and prop.confidence >= MIN_EVENT_CONFIDENCE
            ):
                # Each counted frame is >= MIN_EVENT_CONFIDENCE, so the
                # airborne emit below cannot be suppressed after transition.
                self._release_frames += 1
                self._confidences.append(prop.confidence)
                if self._release_frames >= RELEASE_CONFIRM_FRAMES:
                    self._phase = "airborne"
                    self._airborne_s = 0.0
                    self._miss_s = 0.0
                    self._flip_emitted = False
                    self._aspects = {}
                    return self._emit("airborne", timestamp)
            elif confirmed and palm_dist >= RELEASE_SEPARATION:
                # Clearly away from the palm without upward speed: not a toss.
                self.reset_phase()
        elif self._phase in {"airborne", "catching"}:
            return self._in_flight(
                prop, confirmed, near, vx, vy, dt, timestamp, width, height
            )
        return None

    def reset_phase(self) -> None:
        latest, seq = self._latest, self._sequence
        last_ts = self._last_ts
        self.reset()
        self._latest, self._sequence, self._last_ts = latest, seq, last_ts

    def _in_flight(self, prop, confirmed, near, vx, vy, dt, timestamp, width, height):
        self._airborne_s += dt
        if self._airborne_s > MAX_AIRBORNE_S:
            self.reset_phase()
            return None
        if prop is None:
            self._miss_s += dt
            if self._miss_s > MISS_GRACE_S:
                self.reset_phase()
            return None
        self._miss_s = 0.0
        if not confirmed:
            return None
        self._confidences.append(prop.confidence)
        if not near and not _touches_edge(prop, width, height):
            # Edge-clipped boxes look "wide" without rotating; skip them.
            aspect = _aspect_class(prop)
            if aspect is not None and prop.confidence >= MIN_EVENT_CONFIDENCE:
                self._aspects[aspect] = self._aspects.get(aspect, 0) + 1
            if not self._flip_emitted and all(
                self._aspects.get(a, 0) >= FLIP_ASPECT_FRAMES for a in ("tall", "wide")
            ):
                self._flip_emitted = True
                return self._emit("flip", timestamp)
        speed = math.hypot(vx or 0.0, vy or 0.0) if vx is not None else None
        slow = speed is not None and speed <= CATCH_MAX_SPEED
        if near and slow and self._airborne_s >= MIN_AIRBORNE_S:
            if self._phase != "catching":
                self._phase = "catching"
                self._catch_s = 0.0
                return None
            self._catch_s += dt
            if self._catch_s >= CATCH_STABLE_S:
                event = self._emit("caught", timestamp)
                self.reset_phase()
                self._phase = "held"
                return event
        elif self._phase == "catching":
            self._phase = "airborne"
            self._catch_s = 0.0
        return None

    def _emit(self, kind: MotionEventKind, timestamp: float) -> MotionEvent | None:
        recent = self._confidences[-6:]
        confidence = sum(recent) / len(recent) if recent else 0.0
        if confidence < MIN_EVENT_CONFIDENCE:
            return None
        self._sequence += 1
        self._latest = MotionEvent(
            kind=kind,
            confidence=round(min(1.0, confidence), 3),
            sequence=self._sequence,
            emitted_at=timestamp,
        )
        return self._latest

    @staticmethod
    def _palm_distance(
        prop, hands: HandsResult, width: int, height: int
    ) -> float | None:
        """Normalized prop-center to nearest-palm distance; None if unobservable."""
        if prop is None:
            return None
        center = prop.center_normalized(width, height)
        palm = hands.nearest_palm_to(center)
        if palm is None:
            return None
        return math.hypot(palm.x - center.x, palm.y - center.y)
