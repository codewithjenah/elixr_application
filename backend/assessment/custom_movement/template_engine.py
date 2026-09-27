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
STATIC_SCHEMA_VERSION = 3
STATIC_HOLD_MS = 800
# Normalized distances below are shoulder widths when Pose anchors the frame.
# Static matching ranks evidence: hand/grip shape (wrist-relative) is strict,
# relevant arm pose is secondary, and the prop only has to stay broadly placed
# so ordinary YOLO centre jitter cannot veto a correct grip.
STATIC_STABILITY_TOLERANCE = 0.16  # final-observation stillness
STATIC_REFERENCE_MATCH_RATIO = 0.85  # same agreement ratio as live assessment
STATIC_HAND_KEYPOINT_TOLERANCE = 0.15
STATIC_HAND_POSITION_TOLERANCE = 0.20
STATIC_POSE_TOLERANCE = 0.20
STATIC_PROP_TOLERANCE = 0.25
# A static reference is hand-led when a well-tracked hand touches the learned
# prop box (expanded by this many palm lengths). Its grip and hand-to-prop
# relation are then compared in a wrist-local frame, so arm/body geometry is
# observed but never vetoes a correct grip. Otherwise pose stays technique.
STATIC_GRIP_MIN_HAND_KEYPOINTS = 5
STATIC_GRIP_CONTACT_MARGIN = 0.5
CAPTURE_VERSION = 1
CANONICAL_FRAMES = 32
MIN_FRAMES = 8
MIN_COVERAGE = 0.70
MAX_TRACK_GAP = 2
# Live detector losses are measured in elapsed time. Reference recording now
# uses the same elapsed-time policy (see REFERENCE_MAX_GAP_MS).
ASSESSMENT_MAX_TRACK_GAP_MS = 450
ASSESSMENT_MAX_FRAME_INTERVAL_MS = 700
POSE_MOTION_THRESHOLD = 0.08
# Reference authoring. The custom-capture AI loop is unthrottled, so its sample
# cadence is inference-bound (roughly 5-15 Hz on target laptops). Wall-clock
# clip duration and processed sample count are therefore checked separately.
MIN_STATIC_REFERENCES = 1
MIN_DYNAMIC_REFERENCES = 2
MIN_REFERENCE_DURATION_MS = 1000  # holds the 800 ms static ending plus lead-in
MIN_TRACKING_SAMPLES = 6  # 1 s at >= 6 Hz
MIN_STATIC_HOLD_SAMPLES = 4  # 800 ms at >= 5 Hz (window includes boundary)
REFERENCE_MIN_PROP_COVERAGE = 0.60
REFERENCE_MAX_GAP_MS = ASSESSMENT_MAX_TRACK_GAP_MS
REFERENCE_MAX_PROP_GAP_MS = 800
# Meaningful dynamic motion, in shoulder widths. Converted to each template's
# own coordinate units with ``motion_unit`` so hand-anchored templates are not
# judged against pose-anchored numbers.
MEANINGFUL_MOTION_THRESHOLD = 0.05
PROP_MOTION_THRESHOLD = 0.08
NOMINAL_SHOULDER_WIDTH = 0.30  # image fraction, used only if shoulders unseen
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
    INSUFFICIENT_HAND_COVERAGE = "insufficient_hand_coverage"
    INSUFFICIENT_ORIENTATION = "insufficient_orientation"
    REFERENCE_DURATION_TOO_SHORT = "reference_duration_too_short"
    INSUFFICIENT_TRACKING_SAMPLES = "insufficient_tracking_samples"
    INSUFFICIENT_PROP_COVERAGE = "insufficient_prop_coverage"
    EXCESSIVE_TRACKING_GAP = "excessive_tracking_gap"
    NO_MEANINGFUL_MOTION = "no_meaningful_motion"
    INCONSISTENT_DYNAMIC_REFERENCES = "inconsistent_dynamic_references"
    UNSTABLE_STATIC_REFERENCE = "unstable_static_reference"
    INCONSISTENT_STATIC_REFERENCES = "inconsistent_static_references"


class ReferenceQualityError(ValueError):
    """A reference-authoring rejection with user-facing measured values.

    ``str(error)`` is the failure code so existing ``ValueError`` handlers keep
    returning the same ``error_code``; ``details`` carries the measurements.
    """

    def __init__(self, code: FailureCode, details: Mapping[str, Any] | None = None):
        super().__init__(code.value)
        self.code = code.value
        self.details: dict[str, Any] = {"reason": code.value, **dict(details or {})}


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


def trailing_hold_window(samples: Sequence[FrameSample]) -> tuple[FrameSample, ...]:
    """Include the observation crossing the hold boundary at any camera FPS."""
    if not samples:
        return ()
    cutoff = samples[-1].timestamp_ms - STATIC_HOLD_MS
    start = len(samples) - 1
    while start > 0 and samples[start - 1].timestamp_ms >= cutoff:
        start -= 1
    return tuple(samples[max(0, start - 1):])


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
    movement_behavior: str = "dynamic"

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
        if self.schema_version >= STATIC_SCHEMA_VERSION:
            result["movement_behavior"] = self.movement_behavior
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
            if version >= 2:
                expected.add("rotation_trace")
            if version == STATIC_SCHEMA_VERSION:
                expected.add("movement_behavior")
            if set(raw) != expected:
                raise ValueError("unexpected custom movement template fields")
            if version not in {1, SCHEMA_VERSION, STATIC_SCHEMA_VERSION} or int(raw["capture_version"]) != CAPTURE_VERSION:
                raise ValueError("unsupported custom movement template schema")
            behavior = raw.get("movement_behavior", "dynamic")
            if behavior not in {"static", "dynamic"} or (version == STATIC_SCHEMA_VERSION and behavior != "static"):
                raise ValueError("invalid movement behavior")
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
                version >= 2 and isinstance(raw.get("rotation_trace"), Mapping)
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
                movement_behavior=behavior,
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise ValueError(FailureCode.INVALID_SCHEMA.value) from exc
        if (
            template.reference_count < minimum_references(template.movement_behavior)
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
    rotation_diagnostics: Mapping[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "component_scores": dict(self.component_scores),
            "component_confidence": dict(self.component_confidence),
            "total": self.total,
            "performance_level": self.performance_level,
            "validation_codes": [code.value for code in self.validation.codes],
        }


def minimum_references(movement_behavior: str) -> int:
    """One held example teaches a static pose; dynamic uses two for noise."""
    return MIN_STATIC_REFERENCES if movement_behavior == "static" else MIN_DYNAMIC_REFERENCES


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


def _presence(
    samples: Sequence[FrameSample], modality: str, *, hand_side: str | None = None
) -> list[bool]:
    return [_coverage((frame,), modality, hand_side=hand_side)[0] == 1.0 for frame in samples]


def _longest_gap_ms(samples: Sequence[FrameSample], present: Sequence[bool]) -> int:
    """Elapsed unobserved time, matching the live assessment gap rule."""
    if not samples:
        return 0
    if not any(present):
        return samples[-1].timestamp_ms - samples[0].timestamp_ms
    longest = 0
    last_seen: int | None = None
    missing = False
    for frame, observed in zip(samples, present):
        if observed:
            origin = last_seen if last_seen is not None else samples[0].timestamp_ms
            if missing:
                longest = max(longest, frame.timestamp_ms - origin)
            last_seen = frame.timestamp_ms
            missing = False
        else:
            missing = True
    if missing and last_seen is not None:
        longest = max(longest, samples[-1].timestamp_ms - last_seen)
    return longest


def reference_quality(
    samples: Sequence[FrameSample],
    *,
    clip_duration_ms: int | None = None,
    movement_behavior: str = "dynamic",
) -> dict[str, Any]:
    """Beginner-facing measurements for one reference recording.

    Wall-clock clip duration, processed-sample span, sample count, per-input
    coverage and the longest prop gap are reported independently.
    """
    span = samples[-1].timestamp_ms - samples[0].timestamp_ms if len(samples) > 1 else 0
    left = _coverage(samples, "hands", hand_side="left")[0]
    right = _coverage(samples, "hands", hand_side="right")[0]
    static = movement_behavior == "static"
    hold = trailing_hold_window(samples) if static else ()
    return {
        "duration_ms": clip_duration_ms if clip_duration_ms is not None else span,
        "required_duration_ms": MIN_REFERENCE_DURATION_MS,
        "sample_duration_ms": span,
        "sample_count": len(samples),
        "required_sample_count": MIN_TRACKING_SAMPLES,
        "hold_sample_count": len(hold) if static else None,
        "required_hold_sample_count": MIN_STATIC_HOLD_SAMPLES if static else None,
        "hold_duration_ms": hold[-1].timestamp_ms - hold[0].timestamp_ms if hold else None,
        "hand_coverage": round(max(left, right), 3),
        "left_hand_coverage": round(left, 3),
        "right_hand_coverage": round(right, 3),
        "pose_coverage": round(_coverage(samples, "pose")[0], 3),
        "prop_coverage": round(_coverage(samples, "prop_translation")[0], 3),
        "required_prop_coverage": REFERENCE_MIN_PROP_COVERAGE,
        "longest_tracking_gap_ms": _longest_gap_ms(samples, _presence(samples, "prop_translation")),
        "maximum_tracking_gap_ms": REFERENCE_MAX_PROP_GAP_MS,
        "required_hold_ms": STATIC_HOLD_MS if static else None,
    }


def check_reference_integrity(
    samples: Sequence[FrameSample],
    *,
    clip_duration_ms: int | None = None,
    movement_behavior: str = "dynamic",
    reference_index: int | None = None,
) -> dict[str, Any]:
    """Behavior-independent integrity: duration, samples, prop evidence.

    Semantic checks (motion, stable hold, hand sides) need every reference
    and run in :func:`build_template`. Returns the measured quality.
    """
    quality = reference_quality(
        samples, clip_duration_ms=clip_duration_ms, movement_behavior=movement_behavior,
    )
    if reference_index is not None:
        quality["reference_index"] = reference_index
    if quality["duration_ms"] < MIN_REFERENCE_DURATION_MS:
        raise ReferenceQualityError(FailureCode.REFERENCE_DURATION_TOO_SHORT, quality)
    if len(samples) < MIN_TRACKING_SAMPLES:
        raise ReferenceQualityError(FailureCode.INSUFFICIENT_TRACKING_SAMPLES, quality)
    if quality["prop_coverage"] < REFERENCE_MIN_PROP_COVERAGE:
        raise ReferenceQualityError(FailureCode.INSUFFICIENT_PROP_COVERAGE, quality)
    if quality["longest_tracking_gap_ms"] > REFERENCE_MAX_PROP_GAP_MS:
        raise ReferenceQualityError(FailureCode.EXCESSIVE_TRACKING_GAP, quality)
    return quality


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


def validate_assessment_sequence(
    samples: Sequence[FrameSample],
    required_modalities: Iterable[str],
    *,
    required_hand_sides: Iterable[str] = (),
    template: MovementTemplate | None = None,
) -> ValidationResult:
    """Validate real live observations with the same cadence rules as authoring."""
    required = tuple(sorted(set(required_modalities)))
    codes: list[FailureCode] = []
    if not set(required).issubset(SUPPORTED_MODALITIES):
        codes.append(FailureCode.INVALID_SCHEMA)
    minimum_samples = (
        MIN_STATIC_HOLD_SAMPLES
        if template is not None and template.movement_behavior == "static"
        else MIN_TRACKING_SAMPLES
    )
    if len(samples) < minimum_samples:
        codes.append(FailureCode.INSUFFICIENT_FRAMES)
    timestamps = [frame.timestamp_ms for frame in samples]
    if any(not isinstance(ts, int) for ts in timestamps) or any(
        b <= a for a, b in zip(timestamps, timestamps[1:])
    ):
        codes.append(FailureCode.INVALID_TIMESTAMPS)
    if any(b - a > ASSESSMENT_MAX_FRAME_INTERVAL_MS for a, b in zip(timestamps, timestamps[1:])):
        codes.append(FailureCode.TRACK_LOSS)
    for modality in required:
        sides = tuple(sorted(set(required_hand_sides))) if modality == "hands" else (None,)
        for side in sides or (None,):
            expected: Mapping[str, Landmark] = {}
            if template is not None and modality in {"pose", "hands"}:
                target = template.canonical_sequence[-1]
                if modality == "pose":
                    meaningful = {key: point for key, point in target.pose.items()
                                  if key in MEANINGFUL_POSE_KEYS}
                    expected = meaningful or target.pose
                else:
                    semantic = _semantic_hands(target.hands)
                    expected = {key: point for key, point in semantic.items()
                                if side is None or _hand_side(key) == side}
            if expected:
                minimum = max(1, math.ceil(len(expected) * 0.5))
                present = []
                for frame in samples:
                    observed = frame.pose if modality == "pose" else _semantic_hands(frame.hands)
                    present.append(sum(
                        _usable(observed.get(key)) for key in expected
                    ) >= minimum)
            else:
                present = [
                    _coverage((frame,), modality, hand_side=side)[0] == 1.0
                    for frame in samples
                ]
            coverage = sum(present) / len(samples) if samples else 0.0
            if coverage < MIN_COVERAGE:
                codes.append(FailureCode.MISSING_MODALITY)
            last_seen: int | None = None
            missing = False
            for frame, observed in zip(samples, present):
                if observed:
                    if missing and last_seen is not None and frame.timestamp_ms - last_seen > ASSESSMENT_MAX_TRACK_GAP_MS:
                        codes.append(FailureCode.TRACK_LOSS)
                    last_seen = frame.timestamp_ms
                    missing = False
                else:
                    missing = True
                    if frame.timestamp_ms - (last_seen if last_seen is not None else samples[0].timestamp_ms) > ASSESSMENT_MAX_TRACK_GAP_MS:
                        codes.append(FailureCode.TRACK_LOSS)
            if samples and last_seen is None:
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


class PropEventTracker:
    """Incremental observed-event tracker shared by live cues and batch scoring."""

    def __init__(self) -> None:
        self.contact_run = 0
        self.held = False
        self.released = False
        self.airborne = False
        self.away_run = 0
        self.release_y: float | None = None
        self.prior_prop: Landmark | None = None
        self.prior_hands: Mapping[str, Landmark] = {}
        self.prior_timestamp: int | None = None
        self.prior_track_id: Any = None
        self.prior_velocity: float | None = None

    def update(self, frame: FrameSample) -> tuple[PropEvent, ...]:
        """Return only events verified by this current detector observation."""
        events: list[PropEvent] = []
        prop = frame.prop if _usable(frame.prop) else None
        hands = {key: hand for key, hand in frame.hands.items() if _usable(hand)}
        if prop is None:
            # Unknown prop location cannot establish release, flight, or catch.
            self.prior_prop = None
            self.prior_velocity = None
            self.held = False
            # One earlier contact may contribute only if the prop returns
            # near the hand promptly; reacquisition away cannot be a release.
            self.contact_run = min(self.contact_run, 1)
            return ()
        closest_key = min(
            hands,
            key=lambda key: math.hypot(prop.x - hands[key].x, prop.y - hands[key].y),
            default=None,
        )
        distance = (
            math.hypot(prop.x - hands[closest_key].x, prop.y - hands[closest_key].y)
            if closest_key is not None else float("inf")
        )
        track_id = frame.prop_metadata.get("track_id")
        previous_prop = self.prior_prop
        if (self.prior_timestamp is not None
                and frame.timestamp_ms - self.prior_timestamp > 250):
            # A new visible location after a long unknown interval cannot
            # establish the transition from the old held/flight state.
            self.held = self.released = self.airborne = False
            self.contact_run = 0
            self.away_run = 0
            self.release_y = None
            self.prior_velocity = None
        if (self.prior_prop is not None and track_id is not None
                and self.prior_track_id is not None and track_id != self.prior_track_id):
            # An identity switch is not evidence that the held prop moved.
            self.held = self.released = self.airborne = False
            self.contact_run = 0
            self.away_run = 0
            self.release_y = None
            self.prior_velocity = None
        continuous = (
            self.prior_prop is not None
            and self.prior_timestamp is not None
            and 0 < frame.timestamp_ms - self.prior_timestamp <= 250
            and (track_id is None or self.prior_track_id is None or track_id == self.prior_track_id)
        )
        speed = 0.0
        relative_speed = 0.0
        if continuous:
            assert self.prior_prop is not None and self.prior_timestamp is not None
            dt = frame.timestamp_ms - self.prior_timestamp
            speed = math.hypot(prop.x - self.prior_prop.x, prop.y - self.prior_prop.y) / dt
            vertical_velocity = (prop.y - self.prior_prop.y) / dt
            if self.airborne and self.prior_velocity is not None and self.prior_velocity < 0 <= vertical_velocity:
                events.append(PropEvent(frame.timestamp_ms, "apex"))
            self.prior_velocity = vertical_velocity
            if closest_key is not None and closest_key in self.prior_hands:
                hand = hands[closest_key]
                previous_hand = self.prior_hands[closest_key]
                relative_speed = math.hypot(
                    (prop.x - hand.x) - (self.prior_prop.x - previous_hand.x),
                    (prop.y - hand.y) - (self.prior_prop.y - previous_hand.y),
                ) / dt
            else:
                relative_speed = speed
        else:
            self.prior_velocity = None
        self.prior_timestamp = frame.timestamp_ms
        self.prior_prop = prop
        self.prior_hands = hands
        self.prior_track_id = track_id
        near_and_slow = distance <= 0.25 and relative_speed <= 0.0015
        self.contact_run = self.contact_run + 1 if near_and_slow else 0
        if self.contact_run == 2:
            events.append(PropEvent(frame.timestamp_ms, "stable_contact"))
            if self.airborne:
                events.append(PropEvent(frame.timestamp_ms, "catch"))
                self.airborne = False
                self.released = False
                self.held = True
                self.away_run = 0
                self.release_y = None
            elif self.released:
                # A released prop that never showed flight is simply back in
                # contact; do not invent an airborne catch.
                self.released = False
                self.held = True
                self.away_run = 0
                self.release_y = None
            else:
                events.append(PropEvent(frame.timestamp_ms, "contact"))
                self.held = True
        if self.held and closest_key is not None and distance > 0.25:
            events.append(PropEvent(frame.timestamp_ms, "release"))
            self.held = False
            self.released = True
            self.away_run = 1
            self.release_y = previous_prop.y if previous_prop is not None else prop.y
        elif self.released and closest_key is not None and distance > 0.25:
            self.away_run = self.away_run + 1 if continuous else 1
        if (self.released and not self.airborne and closest_key is not None
                and distance > 0.25 and continuous and self.away_run >= 2
                and self.release_y is not None and abs(prop.y - self.release_y) >= 0.02
                and speed > 0.0015):
            events.append(PropEvent(frame.timestamp_ms, "airborne"))
            self.airborne = True
        return tuple(events)


def detect_prop_events(samples: Sequence[FrameSample]) -> tuple[PropEvent, ...]:
    """Infer only observed contact, release, flight and catch evidence."""
    tracker = PropEventTracker()
    events: list[PropEvent] = []
    for frame in samples:
        events.extend(tracker.update(frame))
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
    *, movement_behavior: str = "dynamic",
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    hand_sides = tuple(
        side
        for side in ("left", "right")
        if all(_reliable(reference, "hands", hand_side=side) for reference in references)
    )
    meaningful_pose_count = sum(
        _pose_motion(reference) >= POSE_MOTION_THRESHOLD for reference in references
    )
    required = ["prop_translation"]
    if hand_sides:
        required.append("hands")
    if _pose_reliable(references) and (
        movement_behavior == "static"
        or meaningful_pose_count >= min(2, len(references))
    ):
        required.append("pose")
    return tuple(sorted(required)), hand_sides


def _reliable(
    reference: Sequence[FrameSample], modality: str, *, hand_side: str | None = None
) -> bool:
    return (
        _coverage(reference, modality, hand_side=hand_side)[0] >= MIN_COVERAGE
        and _longest_gap_ms(reference, _presence(reference, modality, hand_side=hand_side))
        <= REFERENCE_MAX_GAP_MS
    )


def _pose_reliable(references: Sequence[Sequence[FrameSample]]) -> bool:
    return all(_reliable(reference, "pose") for reference in references)


def _median(values: Sequence[float]) -> float:
    ordered = sorted(values)
    middle = len(ordered) // 2
    return ordered[middle] if len(ordered) % 2 else (ordered[middle - 1] + ordered[middle]) / 2


def _smoothed_range(points: Sequence[Landmark]) -> float:
    """Farthest sustained displacement from the start of one landmark track.

    A 3-sample median rejects one-frame detector spikes, so displacement has
    to persist across consecutive observations before it counts as movement.
    """
    if len(points) < 3:
        return 0.0
    filtered = [
        Landmark(_median([p.x for p in points[i - 1:i + 2]]),
                 _median([p.y for p in points[i - 1:i + 2]]))
        for i in range(1, len(points) - 1)
    ]
    origin = filtered[0]
    return max(math.hypot(p.x - origin.x, p.y - origin.y) for p in filtered)


def sequence_motion(sequence: Sequence[FrameSample], modality: str) -> float:
    """Sustained normalized displacement of one modality (template units)."""
    if modality == "prop_translation":
        # A prop identity switch starts a new track instead of a jump.
        segments: list[list[Landmark]] = [[]]
        previous_track: Any = None
        for frame in sequence:
            if not _usable(frame.prop):
                continue
            track = frame.prop_metadata.get("track_id")
            if segments[-1] and track is not None and previous_track is not None and track != previous_track:
                segments.append([])
            segments[-1].append(frame.prop)  # type: ignore[arg-type]
            previous_track = track if track is not None else previous_track
        return max((_smoothed_range(segment) for segment in segments), default=0.0)
    tracks: dict[str, list[Landmark]] = {}
    for frame in sequence:
        points = frame.pose if modality == "pose" else _semantic_hands(frame.hands)
        for key, point in points.items():
            if (modality != "pose" or key in MEANINGFUL_POSE_KEYS) and _usable(point):
                tracks.setdefault(key, []).append(point)
    ranges = sorted(
        (_smoothed_range(points) for points in tracks.values() if len(points) >= 3),
        reverse=True,
    )
    # A grip transition moves only fingertips, and the anchor wrist never
    # moves in its own frame; average the most-moving quarter of landmarks.
    top = ranges[:max(1, len(ranges) // 4)]
    return sum(top) / len(top) if top else 0.0


def _units_per_shoulder(
    reference: Sequence[FrameSample],
    *,
    use_pose_anchor: bool,
    hand_sides: Iterable[str],
) -> float:
    """How many template-frame units one shoulder width spans."""
    sides = frozenset(hand_sides)
    ratios: list[float] = []
    scales: list[float] = []
    for frame in reference:
        hands = {k: p for k, p in _semantic_hands(frame.hands).items() if _hand_side(k) in sides}
        _, scale = _anchor_and_scale(frame, use_pose_anchor=use_pose_anchor, hands=hands)
        scales.append(scale)
        left = frame.pose.get("11") or frame.pose.get("left_shoulder")
        right = frame.pose.get("12") or frame.pose.get("right_shoulder")
        if _usable(left) and _usable(right):
            assert left is not None and right is not None
            width = math.hypot(left.x - right.x, left.y - right.y)
            if width > EPSILON:
                ratios.append(width / scale)
    if ratios:
        return _median(ratios)
    return NOMINAL_SHOULDER_WIDTH / _median(scales) if scales else 1.0


def motion_thresholds(motion_unit: float | None) -> dict[str, float]:
    """Per-modality meaningful-motion thresholds in template units.

    Legacy templates without ``motion_unit`` keep their original 0.08 rule.
    """
    if motion_unit is None:
        return {m: POSE_MOTION_THRESHOLD for m in SUPPORTED_MODALITIES}
    return {
        "hands": MEANINGFUL_MOTION_THRESHOLD * motion_unit,
        "pose": MEANINGFUL_MOTION_THRESHOLD * motion_unit,
        "prop_translation": PROP_MOTION_THRESHOLD * motion_unit,
    }


def _motion_evidence(
    reference: Sequence[FrameSample],
    required: Sequence[str],
    hand_sides: Sequence[str],
) -> tuple[dict[str, Any], float]:
    """OR-style movement evidence for one dynamic reference.

    Any one reliable signal is enough: hand shape/position, arm pose, prop
    path, an observed flight, or verified rotation. Values are reported in
    shoulder widths so the user-facing diagnostics are comparable.
    """
    use_pose = "pose" in required
    normalized = normalize_sequence(reference, use_pose_anchor=use_pose, required_hand_sides=hand_sides)
    unit = _units_per_shoulder(reference, use_pose_anchor=use_pose, hand_sides=hand_sides)
    thresholds = motion_thresholds(unit)
    signals: dict[str, Any] = {}
    moving: list[str] = []
    for modality in ("hands", "pose", "prop_translation"):
        if modality not in required:
            continue
        value = sequence_motion(normalized, modality)
        signals[modality] = round(value / unit, 3)
        if value >= thresholds[modality]:
            moving.append(modality)
    if any(event.kind == "airborne" for event in detect_prop_events(reference)):
        moving.append("release_catch")
    trace = _rotation_trace(reference)
    if (trace.coverage >= MIN_ROTATION_COVERAGE and trace.pair_coverage >= MIN_ROTATION_PAIR_COVERAGE
            and abs(trace.total_signed_rad) >= MIN_ROTATION_AMOUNT_RAD and _rotation_track_stable(reference)):
        moving.append("prop_rotation")
    signals["movement_signals"] = moving
    return signals, unit


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
    prop_minimum_presence: int | None = None,
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
            [frame.prop for frame in frames],
            min_count=minimum_presence if prop_minimum_presence is None else prop_minimum_presence,
        ),
        prop_metadata=_canonical_prop_metadata(frames),
    )


def _validate_reference(
    reference: Sequence[FrameSample],
    required: Sequence[str],
    hand_sides: Sequence[str],
    *,
    index: int,
    movement_behavior: str,
) -> None:
    """Per-reference observability with elapsed-time gaps and specific codes."""
    quality = {**reference_quality(reference, movement_behavior=movement_behavior),
               "reference_index": index}
    timestamps = [frame.timestamp_ms for frame in reference]
    if any(not isinstance(ts, int) for ts in timestamps) or any(
        b <= a for a, b in zip(timestamps, timestamps[1:])
    ):
        raise ReferenceQualityError(FailureCode.INVALID_TIMESTAMPS, quality)
    if quality["prop_coverage"] < REFERENCE_MIN_PROP_COVERAGE:
        raise ReferenceQualityError(FailureCode.INSUFFICIENT_PROP_COVERAGE, quality)
    if quality["longest_tracking_gap_ms"] > REFERENCE_MAX_PROP_GAP_MS:
        raise ReferenceQualityError(FailureCode.EXCESSIVE_TRACKING_GAP, quality)
    checks = [("hands", side) for side in hand_sides] + (
        [("pose", None)] if "pose" in required else []
    )
    for modality, side in checks:
        if _coverage(reference, modality, hand_side=side)[0] < MIN_COVERAGE:
            details = quality
            if modality == "hands" and side is not None:
                details = {**quality, "hand_side": side,
                           "hand_coverage": round(_coverage(reference, modality, hand_side=side)[0], 3)}
            raise ReferenceQualityError(
                FailureCode.INSUFFICIENT_HAND_COVERAGE if modality == "hands"
                else FailureCode.MISSING_MODALITY,
                details,
            )
        gap = _longest_gap_ms(reference, _presence(reference, modality, hand_side=side))
        if gap > REFERENCE_MAX_GAP_MS:
            raise ReferenceQualityError(
                FailureCode.EXCESSIVE_TRACKING_GAP, {**quality, "longest_tracking_gap_ms": gap},
            )


def _require_dynamic_motion(
    references: Sequence[Sequence[FrameSample]],
    required: tuple[str, ...],
    hand_sides: tuple[str, ...],
) -> tuple[tuple[str, ...], float, tuple[str, ...]]:
    """Every dynamic reference needs at least one sustained movement signal.

    A hand-anchored frame hides wrist/arm translation (the hand is its own
    origin). When the only movement is visible relative to the body and the
    upper body was tracked reliably, anchor on the shoulders instead of
    rejecting a genuine arm-led movement.
    """
    evidence = [_motion_evidence(r, required, hand_sides) for r in references]
    if (not all(signals["movement_signals"] for signals, _ in evidence)
            and "pose" not in required and _pose_reliable(references)):
        anchored = tuple(sorted((*required, "pose")))
        alternative = [_motion_evidence(r, anchored, hand_sides) for r in references]
        if all(signals["movement_signals"] for signals, _ in alternative):
            required, evidence = anchored, alternative
    for index, (signals, _) in enumerate(evidence):
        if not signals["movement_signals"]:
            raise ReferenceQualityError(FailureCode.NO_MEANINGFUL_MOTION, {
                **reference_quality(references[index]), **signals, "reference_index": index,
            })
    common = set(evidence[0][0]["movement_signals"])
    for signals, _ in evidence[1:]:
        common &= set(signals["movement_signals"])
    if not common:
        raise ReferenceQualityError(FailureCode.INCONSISTENT_DYNAMIC_REFERENCES, {
            "movement_signals_by_reference": [s["movement_signals"] for s, _ in evidence],
        })
    return required, _median([unit for _, unit in evidence]), tuple(sorted(common))


def _require_consistent_dynamic_references(
    resampled: Sequence[Sequence[FrameSample]],
    common_moving: Sequence[str],
    motion_unit: float,
) -> None:
    """Examples may differ in speed and detail, not in the learned action.

    After DTW phase alignment, an example whose aligned error is as large as
    the movement itself (in every shared moving modality) shows a different
    action. Event/rotation-only evidence has no path to compare here.
    """
    modalities = [m for m in common_moving if m in SUPPORTED_MODALITIES]
    if len(resampled) < 2 or not modalities:
        return
    floor = 0.15 * motion_unit
    for index, other in enumerate(resampled[1:], start=1):
        consistent = False
        for modality in modalities:
            scale = (sequence_motion(resampled[0], modality) + sequence_motion(other, modality)) / 2
            error = _sequence_distance(resampled[0], other, (modality,))
            if error <= max(floor, 0.75 * scale):
                consistent = True
                break
        if not consistent:
            raise ReferenceQualityError(FailureCode.INCONSISTENT_DYNAMIC_REFERENCES, {
                "reference_index": index, "movement_signals": list(common_moving),
            })


def build_template(
    references: Sequence[Sequence[FrameSample]],
    required_modalities: Iterable[str] | None = None,
    *, movement_behavior: str = "dynamic",
) -> MovementTemplate:
    """Build a canonical template: one held static example, or two dynamic.

    Raises :class:`ReferenceQualityError` (a ``ValueError``) with a specific
    code and measured values when a reference cannot teach the movement.
    """
    if movement_behavior not in {"static", "dynamic"}:
        raise ValueError(FailureCode.INVALID_SCHEMA.value)
    required_count = minimum_references(movement_behavior)
    if len(references) < required_count:
        raise ReferenceQualityError(FailureCode.INVALID_REFERENCE_COUNT, {
            "reference_count": len(references), "required_reference_count": required_count,
        })
    static = movement_behavior == "static"
    minimum_samples = MIN_STATIC_HOLD_SAMPLES if static else MIN_TRACKING_SAMPLES
    for index, reference in enumerate(references):
        quality = reference_quality(reference, movement_behavior=movement_behavior)
        span = quality["sample_duration_ms"]
        if (len(reference) < MIN_TRACKING_SAMPLES
                or (static and (span < STATIC_HOLD_MS
                                or len(trailing_hold_window(reference)) < minimum_samples))):
            raise ReferenceQualityError(
                FailureCode.INSUFFICIENT_TRACKING_SAMPLES, {**quality, "reference_index": index},
            )
    if static:
        references = tuple(trailing_hold_window(reference) for reference in references)
    # The caller may require a modality that capture explicitly promised.
    # Its details (including which hand side) are still inferred from samples.
    if required_modalities is not None and not set(required_modalities).issubset(
        SUPPORTED_MODALITIES
    ):
        raise ValueError(FailureCode.INVALID_SCHEMA.value)
    required, hand_sides = _infer_requirements(references, movement_behavior=movement_behavior)
    # Capture readiness guarantees a hand at the start, but intermittent
    # tracking must not turn a hand-led demonstration into a path-only model.
    # A single reliable side is enough; never impose a two-hand requirement.
    def weakest_hand(index: int | None = None, side: str | None = None) -> dict[str, Any]:
        chosen = index if index is not None else min(
            range(len(references)),
            key=lambda i: (
                _coverage(references[i], "hands", hand_side=side)[0]
                if side is not None else
                max(_coverage(references[i], "hands", hand_side=candidate)[0]
                    for candidate in ("left", "right"))
            ),
        )
        quality = reference_quality(references[chosen], movement_behavior=movement_behavior)
        if side is not None:
            quality["hand_side"] = side
            quality["hand_coverage"] = round(
                _coverage(references[chosen], "hands", hand_side=side)[0], 3,
            )
        return {**quality, "reference_index": chosen}

    if not hand_sides and (
        (required_modalities is not None and "hands" in required_modalities)
        or any(
            any(point.usable() for point in frame.hands.values())
            for reference in references for frame in reference
        )
    ):
        raise ReferenceQualityError(FailureCode.INSUFFICIENT_HAND_COVERAGE, weakest_hand())
    # A second side seen throughout every demonstration is technique evidence,
    # even if gaps keep it below the reliable-side threshold. Avoid silently
    # treating that repeated two-hand attempt as a one-hand movement.
    for side in ("left", "right"):
        if side not in hand_sides and all(
            _coverage(reference, "hands", hand_side=side)[0] >= 0.30
            for reference in references
        ):
            raise ReferenceQualityError(FailureCode.INSUFFICIENT_HAND_COVERAGE, weakest_hand(side=side))
    for index, reference in enumerate(references):
        _validate_reference(
            reference, required, hand_sides, index=index, movement_behavior=movement_behavior,
        )
    common_moving: tuple[str, ...] = ()
    if static:
        motion_unit = _median([
            _units_per_shoulder(r, use_pose_anchor="pose" in required, hand_sides=hand_sides)
            for r in references
        ])
    else:
        required, motion_unit, common_moving = _require_dynamic_motion(
            references, required, hand_sides,
        )
    normalised: list[tuple[FrameSample, ...]] = []
    durations: list[int] = []
    static_endings: list[FrameSample] = []
    for index, reference in enumerate(references):
        normalised.append(
            normalize_sequence(
                reference,
                use_pose_anchor="pose" in required,
                required_hand_sides=hand_sides,
            )
        )
        durations.append(reference[-1].timestamp_ms - reference[0].timestamp_ms)
        if static:
            ending = static_reference_target(normalised[-1], required)
            if ending is None:
                raise ReferenceQualityError(FailureCode.UNSTABLE_STATIC_REFERENCE, {
                    **reference_quality(reference, movement_behavior="static"),
                    "reference_index": index,
                })
            static_endings.append(ending)
    if static:
        target = static_endings[0]
        if any(not static_frame_matches(target, ending, required) for ending in static_endings[1:]):
            raise ReferenceQualityError(FailureCode.INCONSISTENT_STATIC_REFERENCES)
    resampled = [_resample(seq) for seq in normalised]
    if not static:
        _require_consistent_dynamic_references(resampled, common_moving, motion_unit)
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
                # A brief YOLO loss in one example is filled by another
                # example at the same phase instead of erasing that phase.
                prop_minimum_presence=(len(references) + 1) // 2,
            )
        )
    prop_coverage = sum(frame.prop is not None for frame in canonical) / CANONICAL_FRAMES
    # Same elapsed-time policy as each reference: a short miss leaves a few
    # unknown canonical frames (resampling never invents landmarks).
    for modality, side in [("prop_translation", None), *(("hands", s) for s in hand_sides),
                           *((("pose", None),) if "pose" in required else ())]:
        present = _presence(canonical, modality, hand_side=side)
        prop = modality == "prop_translation"
        if (sum(present) / CANONICAL_FRAMES < (REFERENCE_MIN_PROP_COVERAGE if prop else MIN_COVERAGE)
                or _longest_gap_ms(canonical, present)
                > (REFERENCE_MAX_PROP_GAP_MS if prop else REFERENCE_MAX_GAP_MS)):
            # Every example lost tracking in the same part of the movement.
            raise ReferenceQualityError(FailureCode.EXCESSIVE_TRACKING_GAP, {"input": modality})
    # Phase timing is learned from the original reference clocks. Detecting
    # contact on interpolated canonical frames shifts event boundaries and can
    # make a correct catch score like a late one.
    reference_events = [detect_prop_events(reference) for reference in references]
    occurrences: dict[str, int] = {}
    shared_events: list[PropEvent] = []
    for event in reference_events[medoid_index]:
        occurrence = occurrences.get(event.kind, 0)
        occurrences[event.kind] = occurrence + 1
        matching = [
            [item for item in events if item.kind == event.kind]
            for events in reference_events
        ]
        if not all(len(items) > occurrence for items in matching):
            continue
        relative_times = [
            (items[occurrence].timestamp_ms - reference[0].timestamp_ms)
            / max(1, duration)
            for items, reference, duration in zip(matching, references, durations)
        ]
        shared_events.append(PropEvent(round(canonical_duration * sum(relative_times) / len(relative_times)), event.kind))
    prop_events = tuple(shared_events)
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
        schema_version=STATIC_SCHEMA_VERSION if movement_behavior == "static" else SCHEMA_VERSION if rotation_trace else 1,
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
        variability_metadata={
            "duration_std_ms": _std(durations),
            "reference_count": float(len(references)),
            # Template-frame units per shoulder width; lets live completion
            # apply the authoring motion thresholds in the same units.
            "motion_unit": round(motion_unit, 6),
        },
        prop_events=prop_events,
        rotation_trace=rotation_trace,
        movement_behavior=movement_behavior,
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
    """Every observed prop must retain the same identity for verified rotation."""
    identities = {
        frame.prop_metadata.get("track_id")
        for frame in samples
        if frame.prop is not None
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


def static_grip_side(
    target: FrameSample, required_modalities: Sequence[str]
) -> str | None:
    """The hand side whose learned grip holds the prop, when the reference shows it.

    Derived only from the observed target geometry: a hand with enough
    keypoints (including its wrist) lying on the prop box. A prop resting on
    the forearm, elbow, or shoulder is away from the hand, so such body-
    supported holds keep pose as technique evidence.
    """
    if not {"hands", "pose", "prop_translation"}.issubset(required_modalities):
        return None
    prop = target.prop
    width = target.prop_metadata.get("bbox_width")
    height = target.prop_metadata.get("bbox_height")
    if (not _usable(prop) or not all(
            isinstance(v, (int, float)) and not isinstance(v, bool)
            and math.isfinite(float(v)) and v > 0 for v in (width, height))):
        return None
    assert prop is not None
    hands = _semantic_hands(target.hands)
    for side in ("left", "right"):
        points = [p for k, p in hands.items() if _hand_side(k) == side and _usable(p)]
        wrist, middle = hands.get(f"{side}:0"), hands.get(f"{side}:9")
        if not _usable(wrist) or len(points) < STATIC_GRIP_MIN_HAND_KEYPOINTS:
            continue
        palm = _point_distance(wrist, middle) or 0.0
        margin = STATIC_GRIP_CONTACT_MARGIN * palm
        if any(abs(p.x - prop.x) <= float(width) / 2 + margin
               and abs(p.y - prop.y) <= float(height) / 2 + margin for p in points):
            return side
    return None


def _wrist_local(frame: FrameSample, side: str) -> FrameSample:
    """Hands and prop relative to one wrist; body pose is dropped."""
    wrist = frame.hands.get(f"{side}:0")
    if not _usable(wrist):
        return FrameSample(frame.timestamp_ms, prop_metadata=frame.prop_metadata)
    assert wrist is not None
    shift = lambda p: Landmark(p.x - wrist.x, p.y - wrist.y, p.confidence)  # noqa: E731
    return FrameSample(
        timestamp_ms=frame.timestamp_ms,
        hands={k: shift(p) for k, p in frame.hands.items() if _usable(p)},
        prop=shift(frame.prop) if _usable(frame.prop) else None,
        prop_metadata=frame.prop_metadata,
    )


def static_match_modalities(
    target: FrameSample, required_modalities: Sequence[str]
) -> tuple[str, ...]:
    """Modalities that geometrically gate a static hold (pose is observed-only when hand-led)."""
    if static_grip_side(target, required_modalities) is None:
        return tuple(required_modalities)
    return tuple(m for m in required_modalities if m != "pose")


def static_frame_matches(
    target: FrameSample, frame: FrameSample, required_modalities: Sequence[str]
) -> bool:
    """Match a held position in normalized space, ranked by evidence.

    1. Hand/grip shape is compared relative to each wrist so a slightly
       different hand position cannot hide or fake a different grip.
    2. Arm pose uses only elbows/wrists; face/hip landmarks never gate.
       A hand-led hold (see :func:`static_grip_side`) is compared in its
       wrist-local frame instead: grip shape and hand-to-prop placement
       must match, while arm/body geometry does not gate.
    3. The prop must be present and broadly placed; centre jitter is normal.
    """
    side = static_grip_side(target, required_modalities)
    if side is not None:
        target, frame = _wrist_local(target, side), _wrist_local(frame, side)
        required_modalities = tuple(m for m in required_modalities if m != "pose")
    for modality in required_modalities:
        if modality == "hands":
            expected = target.hands
            observed = {key: p for key, p in frame.hands.items() if _usable(p)}
            if expected and len(expected.keys() & observed.keys()) < len(expected) * 0.8:
                return False
            shape, position = _hand_errors(expected, observed)
            if not shape and not position:
                return False
            if any(error > STATIC_HAND_KEYPOINT_TOLERANCE for error in shape):
                return False
            if position and sum(position) / len(position) > STATIC_HAND_POSITION_TOLERANCE:
                return False
        elif modality == "pose":
            expected = {k: p for k, p in target.pose.items() if k in MEANINGFUL_POSE_KEYS}
            if not expected:
                continue  # shoulders only anchor the frame
            errors = [e for key, point in expected.items()
                      if (e := _point_distance(point, frame.pose.get(key))) is not None]
            if len(errors) < math.ceil(len(expected) / 2):
                return False
            if sum(errors) / len(errors) > STATIC_POSE_TOLERANCE:
                return False
        else:
            error = _point_distance(target.prop, frame.prop)
            if error is None or error > STATIC_PROP_TOLERANCE:
                return False
    return True


def _hand_errors(
    expected: Mapping[str, Landmark], observed: Mapping[str, Landmark]
) -> tuple[list[float], list[float]]:
    """Wrist-relative shape errors and absolute hand-position errors."""
    shape: list[float] = []
    position: list[float] = []
    for side in ("left", "right"):
        side_expected = {k: p for k, p in expected.items() if _hand_side(k) == side}
        if not side_expected:
            continue
        wrist = f"{side}:0"
        if wrist in side_expected and wrist in observed and len(side_expected) > 1:
            ew, ow = side_expected[wrist], observed[wrist]
            position.append(math.hypot(ew.x - ow.x, ew.y - ow.y))
            for key, point in side_expected.items():
                if key != wrist and key in observed:
                    shape.append(math.hypot(
                        (point.x - ew.x) - (observed[key].x - ow.x),
                        (point.y - ew.y) - (observed[key].y - ow.y),
                    ))
        else:
            position.extend(
                math.hypot(point.x - observed[key].x, point.y - observed[key].y)
                for key, point in side_expected.items() if key in observed
            )
    return shape, position


def final_frames_still(
    hold: Sequence[FrameSample], required_modalities: Sequence[str]
) -> bool:
    """The last three normalized observations show the performer stopped.

    Uses hands and arm pose; the prop is only used when neither is required,
    because YOLO centre jitter is not performer motion.
    """
    if len(hold) < 3:
        return False
    last = hold[-1]
    body = [m for m in ("hands", "pose") if m in required_modalities]
    for frame in hold[-3:-1]:
        for modality in body or ["prop_translation"]:
            if modality == "hands":
                error = _modality_error(last, frame, "hands")
            elif modality == "pose":
                errors = [e for key in MEANINGFUL_POSE_KEYS
                          if (e := _point_distance(last.pose.get(key), frame.pose.get(key))) is not None]
                if not errors:
                    continue
                error = sum(errors) / len(errors)
            else:
                error = _point_distance(last.prop, frame.prop)
            limit = STATIC_PROP_TOLERANCE if modality == "prop_translation" else STATIC_STABILITY_TOLERANCE
            if error is None or error > limit:
                return False
    return True


def static_reference_target(
    hold: Sequence[FrameSample], required_modalities: Sequence[str]
) -> FrameSample | None:
    """Return the stable ending of a normalized static reference hold, if any.

    The last three frames must all match the ending and be still, so a
    performer still moving at the end is rejected. Elsewhere in the hold
    isolated detector misses/jitter are tolerated at the same 85% agreement
    live assessment uses (always at least one miss). The ending is the recent
    frame agreeing with most of the hold, so one noisy final observation does
    not become the reference position.
    """
    if len(hold) < 3:
        return None
    best: tuple[int, FrameSample, list[bool]] | None = None
    for candidate in reversed(hold[-3:]):
        matches = [static_frame_matches(candidate, frame, required_modalities) for frame in hold]
        if best is None or sum(matches) > best[0]:
            best = (sum(matches), candidate, matches)
    _, target, matches = best
    allowed_mismatches = max(1, int(len(hold) * (1 - STATIC_REFERENCE_MATCH_RATIO)))
    if (not all(matches[-3:]) or matches.count(False) > allowed_mismatches
            or not final_frames_still(hold, required_modalities)):
        return None
    return target


def _phase_aligned_prop_curve_error(
    reference: Sequence[FrameSample],
    candidate: Sequence[FrameSample],
    path: Sequence[tuple[int, int]],
) -> tuple[float | None, float]:
    """Compare local prop-trajectory curvature after DTW phase alignment.

    Neighbor residuals remove absolute position and steady velocity, so this
    measures local jitter/control without treating a smooth fast execution or
    a learned sharp turn as unstable. Missing observations remain unknown.
    """
    reference_points: list[list[Landmark]] = [[] for _ in candidate]
    for reference_index, candidate_index in path:
        point = reference[reference_index].prop
        if _usable(point):
            assert point is not None
            reference_points[candidate_index].append(point)
    aligned_reference = [
        _mean_points(points) if points else None for points in reference_points
    ]

    possible = max(0, len(candidate) - 2)
    if possible == 0:
        return None, 0.0
    errors: list[float] = []
    for index in range(1, len(candidate) - 1):
        expected = (
            aligned_reference[index - 1],
            aligned_reference[index],
            aligned_reference[index + 1],
        )
        observed = (
            candidate[index - 1].prop,
            candidate[index].prop,
            candidate[index + 1].prop,
        )
        if not all(_usable(point) for point in (*expected, *observed)):
            continue
        expected_before, expected_center, expected_after = expected
        observed_before, observed_center, observed_after = observed
        assert all(
            point is not None
            for point in (
                expected_before,
                expected_center,
                expected_after,
                observed_before,
                observed_center,
                observed_after,
            )
        )
        expected_curve_x = expected_center.x - (
            expected_before.x + expected_after.x
        ) / 2
        expected_curve_y = expected_center.y - (
            expected_before.y + expected_after.y
        ) / 2
        observed_curve_x = observed_center.x - (
            observed_before.x + observed_after.x
        ) / 2
        observed_curve_y = observed_center.y - (
            observed_before.y + observed_after.y
        ) / 2
        errors.append(
            math.hypot(
                expected_curve_x - observed_curve_x,
                expected_curve_y - observed_curve_y,
            )
        )
    return (
        (sum(errors) / len(errors), len(errors) / possible)
        if errors
        else (None, 0.0)
    )


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


def compare_sequence(template: MovementTemplate, samples: Sequence[FrameSample], *, assessment: bool = False) -> SequenceComparison:
    """Compare captured measurements with a template using modality-masked DTW.

    Missing observations lower coverage and cannot yield a perfect component.
    ``total`` is a bounded 0..12 rubric: observed movement components carry
    75%, prop components 25%, with at most one optional rotation bonus point.
    """
    validator = validate_assessment_sequence if assessment else validate_sequence
    validation = validator(
        samples,
        template.required_modalities,
        required_hand_sides=template.required_hand_sides,
        **({"template": template} if assessment else {}),
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
    canonical = template.canonical_sequence
    static = template.movement_behavior == "static"
    grip_side = (
        static_grip_side(canonical[-1], template.required_modalities)
        if static else None
    )
    if grip_side is not None:
        # Score a hand-led hold the way completion matches it: grip and
        # hand-to-prop placement in the wrist frame; arm pose is not technique.
        canonical = tuple(_wrist_local(frame, grip_side) for frame in canonical)
        candidate = tuple(_wrist_local(frame, grip_side) for frame in candidate)
        path_modalities = [m for m in path_modalities if m != "pose"]
    path = _dtw(canonical, candidate, path_modalities)
    component_for = {"Body technique": "pose", "Hand technique": "hands", "Prop path": "prop_translation"}
    for name, modality in component_for.items():
        if modality not in path_modalities:
            continue
        errors = [_modality_error(canonical[i], candidate[j], modality) for i, j in path]
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
                tuple(
                    PropEvent(event.timestamp_ms - samples[0].timestamp_ms, event.kind)
                    for event in detect_prop_events(samples)
                ),
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
        coverage, _ = _coverage(samples, "prop_translation")
        control_error, local_coverage = _phase_aligned_prop_curve_error(
            canonical, candidate, path
        )
        if control_error is not None:
            control_coverage = min(coverage, local_coverage)
            confidence["Control/stability"] = control_coverage
            control_score = _quality(control_error, control_coverage)
            # Even a short valid detector gap is uncertainty, not evidence of
            # perfectly steady control.
            if coverage < 1.0:
                control_score = min(control_score, 2)
            scores["Control/stability"] = control_score
    if template.rotation_trace is not None:
        rotation = _rotation_trace(samples)
        stable = _rotation_track_stable(samples)
        aligned_errors: list[float] = []
        alignment_coverage = 0.0
        if stable and rotation.pair_coverage > 0:
            rotation_path = _dtw_angles(template.rotation_trace.angles_rad, rotation.angles_rad)
            aligned_errors = [
                abs(expected - observed)
                for i, j in rotation_path
                if (expected := template.rotation_trace.angles_rad[i]) is not None
                and (observed := rotation.angles_rad[j]) is not None
            ]
            alignment_coverage = len(aligned_errors) / max(len(rotation_path), 1)
        evidence = min(rotation.coverage, rotation.pair_coverage, alignment_coverage)
        status = (
            "verified"
            if stable
            and rotation.coverage >= MIN_ROTATION_COVERAGE
            and rotation.pair_coverage >= MIN_ROTATION_PAIR_COVERAGE
            and alignment_coverage >= MIN_ROTATION_PAIR_COVERAGE
            else "partial" if evidence > 0 else "unverified"
        )
        rotation_bonus = 0
        if status == "verified" and aligned_errors:
            # Observed 2D turns can reward a matching execution but marker
            # loss never lowers movement or prop-trajectory scores. Signed
            # angle distinguishes one from two turns with the same endpoints.
            total_error = abs(rotation.total_signed_rad - template.rotation_trace.total_signed_rad)
            progression_error = sum(aligned_errors) / len(aligned_errors)
            similarity = math.exp(-total_error / (0.65 * math.pi) - progression_error / (0.65 * math.pi))
            rotation_bonus = 1 if similarity >= 0.70 else 0
        rotation_diagnostics = {
            "rotation_required": False,
            "rotation_available": True,
            "orientation_coverage": round(rotation.coverage, 3),
            "orientation_pair_coverage": round(rotation.pair_coverage, 3),
            "rotation_alignment_coverage": round(alignment_coverage, 3),
            "rotation_track_stable": stable,
            "rotation_evidence": status,
            "rotation_bonus": rotation_bonus,
        }
    else:
        rotation_diagnostics = {"rotation_required": False, "rotation_available": False, "rotation_bonus": 0}
    movement = [scores[name] for name in ("Body technique", "Hand technique", "Timing") if scores[name] is not None]
    prop = [scores[name] for name in ("Prop path", "Control/stability") if scores[name] is not None]
    movement_fraction = sum(movement) / (3 * len(movement)) if movement else 0.0
    prop_fraction = sum(prop) / (3 * len(prop)) if prop else 0.0
    total = max(0, min(12, round(12 * (0.75 * movement_fraction + 0.25 * prop_fraction)) + rotation_diagnostics["rotation_bonus"]))
    return SequenceComparison(scores, confidence, total, _level(total), validation, rotation_diagnostics)
