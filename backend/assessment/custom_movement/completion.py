"""Conservative, template-based completion detection for live assessments."""

from dataclasses import replace
from typing import Sequence

from .template_engine import (
    POSE_MOTION_THRESHOLD,
    STATIC_HOLD_MS,
    FrameSample,
    MovementTemplate,
    _modality_error,
    compare_sequence,
    detect_prop_events,
    normalize_sequence,
    static_frame_matches,
    trailing_hold_window,
    validate_sequence,
)


WAITING_FOR_MOVEMENT = "waiting_for_movement"
MOVEMENT_DETECTED = "movement_detected"
MOVEMENT_COMPLETED = "completed"
POSITION_DETECTED = "position_detected"

_MIN_PATH_RATIO = 0.65
_ENDPOINT_TOLERANCE = 0.40
_MAX_COMPLETION_SAMPLES = 240


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


def _sequence_path_length(sequence: Sequence[FrameSample], modality: str) -> float:
    return sum(
        error
        for previous, current in zip(sequence, sequence[1:])
        if (error := _modality_error(previous, current, modality)) is not None
    )


def _movement_start_index(
    normalized: Sequence[FrameSample],
    moving_modalities: Sequence[str],
) -> int | None:
    for index, frame in enumerate(normalized[1:], start=1):
        if any(
            (distance := _modality_error(normalized[0], frame, modality))
            is not None
            and distance >= 0.03
            for modality in moving_modalities
        ):
            return max(0, index - 3)
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


def evaluate_completion(
    template: MovementTemplate, samples: Sequence[FrameSample]
) -> str:
    """Return a beginner-facing progress state using only captured samples.

    The movement range and path checks prevent a stationary user or a partial
    gesture from completing. The existing template validator and comparator
    remain authoritative; comparison time is normalized only for this gate so
    a slower execution can still complete while its real duration is scored
    unchanged by ``compare_sequence`` at assessment finish.
    """
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
        _sequence_range(normalized, modality)
        >= max(POSE_MOTION_THRESHOLD, _sequence_range(reference, modality) * 0.20)
        for modality in moving_modalities
    )
    if not movement_detected:
        return WAITING_FOR_MOVEMENT
    if len(candidate) < 8:
        return MOVEMENT_DETECTED

    candidate_duration = candidate[-1].timestamp_ms - candidate[0].timestamp_ms
    if candidate_duration < template.duration_ms * 0.75:
        return MOVEMENT_DETECTED

    validation = validate_sequence(
        source_candidate,
        required,
        required_hand_sides=template.required_hand_sides,
    )
    if not validation.valid:
        return MOVEMENT_DETECTED

    # Require both ends of at least one learned moving signal and enough
    # observed travel through that signal. A final-pose hold has no such path.
    path_completed = True
    for modality in moving_modalities:
        expected_range = _sequence_range(reference, modality)
        expected_path = _sequence_path_length(reference, modality)
        observed_path = _sequence_path_length(candidate, modality)
        start_error = _modality_error(reference[0], candidate[0], modality)
        end_error = _modality_error(reference[-1], candidate[-1], modality)
        if (
            expected_path > 0
            and observed_path >= expected_path * _MIN_PATH_RATIO
            and start_error is not None
            and end_error is not None
            and start_error <= _ENDPOINT_TOLERANCE
            and end_error <= _ENDPOINT_TOLERANCE
            and expected_range >= POSE_MOTION_THRESHOLD
        ):
            continue
        path_completed = False
        break
    if not path_completed:
        return MOVEMENT_DETECTED

    if template.feature_capabilities.get("release_catch"):
        # Event detection needs consecutive camera observations: the bounded
        # comparison samples can skip the short release and catch evidence.
        observed_events = {
            event.kind for event in detect_prop_events(source_candidate)
        }
        if not {"release", "airborne", "catch"}.issubset(observed_events):
            return MOVEMENT_DETECTED

    # Compare the learned path at its learned time scale. This is a completion
    # gate only; finish_custom_assessment scores the original timestamps.
    comparison_duration = max(template.duration_ms, len(candidate) - 1)
    timed = tuple(
        replace(
            frame,
            timestamp_ms=round(
                index * comparison_duration / max(len(candidate) - 1, 1)
            ),
        )
        for index, frame in enumerate(candidate)
    )
    comparison = compare_sequence(template, timed)
    return MOVEMENT_COMPLETED if comparison.total >= 7 else MOVEMENT_DETECTED


def _evaluate_static_completion(
    template: MovementTemplate, samples: Sequence[FrameSample]
) -> str:
    if not samples:
        return WAITING_FOR_MOVEMENT
    hold = trailing_hold_window(samples)
    if len(hold) < 8:
        return WAITING_FOR_MOVEMENT
    validation = validate_sequence(
        hold, template.required_modalities,
        required_hand_sides=template.required_hand_sides,
    )
    if not validation.valid:
        return WAITING_FOR_MOVEMENT
    normalized = normalize_sequence(
        hold, use_pose_anchor="pose" in template.required_modalities,
        required_hand_sides=template.required_hand_sides,
    )
    target = template.canonical_sequence[-1]
    if not all(static_frame_matches(target, frame, template.required_modalities) for frame in normalized):
        return POSITION_DETECTED if all(
            static_frame_matches(target, frame, template.required_modalities)
            for frame in normalized[-3:]
        ) else WAITING_FOR_MOVEMENT
    if hold[-1].timestamp_ms - hold[0].timestamp_ms < STATIC_HOLD_MS:
        return POSITION_DETECTED
    comparison = compare_sequence(template, hold)
    if comparison.total < 7:
        return POSITION_DETECTED
    if template.feature_capabilities.get("hands") and (comparison.component_scores["Hand technique"] or 0) < 2:
        return POSITION_DETECTED
    if (comparison.component_scores["Prop path"] or 0) < 2:
        return POSITION_DETECTED
    return MOVEMENT_COMPLETED
