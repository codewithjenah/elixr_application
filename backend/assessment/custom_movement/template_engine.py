"""Deterministic custom-movement sequence capture and comparison.

Only detector measurements are accepted: no images, user code, rotation
estimates, or movement-name-specific rules are stored here.  Coordinates are
normalised around the body and shoulder scale while retaining left/right keys.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
import math
from typing import Any, Iterable, Mapping, Sequence


SCHEMA_VERSION = 1
CAPTURE_VERSION = 1
CANONICAL_FRAMES = 32
MIN_FRAMES = 8
MIN_COVERAGE = 0.70
MAX_TRACK_GAP = 2
EPSILON = 1e-6
SUPPORTED_MODALITIES = frozenset({"pose", "hands", "prop_translation"})
SUPPORTED_CAPABILITIES = frozenset(
    {"pose", "hands", "prop_translation", "release_catch", "prop_rotation"}
)


class FailureCode(str, Enum):
    INVALID_SCHEMA = "invalid_schema"
    MISSING_MODALITY = "missing_modality"
    INSUFFICIENT_FRAMES = "insufficient_frames"
    TRACK_LOSS = "track_loss"
    INVALID_REFERENCE_COUNT = "invalid_reference_count"
    INVALID_TIMESTAMPS = "invalid_timestamps"


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

    def to_dict(self) -> dict[str, Any]:
        return {
            "timestamp_ms": self.timestamp_ms,
            "pose": {str(k): v.to_dict() for k, v in self.pose.items()},
            "hands": {str(k): v.to_dict() for k, v in self.hands.items()},
            "prop": self.prop.to_dict() if self.prop else None,
            "prop_metadata": dict(self.prop_metadata),
        }

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any]) -> "FrameSample":
        prop = raw.get("prop")
        return cls(
            timestamp_ms=int(raw["timestamp_ms"]),
            pose={str(k): Landmark.from_dict(v) for k, v in raw.get("pose", {}).items()},
            hands={str(k): Landmark.from_dict(v) for k, v in raw.get("hands", {}).items()},
            prop=Landmark.from_dict(prop) if isinstance(prop, Mapping) else None,
            prop_metadata=dict(raw.get("prop_metadata", {})),
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

    def to_dict(self) -> dict[str, Any]:
        return {
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

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any]) -> "MovementTemplate":
        try:
            if set(raw) != {
                "schema_version", "capture_version", "duration_ms",
                "reference_count", "required_modalities",
                "normalization_metadata", "feature_capabilities",
                "canonical_sequence", "variability_metadata", "prop_events",
            }:
                raise ValueError("unexpected custom movement template fields")
            if int(raw["schema_version"]) != SCHEMA_VERSION or int(raw["capture_version"]) != CAPTURE_VERSION:
                raise ValueError("unsupported custom movement template schema")
            raw_capabilities = raw["feature_capabilities"]
            if set(raw_capabilities) != SUPPORTED_CAPABILITIES or any(
                not isinstance(value, bool) for value in raw_capabilities.values()
            ):
                raise ValueError("invalid feature capabilities")
            capabilities = dict(raw_capabilities)
            # Prop rotation must never be inferred from an axis-aligned detector box.
            if capabilities.get("prop_rotation", False):
                raise ValueError("prop rotation is not supported")
            template = cls(
                schema_version=int(raw["schema_version"]), capture_version=int(raw["capture_version"]),
                duration_ms=int(raw["duration_ms"]), reference_count=int(raw["reference_count"]),
                required_modalities=tuple(str(v) for v in raw["required_modalities"]),
                normalization_metadata=dict(raw["normalization_metadata"]),
                feature_capabilities=capabilities,
                canonical_sequence=tuple(FrameSample.from_dict(v) for v in raw["canonical_sequence"]),
                variability_metadata={str(k): float(v) for k, v in raw["variability_metadata"].items()},
                prop_events=tuple(PropEvent.from_dict(v) for v in raw.get("prop_events", [])),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(FailureCode.INVALID_SCHEMA.value) from exc
        if (
            template.reference_count < 3
            or len(template.canonical_sequence) != CANONICAL_FRAMES
            or not set(template.required_modalities).issubset(SUPPORTED_MODALITIES)
            or not template.required_modalities
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


def _coverage(samples: Sequence[FrameSample], modality: str) -> tuple[float, int]:
    present: list[bool] = []
    for frame in samples:
        if modality == "pose":
            present.append(any(_usable(p) for p in frame.pose.values()))
        elif modality == "hands":
            present.append(any(_usable(p) for p in frame.hands.values()))
        else:
            present.append(_usable(frame.prop))
    longest = current = 0
    for item in present:
        current = current + 1 if not item else 0
        longest = max(longest, current)
    return sum(present) / len(samples) if samples else 0.0, longest


def validate_sequence(samples: Sequence[FrameSample], required_modalities: Iterable[str]) -> ValidationResult:
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
        coverage, gap = _coverage(samples, modality)
        if coverage < MIN_COVERAGE:
            codes.append(FailureCode.MISSING_MODALITY)
        if gap > MAX_TRACK_GAP:
            codes.append(FailureCode.TRACK_LOSS)
    return ValidationResult(not codes, tuple(dict.fromkeys(codes)))


def _anchor_and_scale(frame: FrameSample) -> tuple[Landmark, float]:
    left = frame.pose.get("11") or frame.pose.get("left_shoulder")
    right = frame.pose.get("12") or frame.pose.get("right_shoulder")
    if _usable(left) and _usable(right):
        assert left is not None and right is not None
        scale = math.hypot(left.x - right.x, left.y - right.y)
        if scale > EPSILON:
            return Landmark((left.x + right.x) / 2, (left.y + right.y) / 2), scale
    usable_hands = [p for p in frame.hands.values() if _usable(p)]
    if usable_hands:
        anchor = usable_hands[0]
        return Landmark(anchor.x, anchor.y), 1.0
    return Landmark(0.0, 0.0), 1.0


def _normalise_point(point: Landmark | None, anchor: Landmark, scale: float) -> Landmark | None:
    if not _usable(point):
        return None
    assert point is not None
    return Landmark((point.x - anchor.x) / scale, (point.y - anchor.y) / scale, point.confidence)


def normalize_sequence(samples: Sequence[FrameSample]) -> tuple[FrameSample, ...]:
    """Remove image translation/body scale without mirroring laterality."""
    output: list[FrameSample] = []
    for frame in samples:
        anchor, scale = _anchor_and_scale(frame)
        metadata = dict(frame.prop_metadata)
        for key in ("bbox_width", "bbox_height", "velocity_x", "velocity_y"):
            value = metadata.get(key)
            if isinstance(value, (int, float)) and math.isfinite(float(value)):
                metadata[key] = float(value) / scale
        output.append(FrameSample(
            timestamp_ms=frame.timestamp_ms,
            pose={k: p for k, v in frame.pose.items() if (p := _normalise_point(v, anchor, scale))},
            hands={k: p for k, v in frame.hands.items() if (p := _normalise_point(v, anchor, scale))},
            prop=_normalise_point(frame.prop, anchor, scale),
            prop_metadata=metadata,
        ))
    return tuple(output)


def _interpolate(a: Landmark | None, b: Landmark | None, amount: float) -> Landmark | None:
    if not _usable(a) or not _usable(b):
        return a if amount < 0.5 else b
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


def _mean_points(points: Sequence[Landmark | None]) -> Landmark | None:
    valid = [p for p in points if _usable(p)]
    if not valid:
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


def build_template(references: Sequence[Sequence[FrameSample]], required_modalities: Iterable[str]) -> MovementTemplate:
    """Build a stable canonical template from at least three valid captures."""
    if len(references) < 3:
        raise ValueError(FailureCode.INVALID_REFERENCE_COUNT.value)
    required = tuple(sorted(set(required_modalities)))
    normalised: list[tuple[FrameSample, ...]] = []
    durations: list[int] = []
    for reference in references:
        check = validate_sequence(reference, required)
        if not check.valid:
            raise ValueError(",".join(code.value for code in check.codes))
        normalised.append(normalize_sequence(reference))
        durations.append(reference[-1].timestamp_ms - reference[0].timestamp_ms)
    resampled = [_resample(seq) for seq in normalised]
    canonical: list[FrameSample] = []
    for index in range(CANONICAL_FRAMES):
        frames = [sequence[index] for sequence in resampled]
        pose_keys = set().union(*(frame.pose.keys() for frame in frames))
        hand_keys = set().union(*(frame.hands.keys() for frame in frames))
        canonical.append(FrameSample(
            timestamp_ms=round(sum(durations) / len(durations) * index / (CANONICAL_FRAMES - 1)),
            pose={key: point for key in sorted(pose_keys) if (point := _mean_points([frame.pose.get(key) for frame in frames]))},
            hands={key: point for key in sorted(hand_keys) if (point := _mean_points([frame.hands.get(key) for frame in frames]))},
            prop=_mean_points([frame.prop for frame in frames]),
            prop_metadata=_canonical_prop_metadata(frames),
        ))
    prop_coverage = sum(frame.prop is not None for frame in canonical) / CANONICAL_FRAMES
    prop_events = detect_prop_events(canonical)
    event_kinds = {event.kind for event in prop_events}
    has_release_catch = {"release", "catch"}.issubset(event_kinds)
    return MovementTemplate(
        schema_version=SCHEMA_VERSION, capture_version=CAPTURE_VERSION,
        duration_ms=round(sum(durations) / len(durations)), reference_count=len(references),
        required_modalities=required,
        normalization_metadata={"anchor": "shoulder_midpoint", "scale": "shoulder_width", "mirrored": False},
        feature_capabilities={"pose": "pose" in required, "hands": "hands" in required, "prop_translation": prop_coverage >= MIN_COVERAGE, "release_catch": has_release_catch, "prop_rotation": False},
        canonical_sequence=tuple(canonical),
        variability_metadata={"duration_std_ms": _std(durations), "reference_count": float(len(references))},
        prop_events=prop_events,
    )


def _std(values: Sequence[float]) -> float:
    mean = sum(values) / len(values)
    return math.sqrt(sum((value - mean) ** 2 for value in values) / len(values))


def _point_distance(a: Landmark | None, b: Landmark | None) -> float | None:
    if not _usable(a) or not _usable(b):
        return None
    assert a is not None and b is not None
    return math.hypot(a.x - b.x, a.y - b.y)


def _modality_error(a: FrameSample, b: FrameSample, modality: str) -> float | None:
    if modality == "prop_translation":
        return _point_distance(a.prop, b.prop)
    left = a.pose if modality == "pose" else a.hands
    right = b.pose if modality == "pose" else b.hands
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
    validation = validate_sequence(samples, template.required_modalities)
    names = ("Body technique", "Hand technique", "Prop path", "Timing", "Control/stability")
    scores: dict[str, int | None] = {name: None for name in names}
    confidence = {name: 0.0 for name in names}
    if not validation.valid:
        return SequenceComparison(scores, confidence, 0, _level(0), validation)
    candidate = normalize_sequence(samples)
    path_modalities = [m for m, capable in (("pose", template.feature_capabilities.get("pose")), ("hands", template.feature_capabilities.get("hands")), ("prop_translation", template.feature_capabilities.get("prop_translation"))) if capable]
    path = _dtw(template.canonical_sequence, candidate, path_modalities)
    component_for = {"Body technique": "pose", "Hand technique": "hands", "Prop path": "prop_translation"}
    for name, modality in component_for.items():
        if modality not in path_modalities:
            continue
        errors = [_modality_error(template.canonical_sequence[i], candidate[j], modality) for i, j in path]
        usable = [value for value in errors if value is not None]
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
    numeric = [score if score is not None else 0 for score in scores.values()]
    total = max(0, min(12, round(sum(numeric) * 12 / 15)))
    return SequenceComparison(scores, confidence, total, _level(total), validation)
