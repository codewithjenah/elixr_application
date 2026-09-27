"""Evidence-based completion detection for live custom assessments."""

from dataclasses import dataclass
from typing import Mapping, Sequence

from .template_engine import (
    MAX_REFERENCE_ROTATION_SPREAD_RAD,
    MIN_ROTATION_AMOUNT_RAD,
    MIN_ROTATION_COVERAGE,
    MIN_ROTATION_PAIR_COVERAGE,
    MIN_STATIC_HOLD_SAMPLES,
    MIN_TRACKING_SAMPLES,
    STATIC_HOLD_MS,
    FrameSample,
    MovementTemplate,
    _dtw,
    _modality_error,
    _rotation_trace,
    _rotation_track_stable,
    compare_sequence,
    final_frames_still,
    motion_thresholds,
    normalize_sequence,
    sequence_motion,
    static_frame_matches,
    trailing_hold_window,
    validate_assessment_sequence,
)


WAITING_FOR_MOVEMENT = "waiting_for_movement"
MOVEMENT_DETECTED = "movement_detected"
MOVEMENT_COMPLETED = "completed"
POSITION_DETECTED = "position_detected"

_MIN_PATH_RATIO = 0.65
_ENDPOINT_TOLERANCE = 0.40
_MAX_COMPLETION_SAMPLES = 240
_MIN_DYNAMIC_DURATION_MS = 350
_MAX_ALIGNED_MOTION_ERROR = 0.25


@dataclass(frozen=True)
class DynamicMotionEvidence:
    modality: str
    path_ratio: float
    start_error: float | None
    end_error: float | None
    aligned_error: float | None
    phase_progress: float
    complete: bool


def _bounded_samples(samples: Sequence[FrameSample]) -> tuple[FrameSample, ...]:
    if len(samples) <= _MAX_COMPLETION_SAMPLES:
        return tuple(samples)
    stride = (len(samples) - 1 + _MAX_COMPLETION_SAMPLES - 2) // (
        _MAX_COMPLETION_SAMPLES - 1
    )
    bounded = list(samples[::stride])
    if bounded[-1] is not samples[-1]:
        bounded.append(samples[-1])
    return tuple(bounded)


def _sequence_range(sequence: Sequence[FrameSample], modality: str) -> float:
    if len(sequence) < 2:
        return 0.0
    first = sequence[0]
    return max(
        (
            error
            for frame in sequence[1:]
            if (error := _modality_error(first, frame, modality)) is not None
        ),
        default=0.0,
    )


def _sequence_path_length(
    sequence: Sequence[FrameSample], modality: str, *, bridge_gap_ms: int = 0
) -> float:
    """Sum observed travel; across a short miss use only endpoint displacement."""
    total = 0.0
    previous: tuple[int, FrameSample] | None = None
    for index, frame in enumerate(sequence):
        if _modality_error(frame, frame, modality) is None:
            continue
        if previous is not None:
            previous_index, previous_frame = previous
            if (index == previous_index + 1 or
                    (bridge_gap_ms > 0 and
                     frame.timestamp_ms - previous_frame.timestamp_ms <= bridge_gap_ms)):
                error = _modality_error(previous_frame, frame, modality)
                if error is not None:
                    total += error
        previous = (index, frame)
    return total


def _movement_start_index(
    normalized: Sequence[FrameSample],
    moving_thresholds: Mapping[str, float],
) -> int | None:
    baselines = {
        modality: next(
            (index for index, frame in enumerate(normalized)
             if _modality_error(frame, frame, modality) is not None),
            None,
        )
        for modality in moving_thresholds
    }
    for index, frame in enumerate(normalized[1:], start=1):
        for modality, baseline in baselines.items():
            if baseline is None or baseline >= index:
                continue
            distance = _modality_error(normalized[baseline], frame, modality)
            # Start evidence may appear before full meaningful motion. The
            # later sustained-displacement gate still rejects detector jitter.
            start_threshold = min(0.03, moving_thresholds[modality] * 0.5)
            if distance is not None and distance >= start_threshold:
                return max(baseline, index - 3)
    return None


def _motion_unit(template: MovementTemplate) -> float | None:
    value = template.variability_metadata.get("motion_unit")
    return float(value) if value is not None and value > 0 else None


def _motion(template: MovementTemplate, sequence: Sequence[FrameSample], modality: str) -> float:
    """The motion measure authoring used; legacy templates keep the old one."""
    if _motion_unit(template) is None:
        return _sequence_range(sequence, modality)
    return sequence_motion(sequence, modality)


def _moving_thresholds(template: MovementTemplate) -> dict[str, float]:
    """Learned moving modalities and their meaningful-motion thresholds.

    Uses the authoring thresholds and motion measure in the template's own
    units, so a small movement accepted at authoring is also completable
    live. Legacy templates without ``motion_unit`` keep the original rule.
    """
    thresholds = motion_thresholds(_motion_unit(template))
    return {
        modality: thresholds[modality]
        for modality in template.required_modalities
        if _motion(template, template.canonical_sequence, modality) >= thresholds[modality]
    }


def find_movement_start_index(
    template: MovementTemplate, samples: Sequence[FrameSample]
) -> int | None:
    if len(samples) < 2:
        return None
    required = template.required_modalities
    normalized = normalize_sequence(
        samples,
        use_pose_anchor="pose" in required,
        required_hand_sides=template.required_hand_sides,
    )
    return _movement_start_index(normalized, _moving_thresholds(template))


def estimate_sequence_progress(
    template: MovementTemplate, samples: Sequence[FrameSample]
) -> float:
    """Estimate the latest observed canonical phase for generic coaching."""
    if not samples or template.movement_behavior == "static":
        return 0.0
    reference = template.canonical_sequence
    moving = list(_moving_thresholds(template))
    if not moving:
        return 0.0
    recent = normalize_sequence(
        _bounded_samples(samples), use_pose_anchor="pose" in template.required_modalities,
        required_hand_sides=template.required_hand_sides,
    )[-3:]
    best_index = 0
    best_error = float("inf")
    for index, phase in enumerate(reference):
        errors = [
            error for frame in recent for modality in moving
            if (error := _modality_error(phase, frame, modality)) is not None
        ]
        if errors and sum(errors) / len(errors) < best_error:
            best_error = sum(errors) / len(errors)
            best_index = index
    return best_index / max(1, len(reference) - 1) if best_error <= 0.25 else 0.0


def evaluate_completion(
    template: MovementTemplate, samples: Sequence[FrameSample]
) -> str:
    """Return progress from observed motion, independently of rubric score."""
    if template.movement_behavior == "static":
        return _evaluate_static_completion(template, samples)
    bounded = _bounded_samples(samples)
    if len(bounded) < 2:
        return WAITING_FOR_MOVEMENT

    required = template.required_modalities
    normalized = normalize_sequence(
        bounded,
        use_pose_anchor="pose" in required,
        required_hand_sides=template.required_hand_sides,
    )
    reference = template.canonical_sequence
    thresholds = _moving_thresholds(template)
    moving_modalities = list(thresholds)
    if not moving_modalities:
        if template.rotation_trace is not None:
            trace = _rotation_trace(bounded)
            if abs(trace.total_signed_rad) < MIN_ROTATION_AMOUNT_RAD:
                return WAITING_FOR_MOVEMENT
            validation = validate_assessment_sequence(
                bounded, required, required_hand_sides=template.required_hand_sides,
                template=template,
            )
            if (validation.valid and _rotation_track_stable(bounded)
                    and trace.coverage >= MIN_ROTATION_COVERAGE
                    and trace.pair_coverage >= MIN_ROTATION_PAIR_COVERAGE
                    and abs(trace.total_signed_rad - template.rotation_trace.total_signed_rad)
                    <= MAX_REFERENCE_ROTATION_SPREAD_RAD):
                return MOVEMENT_COMPLETED
            return MOVEMENT_DETECTED
        return WAITING_FOR_MOVEMENT
    # Tolerances below were tuned in shoulder widths; widen (never tighten)
    # them for hand-anchored templates whose units are much smaller.
    tolerance_scale = max(1.0, _motion_unit(template) or 1.0)

    # Retain a short lead-in from the user's start position for comparison.
    movement_start = _movement_start_index(normalized, thresholds)
    if movement_start is None:
        return WAITING_FOR_MOVEMENT

    candidate = normalized[movement_start:]
    if not candidate:
        return WAITING_FOR_MOVEMENT
    candidate_start_ms = candidate[0].timestamp_ms
    source_candidate = tuple(
        frame for frame in samples if frame.timestamp_ms >= candidate_start_ms
    )
    movement_detected = any(
        _motion(template, candidate, modality)
        >= max(thresholds[modality], _motion(template, reference, modality) * 0.20)
        for modality in moving_modalities
    )
    if not movement_detected:
        return WAITING_FOR_MOVEMENT
    if len(candidate) < MIN_TRACKING_SAMPLES:
        return MOVEMENT_DETECTED

    candidate_duration = candidate[-1].timestamp_ms - candidate[0].timestamp_ms
    if candidate_duration < _MIN_DYNAMIC_DURATION_MS:
        return MOVEMENT_DETECTED

    validation = validate_assessment_sequence(
        source_candidate,
        required,
        required_hand_sides=template.required_hand_sides,
        template=template,
    )
    if not validation.valid:
        return MOVEMENT_DETECTED

    # Each learned moving modality contributes evidence. A short glitch in one
    # modality cannot veto a well-observed sequence in the others, but every
    # required modality still has to satisfy live observability above.
    evidence: list[DynamicMotionEvidence] = []
    for modality in moving_modalities:
        expected_range = _sequence_range(reference, modality)
        expected_path = _sequence_path_length(reference, modality)
        observed_path = _sequence_path_length(candidate, modality, bridge_gap_ms=450)
        start_error = next(
            (error for frame in candidate[:3]
             if (error := _modality_error(reference[0], frame, modality)) is not None),
            None,
        )
        end_error = next(
            (error for frame in reversed(candidate)
             if candidate[-1].timestamp_ms - frame.timestamp_ms <= 450
             and (error := _modality_error(reference[-1], frame, modality)) is not None),
            None,
        )
        alignment = _dtw(reference, candidate, (modality,))
        errors = [
            error for i, j in alignment
            if (error := _modality_error(reference[i], candidate[j], modality)) is not None
        ]
        aligned_error = sum(errors) / len(errors) if errors else None
        ratio = observed_path / expected_path if expected_path > 0 else 0.0
        recent = next(
            (frame for frame in reversed(candidate)
             if _modality_error(reference[-1], frame, modality) is not None),
            None,
        )
        phase_errors = [
            (error, -index) for index, phase in enumerate(reference)
            if recent is not None
            and (error := _modality_error(phase, recent, modality)) is not None
        ]
        phase_progress = (
            -min(phase_errors)[1] / max(1, len(reference) - 1)
            if phase_errors else 0.0
        )
        endpoint_tolerance = min(
            _ENDPOINT_TOLERANCE * tolerance_scale,
            max(0.10 * tolerance_scale, expected_range * 0.45),
        )
        # Detector jitter accumulates path length but not sustained
        # displacement; a stationary attempt cannot satisfy this.
        sustained = sequence_motion(candidate, modality) >= max(
            0.6 * thresholds[modality], 0.5 * sequence_motion(reference, modality)
        )
        evidence.append(DynamicMotionEvidence(
            modality=modality,
            path_ratio=ratio,
            start_error=start_error,
            end_error=end_error,
            aligned_error=aligned_error,
            phase_progress=phase_progress,
            complete=(ratio >= _MIN_PATH_RATIO
                      and sustained
                      and phase_progress >= 0.85
                      and start_error is not None and start_error <= endpoint_tolerance
                      and end_error is not None and end_error <= endpoint_tolerance
                      and aligned_error is not None
                      and aligned_error <= _MAX_ALIGNED_MOTION_ERROR * tolerance_scale),
        ))
    quorum = len(moving_modalities) // 2 + 1 if len(moving_modalities) > 2 else 1
    if sum(item.complete for item in evidence) < quorum:
        return MOVEMENT_DETECTED
    prop_evidence = next((item for item in evidence if item.modality == "prop_translation"), None)
    prop_endpoint_tolerance = min(
        _ENDPOINT_TOLERANCE * tolerance_scale,
        max(0.10 * tolerance_scale, _sequence_range(reference, "prop_translation") * 0.60),
    )
    if prop_evidence is not None and not (
        prop_evidence.path_ratio >= 0.50
        and prop_evidence.start_error is not None
        and prop_evidence.start_error <= prop_endpoint_tolerance
        and prop_evidence.end_error is not None
        and prop_evidence.end_error <= prop_endpoint_tolerance
        and prop_evidence.aligned_error is not None
        and prop_evidence.aligned_error <= 0.30 * tolerance_scale
    ):
        # A prop-centric template needs meaningful confirmed prop travel even
        # when body/hand motion supplies the completion quorum.
        return MOVEMENT_DETECTED
    return MOVEMENT_COMPLETED


def _evaluate_static_completion(
    template: MovementTemplate, samples: Sequence[FrameSample]
) -> str:
    if not samples:
        return WAITING_FOR_MOVEMENT
    hold = trailing_hold_window(samples)
    if len(hold) < MIN_STATIC_HOLD_SAMPLES:
        if len(hold) < 3:
            return WAITING_FOR_MOVEMENT
        normalized = normalize_sequence(
            hold, use_pose_anchor="pose" in template.required_modalities,
            required_hand_sides=template.required_hand_sides,
        )
        return POSITION_DETECTED if all(
            static_frame_matches(
                template.canonical_sequence[-1], frame, template.required_modalities
            ) for frame in normalized[-3:]
        ) else WAITING_FOR_MOVEMENT
    validation = validate_assessment_sequence(
        hold, template.required_modalities,
        required_hand_sides=template.required_hand_sides,
        template=template,
    )
    if not validation.valid:
        return WAITING_FOR_MOVEMENT
    normalized = normalize_sequence(
        hold, use_pose_anchor="pose" in template.required_modalities,
        required_hand_sides=template.required_hand_sides,
    )
    target = template.canonical_sequence[-1]
    matches = [
        static_frame_matches(target, frame, template.required_modalities)
        for frame in normalized
    ]
    if not all(matches[-3:]):
        return WAITING_FOR_MOVEMENT
    if not final_frames_still(normalized, template.required_modalities):
        return POSITION_DETECTED
    if sum(matches) / len(matches) < 0.85:
        return POSITION_DETECTED
    if hold[-1].timestamp_ms - hold[0].timestamp_ms < STATIC_HOLD_MS:
        return POSITION_DETECTED
    comparison = compare_sequence(template, hold, assessment=True)
    if comparison.total < 7:
        return POSITION_DETECTED
    if template.feature_capabilities.get("hands") and (comparison.component_scores["Hand technique"] or 0) < 2:
        return POSITION_DETECTED
    # Grip/hand geometry is the primary static evidence; the prop only needs
    # presence and broad placement (enforced by static_frame_matches and
    # validation above), so ordinary YOLO jitter cannot block completion.
    if (comparison.component_scores["Prop path"] or 0) < 1:
        return POSITION_DETECTED
    return MOVEMENT_COMPLETED
