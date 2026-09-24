"""Deterministic custom-movement sequence capture and comparison.

Only detector measurements are accepted: no images, user code, or
movement-name-specific rules are stored here. Coordinates are
normalised around the body and shoulder scale while retaining left/right keys.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
import math
from typing import Any, Iterable, Mapping, Sequence

from vision.bottle_orientation import BottleOrientation, wrapped_delta


SCHEMA_VERSION = 2
CAPTURE_VERSION = 1
CANONICAL_FRAMES = 32
MIN_FRAMES = 8
MIN_COVERAGE = 0.70
MAX_TRACK_GAP = 2
POSE_MOTION_THRESHOLD = 0.08
MEANINGFUL_POSE_KEYS = frozenset(
    {
        "13",
        "14",
        "15",
        "16",
        "left_elbow",
        "right_elbow",
        "left_wrist",
        "right_wrist",
    }
)
EPSILON = 1e-6
MAX_ORIENTATION_INTERVAL_MS = 180
MAX_ANGULAR_STEP_RAD = math.pi * 0.85
MIN_ROTATION_COVERAGE = 0.80
MIN_ROTATION_PAIR_COVERAGE = 0.70
MIN_ROTATION_AMOUNT_RAD = math.pi * 1.3
MAX_REFERENCE_ROTATION_SPREAD_RAD = math.pi * 0.8
SUPPORTED_MODALITIES = frozenset({"pose", "hands", "prop_translation"})
BASE_CAPABILITIES = frozenset(
    {"pose", "hands", "prop_translation", "release_catch", "prop_rotation"}
)
SIDE_CAPABILITIES = frozenset({"left_hand", "right_hand"})


class FailureCode(str, Enum):
    INVALID_SCHEMA = "invalid_schema"
    MISSING_MODALITY = "missing_modality"
    INSUFFICIENT_FRAMES = "insufficient_frames"
    TRACK_LOSS = "track_loss"
    INVALID_REFERENCE_COUNT = "invalid_reference_count"
    INVALID_TIMESTAMPS = "invalid_timestamps"
    INSUFFICIENT_ORIENTATION = "insufficient_orientation"


@dataclass(frozen=True)
class Landmark:
    x: float
    y: float
    confidence: float = 1.0

    def usable(self) -> bool:
        return self.confidence >= 0.5 and math.isfinite(self.x) and math.isfinite(self.y)

    def to_dict(self) -> dict[str, float]:
        return {"x": self.x, "y": self.y, "confidence": self.confidence}

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any]) -> "Landmark":
        return cls(float(raw["x"]), float(raw["y"]), float(raw.get("confidence", 1.0)))


@dataclass(frozen=True)
class FrameSample:
    """One synchronised detector observation at ``timestamp_ms``.

    ``pose`` uses detector landmark IDs.  ``hands`` is keyed by canonical
    laterality (``left``/``right``); a hand is represented by its palm centre.
    ``prop`` is the detector centre.  Missing/low-confidence observations are
    represented as absent rather than fabricated values.
    """

    timestamp_ms: int
    pose: Mapping[str, Landmark] = field(default_factory=dict)
    hands: Mapping[str, Landmark] = field(default_factory=dict)
    prop: Landmark | None = None
    prop_metadata: Mapping[str, Any] = field(default_factory=dict)
    orientation: BottleOrientation | None = None

    def to_dict(self) -> dict[str, Any]:
        result = {
            "timestamp_ms": self.timestamp_ms,
            "pose": {str(k): v.to_dict() for k, v in self.pose.items()},
            "hands": {str(k): v.to_dict() for k, v in self.hands.items()},
            "prop": self.prop.to_dict() if self.prop else None,
            "prop_metadata": dict(self.prop_metadata),
        }
        if self.orientation is not None:
            result["orientation"] = self.orientation.to_dict()
        return result

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any]) -> "FrameSample":
        prop = raw.get("prop")
        return cls(
            timestamp_ms=int(raw["timestamp_ms"]),
            pose={str(k): Landmark.from_dict(v) for k, v in raw.get("pose", {}).items()},
            hands={str(k): Landmark.from_dict(v) for k, v in raw.get("hands", {}).items()},
            prop=Landmark.from_dict(prop) if isinstance(prop, Mapping) else None,
            prop_metadata=dict(raw.get("prop_metadata", {})),
            orientation=(
                BottleOrientation.from_dict(raw["orientation"])
                if isinstance(raw.get("orientation"), Mapping)
                else None
            ),
        )


@dataclass(frozen=True)
class PropEvent:
    timestamp_ms: int
    kind: str  # contact, release, airborne, apex, catch, stable_contact

    def to_dict(self) -> dict[str, Any]:
        return {"timestamp_ms": self.timestamp_ms, "kind": self.kind}

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any]) -> "PropEvent":
        kind = str(raw["kind"])
        if kind not in {"contact", "release", "airborne", "apex", "catch", "stable_contact"}:
            raise ValueError("unknown prop event")
        return cls(timestamp_ms=int(raw["timestamp_ms"]), kind=kind)


@dataclass(frozen=True)
class ValidationResult:
    valid: bool
    codes: tuple[FailureCode, ...] = ()


@dataclass(frozen=True)
class RotationTrace:
    """Observed cumulative image-plane angle; null frames are unknown.

    This is a sampled 2D projection, not a claim about hidden 3D axial spins.
    A jump larger than 0.85*pi between samples is deliberately rejected because
    a faster spin could alias to an arbitrary number of turns.
    """

    angles_rad: tuple[float | None, ...]
    total_signed_rad: float
    coverage: float
    pair_coverage: float

    def to_dict(self) -> dict[str, Any]:
        return {
            "angles_rad": list(self.angles_rad),
            "total_signed_rad": self.total_signed_rad,
            "coverage": self.coverage,
            "pair_coverage": self.pair_coverage,
        }

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any]) -> "RotationTrace":
        if set(raw) != {"angles_rad", "total_signed_rad", "coverage", "pair_coverage"}:
            raise ValueError("invalid rotation trace")
        values = raw["angles_rad"]
        if not isinstance(values, list) or len(values) != CANONICAL_FRAMES:
            raise ValueError("invalid rotation trace")
        angles = tuple(None if value is None else float(value) for value in values)
        total = float(raw["total_signed_rad"])
        coverage = float(raw["coverage"])
        pair_coverage = float(raw["pair_coverage"])
        if (
            any(value is not None and (not math.isfinite(value) or abs(value) > 40 * math.pi) for value in angles)
            or not math.isfinite(total) or abs(total) > 40 * math.pi
            or coverage < MIN_ROTATION_COVERAGE or coverage > 1
            or pair_coverage < MIN_ROTATION_PAIR_COVERAGE or pair_coverage > 1
            or abs(total) < MIN_ROTATION_AMOUNT_RAD
            or sum(value is not None for value in angles) < CANONICAL_FRAMES // 2
        ):
            raise ValueError("invalid rotation trace")
        return cls(angles, total, coverage, pair_coverage)


@dataclass(frozen=True)
class MovementTemplate:
    schema_version: int
    capture_version: int
    duration_ms: int
    reference_count: int
    required_modalities: tuple[str, ...]
    normalization_metadata: Mapping[str, Any]
    feature_capabilities: Mapping[str, bool]
    canonical_sequence: tuple[FrameSample, ...]
    variability_metadata: Mapping[str, float]
    prop_events: tuple[PropEvent, ...] = ()
    rotation_trace: RotationTrace | None = None

    @property
    def required_hand_sides(self) -> tuple[str, ...]:
        if not self.feature_capabilities.get("hands", False):
            return ()
        if SIDE_CAPABILITIES.issubset(self.feature_capabilities):
            return tuple(
                side
                for side in ("left", "right")
                if self.feature_capabilities.get(f"{side}_hand", False)
            )
        # Version-1 templates produced before side capabilities existed always
        # required two hands.  Preserve that conservative legacy behavior.
        return ("left", "right")

    def to_dict(self) -> dict[str, Any]:
        result = {
            "schema_version": self.schema_version,
            "capture_version": self.capture_version,
            "duration_ms": self.duration_ms,
            "reference_count": self.reference_count,
            "required_modalities": list(self.required_modalities),
            "normalization_metadata": dict(self.normalization_metadata),
            "feature_capabilities": dict(self.feature_capabilities),
            "canonical_sequence": [frame.to_dict() for frame in self.canonical_sequence],
            "variability_metadata": dict(self.variability_metadata),
            "prop_events": [event.to_dict() for event in self.prop_events],
        }
        if self.schema_version >= 2:
            result["rotation_trace"] = self.rotation_trace.to_dict() if self.rotation_trace else None
        return result

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any]) -> "MovementTemplate":
        try:
            version = int(raw["schema_version"])
            expected = {
                "schema_version", "capture_version", "duration_ms",
                "reference_count", "required_modalities",
                "normalization_metadata", "feature_capabilities",
                "canonical_sequence", "variability_metadata", "prop_events",
            }
            if version == 2:
                expected.add("rotation_trace")
            if set(raw) != expected:
                raise ValueError("unexpected custom movement template fields")
            if version not in {1, SCHEMA_VERSION} or int(raw["capture_version"]) != CAPTURE_VERSION:
                raise ValueError("unsupported custom movement template schema")
            raw_capabilities = raw["feature_capabilities"]
            capability_keys = set(raw_capabilities)
            if capability_keys not in {
                BASE_CAPABILITIES,
                BASE_CAPABILITIES | SIDE_CAPABILITIES,
            } or any(
                not isinstance(value, bool) for value in raw_capabilities.values()
            ):
                raise ValueError("invalid feature capabilities")
            capabilities = dict(raw_capabilities)
            rotating = capabilities.get("prop_rotation", False)
            if (version == 2 and not rotating) or rotating != (
                version == 2 and isinstance(raw.get("rotation_trace"), Mapping)
            ):
                raise ValueError("rotation capability/trace mismatch")
            template = cls(
                schema_version=version, capture_version=int(raw["capture_version"]),
                duration_ms=int(raw["duration_ms"]), reference_count=int(raw["reference_count"]),
                required_modalities=tuple(str(v) for v in raw["required_modalities"]),
                normalization_metadata=dict(raw["normalization_metadata"]),
                feature_capabilities=capabilities,
                canonical_sequence=tuple(FrameSample.from_dict(v) for v in raw["canonical_sequence"]),
                variability_metadata={str(k): float(v) for k, v in raw["variability_metadata"].items()},
                prop_events=tuple(PropEvent.from_dict(v) for v in raw.get("prop_events", [])),
                rotation_trace=(RotationTrace.from_dict(raw["rotation_trace"]) if rotating else None),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(FailureCode.INVALID_SCHEMA.value) from exc
        if (
            template.reference_count < 2
            or len(template.canonical_sequence) != CANONICAL_FRAMES
            or not set(template.required_modalities).issubset(SUPPORTED_MODALITIES)
            or not template.required_modalities
            or (template.rotation_trace is not None and "prop_translation" not in template.required_modalities)
            or (
                template.feature_capabilities.get("hands", False)
                and not template.required_hand_sides
            )
        ):
            raise ValueError(FailureCode.INVALID_SCHEMA.value)
        return template


@dataclass(frozen=True)
class SequenceComparison:
    component_scores: Mapping[str, int | None]
    component_confidence: Mapping[str, float]
    total: int
    performance_level: str
    validation: ValidationResult

    def to_dict(self) -> dict[str, Any]:
        return {
            "component_scores": dict(self.component_scores),
            "component_confidence": dict(self.component_confidence),
            "total": self.total,
            "performance_level": self.performance_level,
            "validation_codes": [code.value for code in self.validation.codes],
        }


def _usable(point: Landmark | None) -> bool:
    return point is not None and point.usable()


def _hand_side(key: str) -> str | None:
    side = str(key).split(":", 1)[0].strip().lower()
    return side if side in {"left", "right"} else None


def _semantic_hands(hands: Mapping[str, Landmark]) -> dict[str, Landmark]:
    """Drop detector-list position while retaining side and landmark identity."""
    semantic: dict[str, Landmark] = {}
    for raw_key, point in hands.items():
        parts = str(raw_key).split(":")
        side = _hand_side(raw_key)
        if side is None:
            continue
        key = f"{side}:{parts[-1]}" if len(parts) >= 3 else str(raw_key)
        existing = semantic.get(key)
        if existing is None or point.confidence > existing.confidence:
            semantic[key] = point
    return semantic


def _coverage(
    samples: Sequence[FrameSample],
    modality: str,
    *,
    hand_side: str | None = None,
) -> tuple[float, int]:
    present: list[bool] = []
    for frame in samples:
        if modality == "pose":
            present.append(any(_usable(p) for p in frame.pose.values()))
        elif modality == "hands":
            present.append(
                any(
                    _usable(point)
                    and (hand_side is None or _hand_side(key) == hand_side)
                    for key, point in frame.hands.items()
                )
            )
        else:
            present.append(_usable(frame.prop))
    longest = current = 0
    for item in present:
        current = current + 1 if not item else 0
        longest = max(longest, current)
    return sum(present) / len(samples) if samples else 0.0, longest


def validate_sequence(
    samples: Sequence[FrameSample],
    required_modalities: Iterable[str],
    *,
    required_hand_sides: Iterable[str] = (),
    require_rotation: bool = False,
) -> ValidationResult:
    required = tuple(sorted(set(required_modalities)))
    codes: list[FailureCode] = []
    if not set(required).issubset(SUPPORTED_MODALITIES):
        codes.append(FailureCode.INVALID_SCHEMA)
    if len(samples) < MIN_FRAMES:
        codes.append(FailureCode.INSUFFICIENT_FRAMES)
    timestamps = [frame.timestamp_ms for frame in samples]
    if any(not isinstance(ts, int) for ts in timestamps) or any(b <= a for a, b in zip(timestamps, timestamps[1:])):
        codes.append(FailureCode.INVALID_TIMESTAMPS)
    for modality in required:
        sides = tuple(sorted(set(required_hand_sides))) if modality == "hands" else ()
        coverage_checks = (
            [_coverage(samples, modality, hand_side=side) for side in sides]
            if sides
            else [_coverage(samples, modality)]
        )
        for coverage, gap in coverage_checks:
            if coverage < MIN_COVERAGE:
                codes.append(FailureCode.MISSING_MODALITY)
            if gap > MAX_TRACK_GAP:
                codes.append(FailureCode.TRACK_LOSS)
    if require_rotation and samples:
        trace = _rotation_trace(samples)
        if trace.coverage < MIN_ROTATION_COVERAGE or trace.pair_coverage < MIN_ROTATION_PAIR_COVERAGE:
            codes.append(FailureCode.INSUFFICIENT_ORIENTATION)
        if not _rotation_track_stable(samples):
            codes.append(FailureCode.TRACK_LOSS)
    return ValidationResult(not codes, tuple(dict.fromkeys(codes)))


def _anchor_and_scale(
    frame: FrameSample,
    *,
    use_pose_anchor: bool,
    hands: Mapping[str, Landmark],
) -> tuple[Landmark, float]:
    if use_pose_anchor:
        left = frame.pose.get("11") or frame.pose.get("left_shoulder")
        right = frame.pose.get("12") or frame.pose.get("right_shoulder")
        if _usable(left) and _usable(right):
            assert left is not None and right is not None
            scale = math.hypot(left.x - right.x, left.y - right.y)
            if scale > EPSILON:
                return Landmark((left.x + right.x) / 2, (left.y + right.y) / 2), scale
    usable_hands = [p for p in hands.values() if _usable(p)]
    if usable_hands:
        roots = [
            point
            for side in ("left", "right")
            if _usable(point := hands.get(side) or hands.get(f"{side}:0"))
        ]
        anchor = roots[0] if roots else usable_hands[0]
        hand_scales = []
        for side in ("left", "right"):
            wrist = hands.get(f"{side}:0")
            middle_mcp = hands.get(f"{side}:9")
            if _usable(wrist) and _usable(middle_mcp):
                assert wrist is not None and middle_mcp is not None
                hand_scales.append(
                    math.hypot(wrist.x - middle_mcp.x, wrist.y - middle_mcp.y)
                )
        usable_scales = sorted(scale for scale in hand_scales if scale > EPSILON)
        scale = (
            usable_scales[len(usable_scales) // 2] if usable_scales else 1.0
        )
        return Landmark(anchor.x, anchor.y), scale
    return Landmark(0.0, 0.0), 1.0


def _normalise_point(point: Landmark | None, anchor: Landmark, scale: float) -> Landmark | None:
    if not _usable(point):
        return None
    assert point is not None
    return Landmark((point.x - anchor.x) / scale, (point.y - anchor.y) / scale, point.confidence)


def normalize_sequence(
    samples: Sequence[FrameSample],
    *,
    use_pose_anchor: bool = True,
    required_hand_sides: Iterable[str] | None = None,
) -> tuple[FrameSample, ...]:
    """Remove image translation/body scale without mirroring laterality.

    Template construction and comparison pass the inferred capabilities so
    both sides use the same coordinate system.  This matters when Pose was
    observed during reference capture but was intentionally not required (and
    therefore is not run during assessment).
    """
    output: list[FrameSample] = []
    hand_sides = (
        None
        if required_hand_sides is None
        else frozenset(required_hand_sides)
    )
    for frame in samples:
        semantic_hands = _semantic_hands(frame.hands)
        selected_hands = {
            key: point
            for key, point in semantic_hands.items()
            if hand_sides is None or _hand_side(key) in hand_sides
        }
        anchor, scale = _anchor_and_scale(
            frame,
            use_pose_anchor=use_pose_anchor,
            hands=selected_hands,
        )
        metadata = dict(frame.prop_metadata)
        for key in ("bbox_width", "bbox_height", "velocity_x", "velocity_y"):
            value = metadata.get(key)
            if isinstance(value, (int, float)) and math.isfinite(float(value)):
                metadata[key] = float(value) / scale
        output.append(FrameSample(
            timestamp_ms=frame.timestamp_ms,
            pose={k: p for k, v in frame.pose.items() if (p := _normalise_point(v, anchor, scale))},
            hands={k: p for k, v in selected_hands.items() if (p := _normalise_point(v, anchor, scale))},
            prop=_normalise_point(frame.prop, anchor, scale),
            prop_metadata=metadata,
        ))
    return tuple(output)


def _interpolate(a: Landmark | None, b: Landmark | None, amount: float) -> Landmark | None:
    if amount <= EPSILON:
        return a if _usable(a) else None
    if amount >= 1.0 - EPSILON:
        return b if _usable(b) else None
    if not _usable(a) or not _usable(b):
        # Missing observations stay unknown.  Do not stretch one endpoint
        # across a detector gap while resampling or temporal alignment.
        return None
    assert a is not None and b is not None
    return Landmark(a.x + (b.x - a.x) * amount, a.y + (b.y - a.y) * amount, min(a.confidence, b.confidence))


def _resample(samples: Sequence[FrameSample], count: int = CANONICAL_FRAMES) -> tuple[FrameSample, ...]:
    if not samples:
        return ()
    start, end = samples[0].timestamp_ms, samples[-1].timestamp_ms
    result: list[FrameSample] = []
    for index in range(count):
        target = start + (end - start) * index / max(count - 1, 1)
        upper = next((i for i, f in enumerate(samples) if f.timestamp_ms >= target), len(samples) - 1)
        lower = max(0, upper - 1)
        first, second = samples[lower], samples[upper]
        amount = 0.0 if first.timestamp_ms == second.timestamp_ms else (target - first.timestamp_ms) / (second.timestamp_ms - first.timestamp_ms)
        pose = {key: p for key in set(first.pose) | set(second.pose) if (p := _interpolate(first.pose.get(key), second.pose.get(key), amount))}
        hands = {key: p for key in set(first.hands) | set(second.hands) if (p := _interpolate(first.hands.get(key), second.hands.get(key), amount))}
        metadata = first.prop_metadata if amount < 0.5 else second.prop_metadata
        result.append(FrameSample(
            round(target), pose, hands,
            _interpolate(first.prop, second.prop, amount), dict(metadata),
        ))
    return tuple(result)


def _mean_points(
    points: Sequence[Landmark | None], *, min_count: int = 1
) -> Landmark | None:
    valid = [p for p in points if _usable(p)]
    if len(valid) < min_count:
        return None
    return Landmark(sum(p.x for p in valid) / len(valid), sum(p.y for p in valid) / len(valid), min(p.confidence for p in valid))


def _canonical_prop_metadata(frames: Sequence[FrameSample]) -> dict[str, Any]:
    """Average observable numeric prop features; omit per-run track identity."""
    output: dict[str, Any] = {}
    keys = set().union(*(frame.prop_metadata.keys() for frame in frames))
    for key in sorted(keys - {"track_id"}):
        values = [frame.prop_metadata.get(key) for frame in frames]
        numeric = [float(value) for value in values if isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))]
        if numeric:
            output[key] = sum(numeric) / len(numeric)
            continue
        booleans = [value for value in values if isinstance(value, bool)]
        if booleans:
            output[key] = sum(booleans) >= len(booleans) / 2
            continue
        text = [value for value in values if isinstance(value, str) and value]
        if text:
            output[key] = max(set(text), key=lambda item: (text.count(item), item))
    return output


def detect_prop_events(samples: Sequence[FrameSample]) -> tuple[PropEvent, ...]:
    """Generic, conservative contact lifecycle inferred from detector data.

    A one-frame miss retains state; a catch requires two slow, consecutive
    near-hand observations, preventing a fast pass-by from becoming a catch.
    """
    events: list[PropEvent] = []
    contact_run = 0
    absent_run = 0
    airborne = False
    prior_prop: Landmark | None = None
    prior_velocity: float | None = None
    for frame in samples:
        prop = frame.prop if _usable(frame.prop) else None
        hands = [h for h in frame.hands.values() if _usable(h)]
        if prop is None:
            absent_run += 1
            continue
        absent_run = 0
        distance = min((math.hypot(prop.x - h.x, prop.y - h.y) for h in hands), default=float("inf"))
        speed = 0.0
        if prior_prop is not None:
            dt = max(1, frame.timestamp_ms - previous_timestamp)
            speed = math.hypot(prop.x - prior_prop.x, prop.y - prior_prop.y) / dt
            vertical_velocity = (prop.y - prior_prop.y) / dt
            if airborne and prior_velocity is not None and prior_velocity < 0 <= vertical_velocity:
                events.append(PropEvent(frame.timestamp_ms, "apex"))
            prior_velocity = vertical_velocity
        previous_timestamp = frame.timestamp_ms
        prior_prop = prop
        near_and_slow = distance <= 0.25 and speed <= 0.0015
        contact_run = contact_run + 1 if near_and_slow else 0
        if contact_run == 2:
            events.append(PropEvent(frame.timestamp_ms, "stable_contact"))
            if airborne:
                events.append(PropEvent(frame.timestamp_ms, "catch"))
                airborne = False
            else:
                events.append(PropEvent(frame.timestamp_ms, "contact"))
        if contact_run == 0 and not airborne and events and events[-1].kind in {"contact", "stable_contact"}:
            events.append(PropEvent(frame.timestamp_ms, "release"))
            events.append(PropEvent(frame.timestamp_ms, "airborne"))
            airborne = True
    return tuple(events)


def _pose_motion(sequence: Sequence[FrameSample]) -> float:
    normalised = normalize_sequence(sequence)
    largest = 0.0
    keys = set().union(*(frame.pose.keys() for frame in normalised))
    keys.intersection_update(MEANINGFUL_POSE_KEYS)
    for key in keys:
        points = [frame.pose.get(key) for frame in normalised]
        usable = [point for point in points if _usable(point)]
        for point_index, first in enumerate(usable):
            for second in usable[point_index + 1 :]:
                assert first is not None and second is not None
                largest = max(
                    largest, math.hypot(second.x - first.x, second.y - first.y)
                )
    return largest


def _infer_requirements(
    references: Sequence[Sequence[FrameSample]],
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    hand_sides = tuple(
        side
        for side in ("left", "right")
        if all(
            (coverage := _coverage(reference, "hands", hand_side=side))[0]
            >= MIN_COVERAGE
            and coverage[1] <= MAX_TRACK_GAP
            for reference in references
        )
    )
    pose_reliable = all(
        (coverage := _coverage(reference, "pose"))[0] >= MIN_COVERAGE
        and coverage[1] <= MAX_TRACK_GAP
        for reference in references
    )
    meaningful_pose_count = sum(
        _pose_motion(reference) >= POSE_MOTION_THRESHOLD for reference in references
    )
    required = ["prop_translation"]
    if hand_sides:
        required.append("hands")
    if pose_reliable and meaningful_pose_count >= 2:
        required.append("pose")
    return tuple(sorted(required)), hand_sides


def _sequence_distance(
    reference: Sequence[FrameSample],
    candidate: Sequence[FrameSample],
    modalities: Sequence[str],
) -> float:
    path = _dtw(reference, candidate, modalities)
    errors: list[float] = []
    for left, right in path:
        observed = [
            value
            for modality in modalities
            if (value := _modality_error(reference[left], candidate[right], modality))
            is not None
        ]
        errors.append(sum(observed) / len(observed) if observed else 1.0)
    return sum(errors) / len(errors) if errors else float("inf")


def _aggregate_frames(
    frames: Sequence[FrameSample],
    *,
    timestamp_ms: int,
    minimum_presence: int,
) -> FrameSample:
    pose_keys = set().union(*(frame.pose.keys() for frame in frames))
    semantic_hands = [_semantic_hands(frame.hands) for frame in frames]
    hand_keys = set().union(*(hands.keys() for hands in semantic_hands))
    return FrameSample(
        timestamp_ms=timestamp_ms,
        pose={
            key: point
            for key in sorted(pose_keys)
            if (
                point := _mean_points(
                    [frame.pose.get(key) for frame in frames],
                    min_count=minimum_presence,
                )
            )
        },
        hands={
            key: point
            for key in sorted(hand_keys)
            if (
                point := _mean_points(
                    [hands.get(key) for hands in semantic_hands],
                    min_count=minimum_presence,
                )
            )
        },
        prop=_mean_points(
            [frame.prop for frame in frames], min_count=minimum_presence
        ),
        prop_metadata=_canonical_prop_metadata(frames),
    )


def build_template(
    references: Sequence[Sequence[FrameSample]],
    required_modalities: Iterable[str] | None = None,
) -> MovementTemplate:
    """Build a stable canonical template from at least two valid captures."""
    if len(references) < 2:
        raise ValueError(FailureCode.INVALID_REFERENCE_COUNT.value)
    # ``required_modalities`` remains accepted for source compatibility with
    # version-1 callers, but capabilities are now inferred from the recorded
    # actual demonstrations rather than imposed by the client.
    if required_modalities is not None and not set(required_modalities).issubset(
        SUPPORTED_MODALITIES
    ):
        raise ValueError(FailureCode.INVALID_SCHEMA.value)
    required, hand_sides = _infer_requirements(references)
    normalised: list[tuple[FrameSample, ...]] = []
    durations: list[int] = []
    for reference in references:
        check = validate_sequence(
            reference, required, required_hand_sides=hand_sides
        )
        if not check.valid:
            raise ValueError(",".join(code.value for code in check.codes))
        normalised.append(
            normalize_sequence(
                reference,
                use_pose_anchor="pose" in required,
                required_hand_sides=hand_sides,
            )
        )
        durations.append(reference[-1].timestamp_ms - reference[0].timestamp_ms)
    resampled = [_resample(seq) for seq in normalised]
    medoid_index = min(
        range(len(resampled)),
        key=lambda index: (
            sum(
                _sequence_distance(resampled[index], other, required)
                for other_index, other in enumerate(resampled)
                if other_index != index
            ),
            index,
        ),
    )
    medoid = resampled[medoid_index]
    aligned_by_reference: list[list[list[FrameSample]]] = []
    for sequence_index, sequence in enumerate(resampled):
        groups: list[list[FrameSample]] = [[] for _ in range(CANONICAL_FRAMES)]
        if sequence_index == medoid_index:
            for index, frame in enumerate(sequence):
                groups[index].append(frame)
        else:
            for medoid_frame, sequence_frame in _dtw(medoid, sequence, required):
                groups[medoid_frame].append(sequence[sequence_frame])
        aligned_by_reference.append(groups)

    canonical: list[FrameSample] = []
    canonical_duration = round(sum(durations) / len(durations))
    for index in range(CANONICAL_FRAMES):
        reference_frames = [
            _aggregate_frames(
                groups[index], timestamp_ms=index, minimum_presence=1
            )
            for groups in aligned_by_reference
            if groups[index]
        ]
        canonical.append(
            _aggregate_frames(
                reference_frames,
                timestamp_ms=round(
                    canonical_duration * index / (CANONICAL_FRAMES - 1)
                ),
                minimum_presence=len(references) // 2 + 1,
            )
        )
    prop_coverage = sum(frame.prop is not None for frame in canonical) / CANONICAL_FRAMES
    canonical_validation = validate_sequence(
        canonical, required, required_hand_sides=hand_sides
    )
    if not canonical_validation.valid:
        raise ValueError(
            ",".join(code.value for code in canonical_validation.codes)
        )
    prop_events = detect_prop_events(canonical)
    event_kinds = {event.kind for event in prop_events}
    has_release_catch = {"release", "catch"}.issubset(event_kinds)
    reference_rotation = [_rotation_trace(reference) for reference in references]
    reliable_rotation = all(
        trace.coverage >= MIN_ROTATION_COVERAGE
        and trace.pair_coverage >= MIN_ROTATION_PAIR_COVERAGE
        and abs(trace.total_signed_rad) >= MIN_ROTATION_AMOUNT_RAD
        and _rotation_track_stable(reference)
        for reference, trace in zip(references, reference_rotation)
    )
    rotation_trace = None
    if reliable_rotation:
        totals = [trace.total_signed_rad for trace in reference_rotation]
        if max(totals) - min(totals) <= MAX_REFERENCE_ROTATION_SPREAD_RAD:
            canonical_angles = _aggregate_rotation_angles(reference_rotation)
            if canonical_angles is not None:
                rotation_trace = RotationTrace(
                    canonical_angles,
                    sum(totals) / len(totals),
                    min(trace.coverage for trace in reference_rotation),
                    min(trace.pair_coverage for trace in reference_rotation),
                )
    return MovementTemplate(
        schema_version=SCHEMA_VERSION if rotation_trace else 1,
        capture_version=CAPTURE_VERSION,
        duration_ms=canonical_duration, reference_count=len(references),
        required_modalities=required,
        normalization_metadata={
            "anchor": (
                "shoulder_midpoint"
                if "pose" in required
                else "required_hand"
                if hand_sides
                else "image_origin"
            ),
            "scale": (
                "shoulder_width"
                if "pose" in required
                else "hand_size"
                if hand_sides
                else "image_fraction"
            ),
            "mirrored": False,
        },
        feature_capabilities={
            "pose": "pose" in required,
            "hands": "hands" in required,
            "prop_translation": prop_coverage >= MIN_COVERAGE,
            "release_catch": has_release_catch,
            "prop_rotation": rotation_trace is not None,
            "left_hand": "left" in hand_sides,
            "right_hand": "right" in hand_sides,
        },
        canonical_sequence=tuple(canonical),
        variability_metadata={"duration_std_ms": _std(durations), "reference_count": float(len(references))},
        prop_events=prop_events,
        rotation_trace=rotation_trace,
    )


def _std(values: Sequence[float]) -> float:
    mean = sum(values) / len(values)
    return math.sqrt(sum((value - mean) ** 2 for value in values) / len(values))


def _observed_rotation(samples: Sequence[FrameSample]) -> tuple[list[float | None], float, float, float]:
    angles: list[float | None] = []
    prior: FrameSample | None = None
    cumulative = 0.0
    good_pairs = 0
    observed = 0
    for frame in samples:
        current = frame.orientation
        if current is None or frame.prop is None:
            angles.append(None)
            prior = None
            continue
        observed += 1
        if prior is None:
            angles.append(0.0 if not any(v is not None for v in angles) else None)
            prior = frame
            continue
        prior_id = prior.prop_metadata.get("track_id")
        current_id = frame.prop_metadata.get("track_id")
        delta = wrapped_delta(current.angle_rad, prior.orientation.angle_rad)
        adjacent = (
            prior_id is not None
            and prior_id == current_id
            and 0 < frame.timestamp_ms - prior.timestamp_ms <= MAX_ORIENTATION_INTERVAL_MS
            and abs(delta) < MAX_ANGULAR_STEP_RAD
        )
        if adjacent:
            cumulative += delta
            good_pairs += 1
            angles.append(cumulative)
        else:
            # Start a new segment without assigning unobserved turns to it.
            angles.append(None)
        prior = frame
    size = len(samples)
    return angles, cumulative, observed / size if size else 0.0, good_pairs / max(size - 1, 1)


def _rotation_track_stable(samples: Sequence[FrameSample]) -> bool:
    """Different track IDs cannot establish one continuous rotating bottle."""
    identities = {
        frame.prop_metadata.get("track_id")
        for frame in samples
        if frame.orientation is not None and frame.prop is not None
    }
    return len(identities) == 1 and None not in identities


def _resample_angles(samples: Sequence[FrameSample], angles: Sequence[float | None]) -> tuple[float | None, ...]:
    if not samples:
        return (None,) * CANONICAL_FRAMES
    start, end = samples[0].timestamp_ms, samples[-1].timestamp_ms
    output: list[float | None] = []
    for index in range(CANONICAL_FRAMES):
        target = start + (end - start) * index / (CANONICAL_FRAMES - 1)
        upper = next((i for i, frame in enumerate(samples) if frame.timestamp_ms >= target), len(samples) - 1)
        lower = max(0, upper - 1)
        if lower == upper or samples[upper].timestamp_ms == target:
            output.append(angles[upper])
        elif angles[lower] is not None and angles[upper] is not None:
            fraction = (target - samples[lower].timestamp_ms) / (samples[upper].timestamp_ms - samples[lower].timestamp_ms)
            output.append(angles[lower] + fraction * (angles[upper] - angles[lower]))
        else:
            output.append(None)
    return tuple(output)


def _rotation_trace(samples: Sequence[FrameSample]) -> RotationTrace:
    angles, total, coverage, pair_coverage = _observed_rotation(samples)
    return RotationTrace(_resample_angles(samples, angles), total, coverage, pair_coverage)


def _aggregate_rotation_angles(traces: Sequence[RotationTrace]) -> tuple[float | None, ...] | None:
    output: list[float | None] = []
    consistent = 0
    for index in range(CANONICAL_FRAMES):
        values = [trace.angles_rad[index] for trace in traces if trace.angles_rad[index] is not None]
        if len(values) < math.ceil(len(traces) / 2):
            output.append(None)
            continue
        if max(values) - min(values) > MAX_REFERENCE_ROTATION_SPREAD_RAD:
            output.append(None)
            continue
        consistent += 1
        output.append(sum(values) / len(values))
    return tuple(output) if consistent >= CANONICAL_FRAMES * MIN_ROTATION_COVERAGE else None


def _point_distance(a: Landmark | None, b: Landmark | None) -> float | None:
    if not _usable(a) or not _usable(b):
        return None
    assert a is not None and b is not None
    return math.hypot(a.x - b.x, a.y - b.y)


def _modality_error(a: FrameSample, b: FrameSample, modality: str) -> float | None:
    if modality == "prop_translation":
        return _point_distance(a.prop, b.prop)
    left = a.pose if modality == "pose" else _semantic_hands(a.hands)
    right = b.pose if modality == "pose" else _semantic_hands(b.hands)
    distances = [_point_distance(left.get(key), right.get(key)) for key in set(left) & set(right)]
    usable = [item for item in distances if item is not None]
    return sum(usable) / len(usable) if usable else None


def _dtw(reference: Sequence[FrameSample], candidate: Sequence[FrameSample], modalities: Sequence[str]) -> list[tuple[int, int]]:
    rows, cols = len(reference), len(candidate)
    costs = [[float("inf")] * (cols + 1) for _ in range(rows + 1)]
    parent: dict[tuple[int, int], tuple[int, int]] = {}
    costs[0][0] = 0.0
    for i in range(1, rows + 1):
        for j in range(1, cols + 1):
            values = [_modality_error(reference[i - 1], candidate[j - 1], m) for m in modalities]
            observed = [v for v in values if v is not None]
            local = sum(observed) / len(observed) if observed else 1.0
            prior = min(((costs[i - 1][j], (i - 1, j)), (costs[i][j - 1], (i, j - 1)), (costs[i - 1][j - 1], (i - 1, j - 1))), key=lambda value: value[0])
            costs[i][j] = local + prior[0]
            parent[(i, j)] = prior[1]
    path: list[tuple[int, int]] = []
    current = (rows, cols)
    while current != (0, 0):
        path.append((current[0] - 1, current[1] - 1))
        current = parent[current]
    return list(reversed(path))


def _dtw_angles(reference: Sequence[float | None], candidate: Sequence[float | None]) -> list[tuple[int, int]]:
    """Align cumulative turns independently of bottle translation.

    A flat prop center cannot dictate how rotational phases are paired.
    Diagonal wins equal-cost ties so identical traces stay one-to-one.
    """
    rows, cols = len(reference), len(candidate)
    costs = [[float("inf")] * (cols + 1) for _ in range(rows + 1)]
    parent: dict[tuple[int, int], tuple[int, int]] = {}
    costs[0][0] = 0.0
    for i in range(1, rows + 1):
        for j in range(1, cols + 1):
            left, right = reference[i - 1], candidate[j - 1]
            local = abs(left - right) if left is not None and right is not None else math.pi
            prior = min(
                ((costs[i - 1][j - 1], (i - 1, j - 1)),
                 (costs[i - 1][j], (i - 1, j)),
                 (costs[i][j - 1], (i, j - 1))),
                key=lambda value: value[0],
            )
            costs[i][j] = local + prior[0]
            parent[(i, j)] = prior[1]
    path: list[tuple[int, int]] = []
    current = (rows, cols)
    while current != (0, 0):
        path.append((current[0] - 1, current[1] - 1))
        current = parent[current]
    return list(reversed(path))


def _quality(error: float, coverage: float) -> int:
    # 0.20 shoulder-width is deliberately a soft dissimilarity scale.
    value = 100.0 * math.exp(-error / 0.20) * min(1.0, coverage / 0.98)
    score = max(0, min(3, round(value * 3 / 100)))
    # A detector gap is observable uncertainty, never evidence of a flawless
    # execution.  Keep a usable short gap comparable, but do not award 3/3.
    return min(score, 2) if coverage < 0.98 else score


def _level(total: int) -> str:
    return "beginning" if total <= 3 else "developing" if total <= 6 else "competent" if total <= 9 else "proficient" if total <= 11 else "mastered"


def _release_catch_similarity(
    expected: Sequence[PropEvent],
    observed: Sequence[PropEvent],
    expected_duration_ms: int,
    observed_duration_ms: int,
) -> tuple[float, float]:
    """Compare generic release/airborne/apex/catch order and relative timing."""
    relevant = {"release", "airborne", "apex", "catch"}
    left = [event for event in expected if event.kind in relevant]
    right = [event for event in observed if event.kind in relevant]
    if not left:
        return 1.0, 1.0
    if not right:
        return 0.0, 0.0

    # Longest-common-subsequence matching preserves repeated generic events
    # without inventing a movement-name-specific state machine.
    rows, cols = len(left), len(right)
    lengths = [[0] * (cols + 1) for _ in range(rows + 1)]
    for i in range(1, rows + 1):
        for j in range(1, cols + 1):
            if left[i - 1].kind == right[j - 1].kind:
                lengths[i][j] = lengths[i - 1][j - 1] + 1
            else:
                lengths[i][j] = max(lengths[i - 1][j], lengths[i][j - 1])
    matches: list[tuple[PropEvent, PropEvent]] = []
    i, j = rows, cols
    while i and j:
        if left[i - 1].kind == right[j - 1].kind:
            matches.append((left[i - 1], right[j - 1]))
            i -= 1
            j -= 1
        elif lengths[i - 1][j] >= lengths[i][j - 1]:
            i -= 1
        else:
            j -= 1
    matches.reverse()

    coverage = len(matches) / max(rows, cols)
    if not matches:
        return 0.0, 0.0
    timing_error = sum(
        abs(
            expected_event.timestamp_ms / max(1, expected_duration_ms)
            - observed_event.timestamp_ms / max(1, observed_duration_ms)
        )
        for expected_event, observed_event in matches
    ) / len(matches)
    return coverage * math.exp(-timing_error / 0.20), coverage


def compare_sequence(template: MovementTemplate, samples: Sequence[FrameSample]) -> SequenceComparison:
    """Compare captured measurements with a template using modality-masked DTW.

    Missing observations lower coverage and cannot yield a perfect component.
    ``total`` is a bounded 0..12 projection of five 0..3 components, allowing
    existing rubric consumers to display it without mixing it with legacy %.
    """
    validation = validate_sequence(
        samples,
        template.required_modalities,
        required_hand_sides=template.required_hand_sides,
        require_rotation=template.rotation_trace is not None,
    )
    names = ("Body technique", "Hand technique", "Prop path", "Timing", "Control/stability")
    scores: dict[str, int | None] = {name: None for name in names}
    confidence = {name: 0.0 for name in names}
    if not validation.valid:
        return SequenceComparison(scores, confidence, 0, _level(0), validation)
    candidate = normalize_sequence(
        samples,
        use_pose_anchor="pose" in template.required_modalities,
        required_hand_sides=template.required_hand_sides,
    )
    path_modalities = [m for m, capable in (("pose", template.feature_capabilities.get("pose")), ("hands", template.feature_capabilities.get("hands")), ("prop_translation", template.feature_capabilities.get("prop_translation"))) if capable]
    path = _dtw(template.canonical_sequence, candidate, path_modalities)
    component_for = {"Body technique": "pose", "Hand technique": "hands", "Prop path": "prop_translation"}
    for name, modality in component_for.items():
        if modality not in path_modalities:
            continue
        errors = [_modality_error(template.canonical_sequence[i], candidate[j], modality) for i, j in path]
        usable = [value for value in errors if value is not None]
        if modality == "hands" and template.required_hand_sides:
            coverage = min(
                _coverage(samples, modality, hand_side=side)[0]
                for side in template.required_hand_sides
            )
        else:
            coverage, _ = _coverage(samples, modality)
        if usable:
            confidence[name] = coverage
            scores[name] = _quality(sum(usable) / len(usable), coverage)
    duration = samples[-1].timestamp_ms - samples[0].timestamp_ms
    if duration > 0:
        ratio_error = abs(math.log(duration / max(1, template.duration_ms)))
        duration_score = max(0, min(3, round(3 * math.exp(-ratio_error / 0.7))))
        if template.feature_capabilities.get("release_catch"):
            event_similarity, event_coverage = _release_catch_similarity(
                template.prop_events,
                detect_prop_events(candidate),
                template.duration_ms,
                duration,
            )
            event_score = max(0, min(3, round(3 * event_similarity)))
            confidence["Timing"] = event_coverage
            scores["Timing"] = (
                min(duration_score, event_score)
                if event_coverage < 1.0
                else max(0, min(3, round((duration_score + 2 * event_score) / 3)))
            )
        else:
            confidence["Timing"] = 1.0
            scores["Timing"] = duration_score
    if "prop_translation" in path_modalities:
        prop_errors = [_modality_error(template.canonical_sequence[i], candidate[j], "prop_translation") for i, j in path]
        usable = [value for value in prop_errors if value is not None]
        coverage, _ = _coverage(samples, "prop_translation")
        if usable:
            # Path error already captures jitter/velocity through the temporal trace.
            confidence["Control/stability"] = coverage
            scores["Control/stability"] = _quality(sum(usable) / len(usable), coverage)
    if template.rotation_trace is not None:
        rotation = _rotation_trace(samples)
        rotation_path = _dtw_angles(template.rotation_trace.angles_rad, rotation.angles_rad)
        aligned_errors = [
            abs(expected - observed)
            for i, j in rotation_path
            if (expected := template.rotation_trace.angles_rad[i]) is not None
            and (observed := rotation.angles_rad[j]) is not None
        ]
        alignment_coverage = len(aligned_errors) / max(len(rotation_path), 1)
        evidence = min(rotation.coverage, rotation.pair_coverage, alignment_coverage)
        if aligned_errors:
            # Rotation changes both the prop-path and control components, but
            # public component names and the 0..12 total remain unchanged.
            # Total signed angle catches equal-start/end one-vs-two-turn cases;
            # aligned progression catches opposite direction and timing.
            total_error = abs(rotation.total_signed_rad - template.rotation_trace.total_signed_rad)
            progression_error = sum(aligned_errors) / len(aligned_errors)
            similarity = math.exp(-total_error / (0.65 * math.pi) - progression_error / (0.65 * math.pi))
            rotation_score = min(3, round(3 * similarity * evidence))
            for name in ("Prop path", "Control/stability"):
                scores[name] = min(scores[name] if scores[name] is not None else 0, rotation_score)
                confidence[name] = min(confidence[name], evidence)
    numeric = [score if score is not None else 0 for score in scores.values()]
    total = max(0, min(12, round(sum(numeric) * 12 / 15)))
    return SequenceComparison(scores, confidence, total, _level(total), validation)
