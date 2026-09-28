"""Evidence-based completion detection for live custom assessments."""

import math
from dataclasses import dataclass, replace
from typing import Mapping, Sequence

from .template_engine import (
    MAX_REFERENCE_ROTATION_SPREAD_RAD,
    MIN_ROTATION_AMOUNT_RAD,
    MIN_ROTATION_COVERAGE,
    MIN_ROTATION_PAIR_COVERAGE,
    MIN_STATIC_HOLD_SAMPLES,
    MIN_TRACKING_SAMPLES,
    STATIC_HOLD_MS,
    STATIC_LIVE_PLACEMENT_SCALE,
    FrameSample,
    MovementTemplate,
    _dtw,
    _modality_error,
    _rotation_trace,
    _rotation_track_stable,
    _semantic_hands,
    _usable,
    compare_sequence,
    final_frames_still,
    motion_thresholds,
    normalize_sequence,
    sequence_motion,
    static_frame_matches,
    static_match_modalities,
    trailing_hold_window,
    validate_assessment_sequence,
)


WAITING_FOR_MOVEMENT = "waiting_for_movement"
MOVEMENT_DETECTED = "movement_detected"
MOVEMENT_COMPLETED = "completed"
POSITION_DETECTED = "position_detected"

# Dynamic completion asks "roughly the learned movement?"; how closely it
# matched is left to compare_sequence scoring (low similarity = low score).
# These are minimal "was the learned movement attempted?" gates; they are
# deliberately loose because compare_sequence grades the quality.
_MIN_PATH_RATIO = 0.35
_MAX_COMPLETION_SAMPLES = 240
# Live completion runs synchronously in the AI frame pass every 0.5 s and DTW
# cost is linear in the candidate length. Completion is sticky, so a recent
# window that still spans a slow execution of the movement is sufficient.
_LIVE_WINDOW_DURATION_FACTOR = 2.5
_LIVE_WINDOW_MIN_MS = 4000
_MIN_DYNAMIC_DURATION_MS = 350
# Compared after centring both paths, so it measures shape, not placement.
_MAX_ALIGNED_MOTION_ERROR = 0.45
_MIN_SUSTAINED_MOTION_RATIO = 0.35
_MIN_OUT_AND_BACK_PHASE = 0.50
# Examples that disagree widen acceptance up to this factor; near-identical
# examples keep the base tolerance.
_MAX_SPREAD_WIDENING = 0.75
# A learned prop path must travel a meaningful share of the reference path and
# keep a rough forward projection onto the learned net travel.
_MIN_PROP_PATH_RATIO = 0.35
_MIN_PROP_PROGRESS = 0.25
# Smallest 0..12 rubric total at or above 70% (9/12 = 75%). Applied only to
# attempts that completion validated; the rubric stays an integer total.
VALIDATED_ATTEMPT_MIN_TOTAL = 9


@dataclass(frozen=True)
class DynamicMotionEvidence:
    modality: str
    path_ratio: float
    start_error: float | None
    end_error: float | None
    aligned_error: float | None
    phase_progress: float
    progress: float | None
    directional: bool
    reference_travel: float
    sustained: bool
    complete: bool


_MIN_DISPLACEMENT_PROGRESS = 0.45
_MIN_WIDENED_DISPLACEMENT_PROGRESS = 0.40


def _same_movement(
    directional: bool,
    progress: float | None,
    phase_progress: float,
    min_progress: float = _MIN_DISPLACEMENT_PROGRESS,
) -> bool:
    """Coarse movement identity from start-anchored displacement.

    A directional movement must travel the same way (reversed or sideways
    attempts project <= 0) for a meaningful share of the reference distance. An
    out-and-back movement has little net travel, so it must reach a late
    learned phase. Absolute start/end placement is never required.
    """
    if directional:
        return progress is not None and progress >= min_progress
    return phase_progress >= _MIN_OUT_AND_BACK_PHASE


def _spread_widening(template: MovementTemplate) -> float:
    """0 for consistent examples up to ``_MAX_SPREAD_WIDENING`` for varied ones."""
    spread = template.variability_metadata.get("reference_spread") or 0.0
    return min(_MAX_SPREAD_WIDENING, max(0.0, float(spread)))


def _centred(sequence: Sequence[FrameSample], modality: str) -> tuple[FrameSample, ...]:
    """Subtract each point's mean position, keeping only the path's shape.

    Removes where the user stands, where the movement starts, and fixed
    offsets from different body proportions, so DTW compares the pattern.
    """
    observed = [points for frame in sequence if (points := _points(frame, modality))]
    if not observed:
        return tuple(sequence)
    sums: dict[str, list[float]] = {}
    for points in observed:
        for key, (x, y) in points.items():
            total = sums.setdefault(key, [0.0, 0.0, 0.0])
            total[0] += x
            total[1] += y
            total[2] += 1
    mean = {key: (sx / n, sy / n) for key, (sx, sy, n) in sums.items()}

    def shift(key: str, point):
        mx, my = mean[key]
        return replace(point, x=point.x - mx, y=point.y - my)

    frames = []
    for frame in sequence:
        if modality == "prop_translation":
            frames.append(replace(
                frame, prop=shift("prop", frame.prop) if _usable(frame.prop) else None))
        elif modality == "pose":
            frames.append(replace(frame, pose={
                k: shift(k, p) for k, p in frame.pose.items() if _usable(p) and k in mean}))
        else:
            hands = _semantic_hands(frame.hands)
            frames.append(replace(frame, hands={
                k: shift(k, p) for k, p in hands.items() if _usable(p) and k in mean}))
    return tuple(frames)


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


def live_completion_window(
    template: MovementTemplate, samples: Sequence[FrameSample]
) -> Sequence[FrameSample]:
    """Recent samples for periodic live dynamic evaluation.

    Spans a lead-in plus ``_LIVE_WINDOW_DURATION_FACTOR`` times the learned
    duration, so an idle prefix never inflates per-tick comparison cost.
    Static holds already evaluate only their trailing hold window.
    """
    if template.movement_behavior == "static" or not samples:
        return samples
    window_ms = max(_LIVE_WINDOW_MIN_MS,
                    round(_LIVE_WINDOW_DURATION_FACTOR * template.duration_ms) + 1000)
    cutoff = samples[-1].timestamp_ms - window_ms
    start = len(samples)
    while start > 0 and samples[start - 1].timestamp_ms >= cutoff:
        start -= 1
    return samples[start:]


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


def _points(frame: FrameSample, modality: str) -> dict[str, tuple[float, float]]:
    if modality == "prop_translation":
        return {"prop": (frame.prop.x, frame.prop.y)} if _usable(frame.prop) else {}
    points = frame.pose if modality == "pose" else _semantic_hands(frame.hands)
    return {key: (p.x, p.y) for key, p in points.items() if _usable(p)}


def _mean_points(
    frames: Sequence[dict[str, tuple[float, float]]],
) -> dict[str, tuple[float, float]]:
    keys = set.intersection(*(set(frame) for frame in frames))
    return {
        key: (sum(f[key][0] for f in frames) / len(frames),
              sum(f[key][1] for f in frames) / len(frames))
        for key in keys
    }


def _displacement_match(
    reference: Sequence[FrameSample],
    candidate: Sequence[FrameSample],
    modality: str,
) -> tuple[float | None, float | None, float]:
    """Start-anchored net travel compared with the reference's net travel.

    Returns ``(progress, anchored_end_error, reference_travel)``: progress is the candidate's
    travel projected on the reference direction (1.0 = same net travel,
    negative = reversed); the error compares displacement vectors, so where
    the user starts in the frame does not matter, only what they did.
    """
    observed = [points for frame in candidate if (points := _points(frame, modality))]
    learned = [points for frame in reference if (points := _points(frame, modality))]
    if len(observed) < 2 or len(learned) < 2:
        return None, None, 0.0
    # The start is the lead-in observation (averaging would mix in early
    # motion); the end averages three observations, on both sides alike, so
    # one jittery final detection cannot flip or inflate the net travel.
    ref_start, ref_end = learned[0], _mean_points(learned[-3:])
    cand_start, cand_end = observed[0], _mean_points(observed[-3:])
    keys = ref_start.keys() & ref_end.keys() & cand_start.keys() & cand_end.keys()
    if not keys:
        return None, None, 0.0
    dot = norm = error = travel = 0.0
    for key in keys:
        rx, ry = ref_end[key][0] - ref_start[key][0], ref_end[key][1] - ref_start[key][1]
        cx, cy = cand_end[key][0] - cand_start[key][0], cand_end[key][1] - cand_start[key][1]
        dot += rx * cx + ry * cy
        norm += rx * rx + ry * ry
        error += math.hypot(rx - cx, ry - cy)
        travel += math.hypot(rx, ry)
    return (dot / norm if norm > 0 else None), error / len(keys), travel / len(keys)


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
    widening = _spread_widening(template)
    tolerance_scale *= 1.0 + widening
    min_progress = _MIN_DISPLACEMENT_PROGRESS - (
        (_MIN_DISPLACEMENT_PROGRESS - _MIN_WIDENED_DISPLACEMENT_PROGRESS)
        * widening / _MAX_SPREAD_WIDENING
    )

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
        progress, end_error, reference_travel = _displacement_match(
            reference, candidate, modality,
        )
        centred_reference = _centred(reference, modality)
        centred_candidate = _centred(candidate, modality)
        alignment = _dtw(centred_reference, centred_candidate, (modality,))
        errors = [
            error for i, j in alignment
            if (error := _modality_error(
                centred_reference[i], centred_candidate[j], modality)) is not None
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
        # Detector jitter accumulates path length but not sustained
        # displacement; a stationary attempt cannot satisfy this.
        sustained = sequence_motion(candidate, modality) >= max(
            0.6 * thresholds[modality],
            _MIN_SUSTAINED_MOTION_RATIO * sequence_motion(reference, modality),
        )
        # Completion asks "same movement?", not "same spot/size?": identity
        # is judged on start-anchored net travel, while absolute start/end
        # placement and amplitude are left to compare_sequence scoring.
        directional = reference_travel >= 0.5 * expected_range
        evidence.append(DynamicMotionEvidence(
            modality=modality,
            path_ratio=ratio,
            start_error=start_error,
            end_error=end_error,
            aligned_error=aligned_error,
            phase_progress=phase_progress,
            progress=progress,
            directional=directional,
            reference_travel=reference_travel,
            sustained=sustained,
            complete=(ratio >= _MIN_PATH_RATIO
                      and sustained
                      and _same_movement(directional, progress, phase_progress, min_progress)
                      and aligned_error is not None
                      and aligned_error <= _MAX_ALIGNED_MOTION_ERROR * tolerance_scale),
        ))
    quorum = len(moving_modalities) // 2 + 1 if len(moving_modalities) > 2 else 1
    if sum(item.complete for item in evidence) < quorum:
        return MOVEMENT_DETECTED
    # Prop presence is enforced by live validation above. A learned prop path
    # must show real travel (not a set-down prop) that roughly follows the
    # learned action; its exact shape and endpoints are scored by
    # compare_sequence rather than vetoing completion.
    if any(item.modality == "prop_translation" and not _prop_follows(item)
           for item in evidence):
        return MOVEMENT_DETECTED
    return MOVEMENT_COMPLETED


def _prop_follows(item: DynamicMotionEvidence) -> bool:
    """Meaningful prop travel in roughly the learned direction.

    Looser than full movement identity (a prop may move differently from the
    reference), but a still, barely moved, or opposite-travelling prop cannot
    pass on body/hand evidence alone.
    """
    if not item.sustained or item.path_ratio < _MIN_PROP_PATH_RATIO:
        return False
    if item.directional:
        return item.progress is not None and item.progress >= _MIN_PROP_PROGRESS
    return True


def apply_validated_attempt_floor(total: int) -> int:
    """Beginner-friendly minimum for an attempt completion already validated.

    Call only after ``evaluate_completion`` returned ``MOVEMENT_COMPLETED`` and
    the final comparison validated: completion is what rejects stationary,
    reversed, prop-less, and unrelated movement. Similarity still orders
    scores above the floor.
    """
    return max(total, VALIDATED_ATTEMPT_MIN_TOTAL)


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
                template.canonical_sequence[-1], frame, template.required_modalities,
                placement_scale=STATIC_LIVE_PLACEMENT_SCALE,
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
        static_frame_matches(target, frame, template.required_modalities,
                             placement_scale=STATIC_LIVE_PLACEMENT_SCALE)
        for frame in normalized
    ]
    if not all(matches[-3:]):
        return WAITING_FOR_MOVEMENT
    if not final_frames_still(
        normalized, static_match_modalities(target, template.required_modalities)
    ):
        return POSITION_DETECTED
    if sum(matches) / len(matches) < 0.85:
        return POSITION_DETECTED
    if hold[-1].timestamp_ms - hold[0].timestamp_ms < STATIC_HOLD_MS:
        return POSITION_DETECTED
    # Grip identity is gated by static_frame_matches above (wrist-relative
    # shape); rubric totals and Hand technique also grade absolute hand/arm
    # placement, so they score the hold rather than decide completion.
    comparison = compare_sequence(template, hold, assessment=True)
    # Grip/hand geometry is the primary static evidence; the prop only needs
    # presence and broad placement (enforced by static_frame_matches and
    # validation above), so ordinary YOLO jitter cannot block completion.
    if (comparison.component_scores["Prop path"] or 0) < 1:
        return POSITION_DETECTED
    return MOVEMENT_COMPLETED
