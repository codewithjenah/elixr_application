"""Evidence-based completion detection for live custom assessments."""

import math
from dataclasses import dataclass, replace
from typing import Any, Mapping, Sequence

from .template_engine import (
    MEANINGFUL_POSE_KEYS,
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
    _prepare_dtw_modality,
    _prepared_modality_error,
    _rotation_trace,
    _rotation_track_stable,
    compare_sequence,
    final_frames_still,
    landmark_tracks_motion,
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
# Pure-Python DTW is O(reference x candidate) per moving modality and retry
# candidate. Two observations per phase of the 32-frame canonical sequence is
# enough to judge path shape, so only the alignment input is strided; gates,
# timestamps, retries and observability keep the full candidate.
_LIVE_ALIGNMENT_MAX_SAMPLES = 64
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
# Beginner-friendly base for attempts that completion validated; the raw
# rubric quality fills the remaining 30 points (0/12 -> 70%, 12/12 -> 100%).
VALIDATED_ATTEMPT_BASE_PERCENT = 70.0


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


def _frame_points(prepared: Any) -> dict[str, tuple[float, float]]:
    """Usable ``(x, y)`` points of one ``_prepare_dtw_modality`` output."""
    if prepared is None:
        return {}
    if not isinstance(prepared, tuple):
        return {"prop": (prepared.x, prepared.y)}
    return {key: (p.x, p.y) for key, p in prepared[1].items() if p is not None}


@dataclass(frozen=True)
class _PreparedSequence:
    """Per-evaluation view of frames with modality data resolved once.

    Built once per ``evaluate_completion_segment`` call (never cached across
    calls), so semantic hands, usability and point mappings are derived once
    per frame instead of once per helper invocation. ``values`` holds exact
    ``_prepare_dtw_modality`` outputs, so ``_prepared_modality_error`` over
    them equals ``_modality_error`` over the frames.
    """

    frames: tuple[FrameSample, ...]
    values: Mapping[str, tuple[Any, ...]]
    points: Mapping[str, tuple[dict[str, tuple[float, float]], ...]]

    def __len__(self) -> int:
        return len(self.frames)

    def tail(self, start: int) -> "_PreparedSequence":
        return _PreparedSequence(
            self.frames[start:],
            {m: v[start:] for m, v in self.values.items()},
            {m: p[start:] for m, p in self.points.items()},
        )

    def error(self, i: int, other: "_PreparedSequence", j: int, modality: str) -> float | None:
        return _prepared_modality_error(self.values[modality][i], other.values[modality][j])


def _prepare(frames: Sequence[FrameSample], modalities: Sequence[str]) -> _PreparedSequence:
    frames = tuple(frames)
    values = {m: tuple(_prepare_dtw_modality(frame, m) for frame in frames) for m in modalities}
    return _PreparedSequence(
        frames, values, {m: tuple(_frame_points(v) for v in vs) for m, vs in values.items()})


def _centred(
    sequence: _PreparedSequence, modality: str, limit: int | None = None
) -> tuple[FrameSample, ...]:
    """Subtract each point's mean position, keeping only the path's shape.

    Removes where the user stands, where the movement starts, and fixed
    offsets from different body proportions, so DTW compares the pattern.
    The mean always spans the full sequence; with ``limit`` only the evenly
    strided frames ``_bounded_samples`` would keep are materialised.
    """
    indexes = (range(len(sequence)) if limit is None
               else _bounded_samples(range(len(sequence)), limit))
    observed = [points for points in sequence.points[modality] if points]
    if not observed:
        return tuple(sequence.frames[i] for i in indexes)
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
    for i in indexes:
        frame, value = sequence.frames[i], sequence.values[modality][i]
        if modality == "prop_translation":
            frames.append(replace(
                frame, prop=shift("prop", value) if value is not None else None))
        else:
            # ``value[1]`` keeps the pose / semantic-hand order, unusable as None.
            shifted = {k: shift(k, p) for k, p in value[1].items() if p is not None and k in mean}
            frames.append(replace(frame, **{"pose" if modality == "pose" else "hands": shifted}))
    return tuple(frames)


def _bounded_samples(
    samples: Sequence[FrameSample], limit: int = _MAX_COMPLETION_SAMPLES
) -> tuple[FrameSample, ...]:
    """Exactly ``limit`` evenly spread real observations, keeping first and last.

    For ``n > limit`` the step ``(n - 1) / (limit - 1)`` exceeds 1, so the
    floored indexes are strictly increasing from 0 to ``n - 1``.
    """
    count = len(samples)
    if count <= limit:
        return tuple(samples)
    return tuple(samples[i * (count - 1) // (limit - 1)] for i in range(limit))


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


def _sequence_range(sequence: _PreparedSequence, modality: str) -> float:
    if len(sequence) < 2:
        return 0.0
    return max(
        (
            error
            for index in range(1, len(sequence))
            if (error := sequence.error(0, sequence, index, modality)) is not None
        ),
        default=0.0,
    )


def _sequence_path_length(
    sequence: _PreparedSequence, modality: str, *, bridge_gap_ms: int = 0
) -> float:
    """Sum observed travel; across a short miss use only endpoint displacement."""
    total = 0.0
    previous: tuple[int, FrameSample] | None = None
    for index, frame in enumerate(sequence.frames):
        # Any usable point is exactly when a frame's self-error is defined.
        if not sequence.points[modality][index]:
            continue
        if previous is not None:
            previous_index, previous_frame = previous
            if (index == previous_index + 1 or
                    (bridge_gap_ms > 0 and
                     frame.timestamp_ms - previous_frame.timestamp_ms <= bridge_gap_ms)):
                error = sequence.error(previous_index, sequence, index, modality)
                if error is not None:
                    total += error
        previous = (index, frame)
    return total


def _sequence_motion(sequence: _PreparedSequence, modality: str) -> float:
    """``sequence_motion`` over prepared frames (no per-call hand re-keying)."""
    if modality == "prop_translation":
        return sequence_motion(sequence.frames, modality)
    tracks: dict[str, list] = {}
    for value in sequence.values[modality]:
        for key, point in value[1].items():
            if point is not None and (modality != "pose" or key in MEANINGFUL_POSE_KEYS):
                tracks.setdefault(key, []).append(point)
    return landmark_tracks_motion(tracks)


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
    reference: _PreparedSequence,
    candidate: _PreparedSequence,
    modality: str,
) -> tuple[float | None, float | None, float]:
    """Start-anchored net travel compared with the reference's net travel.

    Returns ``(progress, anchored_end_error, reference_travel)``: progress is the candidate's
    travel projected on the reference direction (1.0 = same net travel,
    negative = reversed); the error compares displacement vectors, so where
    the user starts in the frame does not matter, only what they did.
    """
    observed = [points for points in candidate.points[modality] if points]
    learned = [points for points in reference.points[modality] if points]
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
    normalized: _PreparedSequence,
    moving_thresholds: Mapping[str, float],
) -> int | None:
    baselines = {
        modality: next(
            (index for index, points in enumerate(normalized.points[modality]) if points),
            None,
        )
        for modality in moving_thresholds
    }
    for index in range(1, len(normalized)):
        for modality, baseline in baselines.items():
            if baseline is None or baseline >= index:
                continue
            distance = normalized.error(baseline, normalized, index, modality)
            # Start evidence may appear before full meaningful motion. The
            # later sustained-displacement gate still rejects detector jitter.
            start_threshold = min(0.03, moving_thresholds[modality] * 0.5)
            if distance is not None and distance >= start_threshold:
                return max(baseline, index - 3)
    return None


def _motion_unit(template: MovementTemplate) -> float | None:
    value = template.variability_metadata.get("motion_unit")
    return float(value) if value is not None and value > 0 else None


def _motion(template: MovementTemplate, sequence: _PreparedSequence, modality: str) -> float:
    """The motion measure authoring used; legacy templates keep the old one."""
    if _motion_unit(template) is None:
        return _sequence_range(sequence, modality)
    return _sequence_motion(sequence, modality)


def _moving_thresholds(
    template: MovementTemplate, reference: _PreparedSequence | None = None
) -> dict[str, float]:
    """Learned moving modalities and their meaningful-motion thresholds.

    Uses the authoring thresholds and motion measure in the template's own
    units, so a small movement accepted at authoring is also completable
    live. Legacy templates without ``motion_unit`` keep the original rule.
    """
    thresholds = motion_thresholds(_motion_unit(template))
    if reference is None:
        reference = _prepare(template.canonical_sequence, template.required_modalities)
    return {
        modality: thresholds[modality]
        for modality in template.required_modalities
        if _motion(template, reference, modality) >= thresholds[modality]
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
    thresholds = _moving_thresholds(template)
    return _movement_start_index(_prepare(normalized, list(thresholds)), thresholds)


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
    return evaluate_completion_segment(template, samples)[0]


# A failed attempt must not stay the anchor of every later attempt. After an
# attempt fails, completion re-anchors where the motion next turns around or
# comes to rest (the natural start of a retry). Restarts are bounded and each
# candidate rejects cheaply before DTW, so the live 0.5 s evaluation stays
# cheap. Every re-anchored candidate passes the same direction,
# sustained-motion, prop and observability gates.
_MAX_ATTEMPT_RESTARTS = 4
# Frames spanned by the direction estimate used to find turnarounds; a span
# (not frame-to-frame) keeps detector jitter from looking like a reversal.
_TURN_SPAN = 3


def _centroid(points: Mapping[str, tuple[float, float]]) -> tuple[float, float] | None:
    if not points:
        return None
    return (sum(x for x, _ in points.values()) / len(points),
            sum(y for _, y in points.values()) / len(points))


def _next_attempt_boundary(
    normalized: _PreparedSequence,
    start: int,
    thresholds: Mapping[str, float],
) -> int | None:
    """First index after ``start`` where learned motion reverses or rests.

    That point ends the current attempt and is where a retry begins. Returns
    ``None`` when the motion never turns around, i.e. no new attempt began.
    """
    for modality, threshold in thresholds.items():
        rest = 0.25 * min(0.03, threshold * 0.5)
        previous: tuple[float, float] | None = None
        moved = False
        points = normalized.points[modality]
        for index in range(start + _TURN_SPAN, len(normalized)):
            now = _centroid(points[index])
            before = _centroid(points[index - _TURN_SPAN])
            if now is None or before is None:
                previous = None
                continue
            vector = (now[0] - before[0], now[1] - before[1])
            magnitude = math.hypot(*vector)
            if moved and magnitude < rest:
                return index
            if (previous is not None and magnitude >= rest
                    and vector[0] * previous[0] + vector[1] * previous[1] < 0):
                return index
            if magnitude >= rest:
                moved = True
                previous = vector
    return None


def evaluate_completion_segment(
    template: MovementTemplate, samples: Sequence[FrameSample]
) -> tuple[str, int | None]:
    """Progress plus the start timestamp of the attempt it describes.

    The returned timestamp is the completed attempt's start when completed,
    otherwise the latest motion onset (the attempt still in progress), or
    ``None`` while waiting. Static holds report no segment start.
    """
    if template.movement_behavior == "static":
        return _evaluate_static_completion(template, samples), None
    bounded = _bounded_samples(samples)
    if len(bounded) < 2:
        return WAITING_FOR_MOVEMENT, None

    required = template.required_modalities
    # One prepared view of the reference and the bounded live sequence serves
    # every restart and gate in this call, so per-frame preprocessing scales
    # with the frame count rather than with helper calls.
    reference = _prepare(template.canonical_sequence, required)
    thresholds = _moving_thresholds(template, reference)
    if not thresholds:
        return _evaluate_dynamic_candidate(
            template, samples, bounded, None, reference, 0, thresholds), None
    normalized = _prepare(normalize_sequence(
        bounded,
        use_pose_anchor="pose" in required,
        required_hand_sides=template.required_hand_sides,
    ), list(thresholds))
    offset = 0
    best: tuple[str, int | None] = (WAITING_FOR_MOVEMENT, None)
    for _ in range(_MAX_ATTEMPT_RESTARTS + 1):
        start = _movement_start_index(normalized.tail(offset), thresholds)
        if start is None:
            break
        start += offset
        status = _evaluate_dynamic_candidate(
            template, samples, bounded, normalized, reference, start, thresholds)
        start_ms = normalized.frames[start].timestamp_ms
        if status == MOVEMENT_COMPLETED:
            return status, start_ms
        if status == MOVEMENT_DETECTED or best[0] == WAITING_FOR_MOVEMENT:
            best = (status, start_ms if status != WAITING_FOR_MOVEMENT else best[1])
        # Re-anchor where this failed attempt turns around or rests, so the
        # retry is compared from its own start, not the failed attempt's tail.
        boundary = _next_attempt_boundary(normalized, start, thresholds)
        if boundary is None or len(normalized) - boundary < 2:
            break
        offset = boundary
    return best


def _evaluate_dynamic_candidate(
    template: MovementTemplate,
    samples: Sequence[FrameSample],
    bounded: Sequence[FrameSample],
    normalized: _PreparedSequence | None,
    reference: _PreparedSequence,
    movement_start: int,
    thresholds: Mapping[str, float],
) -> str:
    """Completion gates for one candidate attempt beginning at ``movement_start``."""
    required = template.required_modalities
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

    assert normalized is not None
    candidate = normalized.tail(movement_start)
    if not candidate.frames:
        return WAITING_FOR_MOVEMENT
    candidate_start_ms = candidate.frames[0].timestamp_ms
    source_candidate = tuple(
        frame for frame in samples if frame.timestamp_ms >= candidate_start_ms
    )
    # Sustained motion is reused by the movement and sustained gates below.
    motion_memo: dict[str, float] = {}

    def candidate_motion(modality: str) -> float:
        if modality not in motion_memo:
            motion_memo[modality] = _sequence_motion(candidate, modality)
        return motion_memo[modality]

    legacy_motion = _motion_unit(template) is None
    movement_detected = any(
        (_sequence_range(candidate, modality) if legacy_motion
         else candidate_motion(modality))
        >= max(thresholds[modality], _motion(template, reference, modality) * 0.20)
        for modality in moving_modalities
    )
    if not movement_detected:
        return WAITING_FOR_MOVEMENT
    if len(candidate) < MIN_TRACKING_SAMPLES:
        return MOVEMENT_DETECTED

    candidate_duration = candidate.frames[-1].timestamp_ms - candidate_start_ms
    if candidate_duration < _MIN_DYNAMIC_DURATION_MS:
        return MOVEMENT_DETECTED

    # Each learned moving modality contributes evidence. A short glitch in one
    # modality cannot veto a well-observed sequence in the others, but every
    # required modality still has to satisfy live observability below. Cheap
    # gates run first; DTW and observability validation run only for a
    # candidate that could still complete (all gates are required anyway).
    evidence: list[DynamicMotionEvidence] = []
    for modality in moving_modalities:
        expected_range = _sequence_range(reference, modality)
        expected_path = _sequence_path_length(reference, modality)
        observed_path = _sequence_path_length(candidate, modality, bridge_gap_ms=450)
        start_error = next(
            (error for j in range(min(3, len(candidate)))
             if (error := reference.error(0, candidate, j, modality)) is not None),
            None,
        )
        progress, end_error, reference_travel = _displacement_match(
            reference, candidate, modality,
        )
        ratio = observed_path / expected_path if expected_path > 0 else 0.0
        last = len(reference) - 1
        recent = next(
            (j for j in reversed(range(len(candidate)))
             if reference.error(last, candidate, j, modality) is not None),
            None,
        )
        phase_errors = [
            (error, -index) for index in range(len(reference))
            if recent is not None
            and (error := reference.error(index, candidate, recent, modality)) is not None
        ]
        phase_progress = (
            -min(phase_errors)[1] / max(1, len(reference) - 1)
            if phase_errors else 0.0
        )
        # Detector jitter accumulates path length but not sustained
        # displacement; a stationary attempt cannot satisfy this.
        sustained = candidate_motion(modality) >= max(
            0.6 * thresholds[modality],
            _MIN_SUSTAINED_MOTION_RATIO * _sequence_motion(reference, modality),
        )
        # Completion asks "same movement?", not "same spot/size?": identity
        # is judged on start-anchored net travel, while absolute start/end
        # placement and amplitude are left to compare_sequence scoring.
        directional = reference_travel >= 0.5 * expected_range
        aligned_error = None
        if (ratio >= _MIN_PATH_RATIO and sustained
                and _same_movement(directional, progress, phase_progress, min_progress)):
            centred_reference = _centred(reference, modality)
            # Centre on the full candidate, then stride; path indexes below
            # refer to this exact bounded sequence.
            centred_candidate = _centred(candidate, modality, _LIVE_ALIGNMENT_MAX_SAMPLES)
            alignment = _dtw(centred_reference, centred_candidate, (modality,))
            errors = [
                error for i, j in alignment
                if (error := _modality_error(
                    centred_reference[i], centred_candidate[j], modality)) is not None
            ]
            aligned_error = sum(errors) / len(errors) if errors else None
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
    # Prop presence is enforced by live validation below. A learned prop path
    # must show real travel (not a set-down prop) that roughly follows the
    # learned action; its exact shape and endpoints are scored by
    # compare_sequence rather than vetoing completion.
    if any(item.modality == "prop_translation" and not _prop_follows(item)
           for item in evidence):
        return MOVEMENT_DETECTED
    validation = validate_assessment_sequence(
        source_candidate,
        required,
        required_hand_sides=template.required_hand_sides,
        template=template,
    )
    if not validation.valid:
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


def validated_attempt_score_percent(raw_total: int) -> float:
    """User-facing 70..100 score for an attempt completion already validated.

    Call only after ``evaluate_completion`` returned ``MOVEMENT_COMPLETED`` and
    the final comparison validated: completion is what rejects stationary,
    reversed, prop-less, and unrelated movement. The raw 0..12 rubric total
    is never altered; it linearly fills the range above the completion base.
    """
    fraction = min(1.0, max(0.0, raw_total / 12))
    return round(VALIDATED_ATTEMPT_BASE_PERCENT
                 + (100.0 - VALIDATED_ATTEMPT_BASE_PERCENT) * fraction, 1)


def validated_attempt_total(score_percent: float) -> int:
    """0..12 rubric-scale equivalent of a validated score, never overstated.

    Classroom persistence stores a 0..12 total whose performance level must
    match it, so the saved grade must agree with the displayed percentage.
    """
    return min(12, math.floor(score_percent * 12 / 100 + 1e-9))


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
