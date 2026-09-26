"""Evidence-based completion detection for live custom assessments."""

from dataclasses import dataclass
from typing import Sequence

from .template_engine import (
    POSE_MOTION_THRESHOLD,
    STATIC_HOLD_MS,
    FrameSample,
    MovementTemplate,
    _dtw,
    _modality_error,
    compare_sequence,
    normalize_sequence,
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
    moving_modalities: Sequence[str],
) -> int | None:
    baselines = {
        modality: next(
            (index for index, frame in enumerate(normalized)
             if _modality_error(frame, frame, modality) is not None),
            None,
        )
        for modality in moving_modalities
    }
    for index, frame in enumerate(normalized[1:], start=1):
        for modality, baseline in baselines.items():
            if baseline is None or baseline >= index:
                continue
            distance = _modality_error(normalized[baseline], frame, modality)
            if distance is not None and distance >= 0.03:
                return max(baseline, index - 3)
    return None


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
    moving_modalities = [
        modality
        for modality in required
        if _sequence_range(template.canonical_sequence, modality)
        >= POSE_MOTION_THRESHOLD
    ]
    return _movement_start_index(normalized, moving_modalities)


def estimate_sequence_progress(
    template: MovementTemplate, samples: Sequence[FrameSample]
) -> float:
    """Estimate the latest observed canonical phase for generic coaching."""
    if not samples or template.movement_behavior == "static":
        return 0.0
    reference = template.canonical_sequence
    moving = [
        modality for modality in template.required_modalities
        if _sequence_range(reference, modality) >= POSE_MOTION_THRESHOLD
    ]
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
    moving_modalities = [
        modality
        for modality in required
        if _sequence_range(reference, modality) >= POSE_MOTION_THRESHOLD
    ]
    if not moving_modalities:
        return WAITING_FOR_MOVEMENT

    # Retain a short lead-in from the user's start position for comparison.
    movement_start = _movement_start_index(normalized, moving_modalities)
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
        _sequence_range(candidate, modality)
        >= max(POSE_MOTION_THRESHOLD, _sequence_range(reference, modality) * 0.20)
        for modality in moving_modalities
    )
    if not movement_detected:
        return WAITING_FOR_MOVEMENT
    if len(candidate) < 8:
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
            _ENDPOINT_TOLERANCE, max(0.10, expected_range * 0.45)
        )
        evidence.append(DynamicMotionEvidence(
            modality=modality,
            path_ratio=ratio,
            start_error=start_error,
            end_error=end_error,
            aligned_error=aligned_error,
            phase_progress=phase_progress,
            complete=(ratio >= _MIN_PATH_RATIO
                      and phase_progress >= 0.85
                      and start_error is not None and start_error <= endpoint_tolerance
                      and end_error is not None and end_error <= endpoint_tolerance
                      and aligned_error is not None
                      and aligned_error <= _MAX_ALIGNED_MOTION_ERROR),
        ))
    quorum = len(moving_modalities) // 2 + 1 if len(moving_modalities) > 2 else 1
    if sum(item.complete for item in evidence) < quorum:
        return MOVEMENT_DETECTED
    prop_evidence = next((item for item in evidence if item.modality == "prop_translation"), None)
    if prop_evidence is not None and not (
        prop_evidence.path_ratio >= 0.50
        and prop_evidence.start_error is not None
        and prop_evidence.start_error <= min(
            _ENDPOINT_TOLERANCE, max(0.10, _sequence_range(reference, "prop_translation") * 0.60)
        )
        and prop_evidence.end_error is not None
        and prop_evidence.end_error <= min(
            _ENDPOINT_TOLERANCE, max(0.10, _sequence_range(reference, "prop_translation") * 0.60)
        )
        and prop_evidence.aligned_error is not None
        and prop_evidence.aligned_error <= 0.30
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
    if len(hold) < 8:
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
    if sum(matches) / len(matches) < 0.85:
        return POSITION_DETECTED
    if hold[-1].timestamp_ms - hold[0].timestamp_ms < STATIC_HOLD_MS:
        return POSITION_DETECTED
    comparison = compare_sequence(template, hold, assessment=True)
    if comparison.total < 7:
        return POSITION_DETECTED
    if template.feature_capabilities.get("hands") and (comparison.component_scores["Hand technique"] or 0) < 2:
        return POSITION_DETECTED
    if (comparison.component_scores["Prop path"] or 0) < 2:
        return POSITION_DETECTED
    return MOVEMENT_COMPLETED
