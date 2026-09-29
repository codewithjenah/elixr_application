"""Evidence-based completion detection for live custom assessments."""

import math
from bisect import bisect_left
from dataclasses import dataclass, field, replace
from typing import Any, Mapping, Sequence

import numpy as np

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
    median3_filter,
    motion_thresholds,
    normalize_sequence,
    sequence_motion,
    static_frame_matches,
    static_match_modalities,
    top_ranges_motion,
    dynamic_prop_gap_policy,
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


# One landmark track of a whole prepared sequence: the frame indexes it was
# observed at and its 3-sample median-filtered coordinates (index ``i`` is the
# median centred on observation ``i + 1``), as numpy arrays.
_MotionTrack = tuple[np.ndarray, np.ndarray, np.ndarray]
# Squared distances within this relative margin of the largest are re-measured
# with ``math.hypot``; float64 rounding of ``dx*dx + dy*dy`` is ~1e-15, so the
# exact maximum is always among them.
_ARGMAX_MARGIN = 1e-9


def _track_range(fx: np.ndarray, fy: np.ndarray, start: int, stop: int) -> float:
    """``max(math.hypot(fx[i] - fx[start], fy[i] - fy[start]))`` for ``start <= i < stop``.

    Vectorised to find the farthest candidates, then measured exactly with
    ``math.hypot`` so the value is bit-identical to the scalar scan.
    """
    dx = fx[start:stop] - fx[start]
    dy = fy[start:stop] - fy[start]
    squared = dx * dx + dy * dy
    largest = float(squared.max())
    if largest > 1e-200:
        candidates = np.flatnonzero(squared >= largest * (1.0 - _ARGMAX_MARGIN))
    else:
        # Degenerate/underflowing distances: measure every moved sample.
        candidates = np.flatnonzero((dx != 0) | (dy != 0))
        if not candidates.size:
            return 0.0
    return max(math.hypot(float(dx[i]), float(dy[i])) for i in candidates)


def _build_motion_tracks(values: Sequence[Any], modality: str) -> list[_MotionTrack]:
    """Pose/hands landmark tracks exactly as ``_sequence_motion`` groups them."""
    positions: dict[str, list[int]] = {}
    xs: dict[str, list[float]] = {}
    ys: dict[str, list[float]] = {}
    for index, value in enumerate(values):
        for key, point in value[1].items():
            if point is not None and (modality != "pose" or key in MEANINGFUL_POSE_KEYS):
                if key not in positions:
                    positions[key], xs[key], ys[key] = [], [], []
                positions[key].append(index)
                xs[key].append(point.x)
                ys[key].append(point.y)
    return [(np.asarray(positions[key], dtype=np.int64),
             np.asarray(median3_filter(xs[key]), dtype=np.float64),
             np.asarray(median3_filter(ys[key]), dtype=np.float64))
            for key in positions]


@dataclass(frozen=True)
class _PreparedSequence:
    """Per-evaluation view of frames with modality data resolved once.

    Built once per ``evaluate_completion_segment`` call (never cached across
    calls), so semantic hands, usability and point mappings are derived once
    per frame instead of once per helper invocation. ``values`` holds exact
    ``_prepare_dtw_modality`` outputs, so ``_prepared_modality_error`` over
    them equals ``_modality_error`` over the frames.

    ``tail``/``span`` views share ``_root_values`` and ``_tracks`` with the
    sequence they were cut from; ``_offset`` locates the view inside it, so
    every candidate's sustained motion reuses one set of landmark tracks.
    """

    frames: tuple[FrameSample, ...]
    values: Mapping[str, tuple[Any, ...]]
    points: Mapping[str, tuple[dict[str, tuple[float, float]], ...]]
    _offset: int = 0
    _root_values: Mapping[str, tuple[Any, ...]] | None = None
    _tracks: dict[str, list[_MotionTrack]] = field(
        default_factory=dict, compare=False, repr=False)

    def __len__(self) -> int:
        return len(self.frames)

    def tail(self, start: int) -> "_PreparedSequence":
        return self.span(start, len(self.frames))

    def span(self, start: int, stop: int) -> "_PreparedSequence":
        start, stop, _ = slice(start, stop).indices(len(self.frames))
        stop = max(start, stop)
        return _PreparedSequence(
            self.frames[start:stop],
            {m: v[start:stop] for m, v in self.values.items()},
            {m: p[start:stop] for m, p in self.points.items()},
            self._offset + start,
            self._root_values if self._root_values is not None else self.values,
            self._tracks,
        )

    def landmark_motion(self, modality: str) -> float:
        """``landmark_tracks_motion`` of this view's pose/hands tracks."""
        root = self._root_values if self._root_values is not None else self.values
        tracks = self._tracks.get(modality)
        if tracks is None:
            tracks = self._tracks[modality] = _build_motion_tracks(root[modality], modality)
        first, stop = self._offset, self._offset + len(self.frames)
        ranges = []
        for positions, fx, fy in tracks:
            p = int(np.searchsorted(positions, first))
            q = int(np.searchsorted(positions, stop))
            if q - p < 3:
                continue
            # A view's own filtered track is fx/fy[p .. q-3]: its median
            # windows lie wholly inside the view, so values are identical.
            ranges.append(_track_range(fx, fy, p, q - 2))
        return top_ranges_motion(ranges)

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
    sequence: _PreparedSequence, modality: str, *, bridge_gap_ms: int = 0,
    certified_gaps: frozenset[tuple[int, int]] = frozenset(),
) -> float:
    """Sum observed travel; across a short miss use only endpoint displacement.

    ``certified_gaps`` holds ``(before_ms, after_ms)`` prop gaps that
    ``dynamic_prop_gap_policy`` certified as airborne detector loss; they are
    bridged by the same endpoint displacement (never interpolated frames).
    """
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
                     frame.timestamp_ms - previous_frame.timestamp_ms <= bridge_gap_ms) or
                    (previous_frame.timestamp_ms, frame.timestamp_ms) in certified_gaps):
                error = sequence.error(previous_index, sequence, index, modality)
                if error is not None:
                    total += error
        previous = (index, frame)
    return total


def _sequence_motion(sequence: _PreparedSequence, modality: str) -> float:
    """``sequence_motion`` over prepared frames (no per-call hand re-keying)."""
    if modality == "prop_translation":
        return sequence_motion(sequence.frames, modality)
    return sequence.landmark_motion(modality)


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
    # Normalisation is per frame, so only the three frames used are normalised.
    recent = normalize_sequence(
        _bounded_samples(samples)[-3:],
        use_pose_anchor="pose" in template.required_modalities,
        required_hand_sides=template.required_hand_sides,
    )
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
# A wrong start can flow into a correct execution without any detectable rest
# or reversal (e.g. a curved turn), leaving the user displaced so no onset-
# anchored candidate can match. Completion then also asks "did the newest
# frames just finish one valid execution?" over a few suffixes ending at the
# latest frame, lengths spaced by a fraction of the learned duration. The
# count is fixed and anchored to the newest frame, so successive live ticks
# probe shifted boundaries while per-call work stays bounded.
_MAX_SUFFIX_CANDIDATES = 6
_MIN_SUFFIX_DURATION_FACTOR = 0.4
_SUFFIX_STEPS_PER_DURATION = 3
# A suffix must begin where the learned motion is not already under way
# (after a wrong, reversed, curved or paused prefix): at most this share of
# the learned travel/turn in the learned direction just before its start.
_MAX_LEAD_IN_PROGRESS = 0.25
# Every onset and suffix candidate is screened with the cheap gates, but only
# this many gate-passing candidates (closest learned path length first) pay
# for pure-Python DTW in one call, so one evaluation performs at most this
# many DTWs per moving modality however many restarts and suffixes exist.
_MAX_ALIGNED_CANDIDATES = 2


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


def _suffix_starts(template: MovementTemplate, frames: Sequence[FrameSample]) -> list[int]:
    """Chronological starts of the bounded suffix candidates of ``frames``."""
    if len(frames) < 2:
        return []
    duration = max(1, template.duration_ms)
    min_length = max(_MIN_DYNAMIC_DURATION_MS,
                     round(_MIN_SUFFIX_DURATION_FACTOR * duration))
    step = max(1, round(duration / _SUFFIX_STEPS_PER_DURATION))
    last = frames[-1].timestamp_ms
    starts: set[int] = set()
    index = len(frames)
    for k in range(_MAX_SUFFIX_CANDIDATES):
        cutoff = last - min_length - k * step
        if cutoff <= frames[0].timestamp_ms:
            break
        while index > 0 and frames[index - 1].timestamp_ms >= cutoff:
            index -= 1
        starts.add(index)
    return sorted(starts)


def _lead_in_index(template: MovementTemplate, frames: Sequence[FrameSample], start: int) -> int:
    """First frame of the suffix spacing just before ``start``."""
    cutoff = frames[start].timestamp_ms - max(
        1, round(template.duration_ms / _SUFFIX_STEPS_PER_DURATION))
    index = start
    while index > 0 and frames[index - 1].timestamp_ms >= cutoff:
        index -= 1
    return index


def _continues_learned_rotation(
    template: MovementTemplate, frames: Sequence[FrameSample], start: int
) -> bool:
    """Whether the bottle was already turning the learned way into ``start``.

    A suffix may drop a wrong or unrelated prefix, but must not cut one
    learned turn out of a longer same-direction spin (an over-rotation).
    """
    assert template.rotation_trace is not None
    lead = frames[_lead_in_index(template, frames, start):start + 1]
    if len(lead) < 2:
        return False
    learned = template.rotation_trace.total_signed_rad
    turned = _rotation_trace(lead).total_signed_rad
    return turned * math.copysign(1.0, learned) >= _MAX_LEAD_IN_PROGRESS * abs(learned)


def _continues_learned_travel(
    template: MovementTemplate,
    reference: "_ReferenceContext",
    normalized: _PreparedSequence,
    start: int,
    modalities: Sequence[str],
) -> bool:
    """Whether a directional movement was already under way into ``start``.

    Mirrors the rotation rule: a suffix must not cut a learned-size slice out
    of a larger same-direction movement (and score only the flattering part).
    """
    lead = normalized.span(_lead_in_index(template, normalized.frames, start), start + 1)
    for modality in modalities:
        progress, _, travel = _displacement_match(reference.sequence, lead, modality)
        if (travel >= 0.5 * reference.range[modality]
                and progress is not None and progress >= _MAX_LEAD_IN_PROGRESS):
            return True
    return False


class LiveCompletionCache:
    """Per-recording memo of work that never changes between live ticks.

    Normalisation and DTW preparation are per frame, so a live sample is
    prepared once when it first enters the window instead of on every 0.5 s
    tick; the canonical reference context depends only on the template.
    Results are identical to uncached evaluation. Entries hold the sample
    itself, so an ``id`` is only reused after its entry was pruned. Use one
    cache per recording, from a single thread.
    """

    def __init__(self) -> None:
        self._template: MovementTemplate | None = None
        self._reference: tuple[_PreparedSequence, dict[str, float], Any] | None = None
        # id(sample) -> (sample, normalised frame, {modality: (value, points)}, seq)
        self._frames: dict[
            int, tuple[FrameSample, FrameSample, dict[str, tuple[Any, Any]], int]] = {}
        self._next_seq = 0
        # Recording-wide pose/hands landmark tracks, extended as samples arrive:
        # modality -> key -> (seqs, xs, ys, filtered xs, filtered ys).
        self._tracks: dict[str, dict[str, tuple[list, list, list, list, list]]] = {}
        self._track_modalities: tuple[str, ...] | None = None

    def _bind(self, template: MovementTemplate) -> None:
        if self._template is not template:
            self._template = template
            self._reference = None
            self._frames = {}
            self._next_seq = 0
            self._tracks = {}
            self._track_modalities = None

    def _extend_tracks(self, seq: int, prepared: Mapping[str, tuple[Any, Any]]) -> None:
        """Append one new sample's landmarks; each median is computed once."""
        for modality in self._track_modalities or ():
            tracks = self._tracks.setdefault(modality, {})
            for key, point in prepared[modality][0][1].items():
                if point is None or (modality == "pose" and key not in MEANINGFUL_POSE_KEYS):
                    continue
                track = tracks.get(key)
                if track is None:
                    track = tracks[key] = ([], [], [], [], [])
                seqs, xs, ys, fxs, fys = track
                seqs.append(seq)
                xs.append(point.x)
                ys.append(point.y)
                if len(xs) >= 3:
                    fxs.extend(median3_filter(xs[-3:]))
                    fys.extend(median3_filter(ys[-3:]))

    def _window_tracks(self, first_seq: int, last_seq: int) -> dict[str, list[_MotionTrack]]:
        """``_build_motion_tracks`` of a contiguous window, from the global tracks.

        A median's neighbours are adjacent observations of the same landmark;
        inside a contiguous run of samples those are the same globally and in
        the window, so the window's filtered values are a slice of the global.
        """
        result: dict[str, list[_MotionTrack]] = {}
        for modality, tracks in self._tracks.items():
            window: list[_MotionTrack] = []
            for seqs, _, _, fxs, fys in tracks.values():
                a = bisect_left(seqs, first_seq)
                b = bisect_left(seqs, last_seq + 1, a)
                if b == a:
                    continue
                window.append((
                    np.asarray(seqs[a:b], dtype=np.int64) - first_seq,
                    np.asarray(fxs[a:max(a, b - 2)], dtype=np.float64),
                    np.asarray(fys[a:max(a, b - 2)], dtype=np.float64),
                ))
            result[modality] = window
        return result

    def reference(self, template: MovementTemplate):
        """``(prepared_reference, thresholds, reference_context or None)``."""
        self._bind(template)
        if self._reference is None:
            prepared = _prepare(template.canonical_sequence, template.required_modalities)
            thresholds = _moving_thresholds(template, prepared)
            context = (_reference_context(template, prepared, thresholds)
                       if thresholds else None)
            self._reference = (prepared, thresholds, context)
        return self._reference

    def prepare(
        self, template: MovementTemplate, samples: Sequence[FrameSample],
        modalities: Sequence[str],
    ) -> _PreparedSequence:
        """``_prepare(normalize_sequence(samples, ...), modalities)``, memoised."""
        self._bind(template)
        track_modalities = tuple(m for m in modalities if m != "prop_translation")
        if self._track_modalities is None:
            self._track_modalities = track_modalities
        missing = [s for s in samples
                   if (entry := self._frames.get(id(s))) is None or entry[0] is not s]
        if missing:
            normalised = normalize_sequence(
                missing,
                use_pose_anchor="pose" in template.required_modalities,
                required_hand_sides=template.required_hand_sides,
            )
            for sample, frame in zip(missing, normalised):
                prepared = {}
                for modality in modalities:
                    value = _prepare_dtw_modality(frame, modality)
                    prepared[modality] = (value, _frame_points(value))
                self._frames[id(sample)] = (sample, frame, prepared, self._next_seq)
                if self._track_modalities == track_modalities:
                    self._extend_tracks(self._next_seq, prepared)
                self._next_seq += 1
        # Only the current window is kept; older samples never return.
        self._frames = {id(s): self._frames[id(s)] for s in samples}
        frames = []
        seqs = []
        values: dict[str, list[Any]] = {m: [] for m in modalities}
        points: dict[str, list[Any]] = {m: [] for m in modalities}
        for sample in samples:
            _, frame, prepared, seq = self._frames[id(sample)]
            frames.append(frame)
            seqs.append(seq)
            for modality in modalities:
                item = prepared.get(modality)
                if item is None:
                    value = _prepare_dtw_modality(frame, modality)
                    item = prepared[modality] = (value, _frame_points(value))
                values[modality].append(item[0])
                points[modality].append(item[1])
        # Reuse the recording-wide tracks only for a contiguous live window in
        # arrival order (a strided or reordered window is rebuilt per call).
        tracks: dict[str, list[_MotionTrack]] = {}
        if (seqs and self._track_modalities == track_modalities
                and all(b == a + 1 for a, b in zip(seqs, seqs[1:]))):
            tracks = self._window_tracks(seqs[0], seqs[-1])
            for modality in track_modalities:
                tracks.setdefault(modality, [])
        return _PreparedSequence(
            tuple(frames),
            {m: tuple(v) for m, v in values.items()},
            {m: tuple(p) for m, p in points.items()},
            _tracks=tracks,
        )


def evaluate_completion_segment(
    template: MovementTemplate, samples: Sequence[FrameSample],
    *, cache: LiveCompletionCache | None = None,
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
    if cache is not None:
        prepared_reference, thresholds, cached_reference = cache.reference(template)
    else:
        prepared_reference = _prepare(template.canonical_sequence, required)
        thresholds = _moving_thresholds(template, prepared_reference)
        cached_reference = None
    # Every candidate passes the same gates; among those that pass, the
    # segment that best fits the learned movement is reported, so a tolerated
    # failed prefix is not scored as part of the valid execution. Full-source
    # observability runs last, best fit first, normally once per call.
    passed: list[tuple[float, int | None, Sequence[FrameSample]]] = []
    if not thresholds:
        # Rotation-only: an earlier wrong turn must not cancel a later valid
        # one in the whole-window trace, so newest suffixes are also judged.
        status, fit = _evaluate_rotation_candidate(template, bounded)
        if status == MOVEMENT_COMPLETED:
            passed.append((fit, None, bounded))
        if template.rotation_trace is not None:
            for start in _suffix_starts(template, bounded):
                if start == 0 or _continues_learned_rotation(template, bounded, start):
                    continue
                suffix_status, fit = _evaluate_rotation_candidate(template, bounded[start:])
                if suffix_status == MOVEMENT_COMPLETED:
                    passed.append((fit, bounded[start].timestamp_ms, bounded[start:]))
        completed = _best_observable(template, passed)
        if completed is not None:
            return MOVEMENT_COMPLETED, completed[1]
        return (MOVEMENT_DETECTED if status == MOVEMENT_COMPLETED else status), None
    if cache is not None:
        reference = cached_reference
        normalized = cache.prepare(template, bounded, list(thresholds))
    else:
        reference = _reference_context(template, prepared_reference, thresholds)
        normalized = _prepare(normalize_sequence(
            bounded,
            use_pose_anchor="pose" in required,
            required_hand_sides=template.required_hand_sides,
        ), list(thresholds))
    # Certified on the raw (image-space) bounded frames, whose timestamps the
    # normalized candidates share; only the prop path may bridge them.
    certified_gaps = (frozenset(dynamic_prop_gap_policy(bounded).certified_gaps)
                      if "prop_translation" in thresholds else frozenset())
    offset = 0
    best: tuple[str, int | None] = (WAITING_FOR_MOVEMENT, None)
    tried: set[int] = set()
    # Candidates that passed every cheap gate; only these may pay for DTW.
    viable: list[_ScreenedCandidate] = []
    for _ in range(_MAX_ATTEMPT_RESTARTS + 1):
        start = _movement_start_index(normalized.tail(offset), thresholds)
        if start is None:
            break
        start += offset
        tried.add(start)
        screened = _screen_dynamic_candidate(
            template, samples, normalized, reference, start, thresholds,
            certified_gaps)
        # A gate-passing onset is reported as in progress unless alignment and
        # observability confirm it below, exactly like a failed alignment.
        if isinstance(screened, str):
            status = screened
        else:
            status = MOVEMENT_DETECTED
            viable.append(screened)
        start_ms = normalized.frames[start].timestamp_ms
        if status == MOVEMENT_DETECTED or best[0] == WAITING_FOR_MOVEMENT:
            best = (status, start_ms if status != WAITING_FOR_MOVEMENT else best[1])
        # Re-anchor where this attempt turns around or rests, so a retry is
        # compared from its own start, not the earlier attempt's tail.
        boundary = _next_attempt_boundary(normalized, start, thresholds)
        if boundary is None or len(normalized) - boundary < 2:
            break
        offset = boundary
    if not tried:
        return best
    # A failed prefix is disposable: a valid execution in the newest frames
    # completes on its own even without a detectable rest or reversal before
    # it. Suffixes never replace the reported in-progress onset (they are not
    # attempts); they only compete as completed segments.
    first_onset = min(tried)
    for start in _suffix_starts(template, normalized.frames):
        if (start <= first_onset or start in tried or _continues_learned_travel(
                template, reference, normalized, start, list(thresholds))):
            continue
        screened = _screen_dynamic_candidate(
            template, samples, normalized, reference, start, thresholds,
            certified_gaps)
        if not isinstance(screened, str):
            viable.append(screened)
    # Bounded alignment: the candidates whose path length best matches the
    # learned path (a whole execution, not a failed prefix plus it or a tail
    # slice of it) pay for DTW; the newer start wins a tie.
    ranked = sorted(viable, key=lambda item: (item.path_mismatch, -item.start))
    for screened in ranked[:_MAX_ALIGNED_CANDIDATES]:
        fit = _aligned_fit(screened, reference)
        if fit is not None:
            passed.append((fit, normalized.frames[screened.start].timestamp_ms,
                           screened.source))
    completed = _best_observable(template, passed)
    if completed is not None:
        return MOVEMENT_COMPLETED, completed[1]
    return best


def _best_observable(
    template: MovementTemplate,
    passed: Sequence[tuple[float, int | None, Sequence[FrameSample]]],
) -> tuple[float, int | None, Sequence[FrameSample]] | None:
    """Best-fitting gate-passing candidate whose source is observable."""
    for candidate in sorted(passed, key=lambda item: item[0]):
        if _observable(template, candidate[2]):
            return candidate
    return None


def _evaluate_rotation_candidate(
    template: MovementTemplate, bounded: Sequence[FrameSample]
) -> tuple[str, float]:
    """Rotation-only status and fit (turn error; ``inf`` unless completed)."""
    if template.rotation_trace is None:
        return WAITING_FOR_MOVEMENT, math.inf
    trace = _rotation_trace(bounded)
    if abs(trace.total_signed_rad) < MIN_ROTATION_AMOUNT_RAD:
        return WAITING_FOR_MOVEMENT, math.inf
    if (_rotation_track_stable(bounded)
            and trace.coverage >= MIN_ROTATION_COVERAGE
            and trace.pair_coverage >= MIN_ROTATION_PAIR_COVERAGE
            and abs(trace.total_signed_rad - template.rotation_trace.total_signed_rad)
            <= MAX_REFERENCE_ROTATION_SPREAD_RAD):
        return MOVEMENT_COMPLETED, abs(
            trace.total_signed_rad - template.rotation_trace.total_signed_rad)
    return MOVEMENT_DETECTED, math.inf


@dataclass(frozen=True)
class _ReferenceContext:
    """Reference-side values shared by every candidate of one evaluation.

    Built once per ``evaluate_completion_segment`` call from the immutable
    canonical sequence, keyed by moving modality, instead of once per
    candidate.
    """

    sequence: _PreparedSequence
    range: Mapping[str, float]
    path: Mapping[str, float]
    motion: Mapping[str, float]
    sustained_motion: Mapping[str, float]
    centred: Mapping[str, tuple[FrameSample, ...]]


def _reference_context(
    template: MovementTemplate,
    reference: _PreparedSequence,
    thresholds: Mapping[str, float],
) -> _ReferenceContext:
    return _ReferenceContext(
        sequence=reference,
        range={m: _sequence_range(reference, m) for m in thresholds},
        path={m: _sequence_path_length(reference, m) for m in thresholds},
        motion={m: _motion(template, reference, m) for m in thresholds},
        sustained_motion={m: _sequence_motion(reference, m) for m in thresholds},
        centred={m: _centred(reference, m) for m in thresholds},
    )


@dataclass(frozen=True)
class _ScreenedCandidate:
    """A candidate that passed every completion gate except shape alignment."""

    start: int
    candidate: _PreparedSequence
    source: tuple[FrameSample, ...]
    # Moving modalities whose cheap gates passed; only these are aligned.
    gated: tuple[str, ...]
    # Mean |log(path ratio)| over ``gated``: 0 when each travelled path is
    # exactly as long as the learned one. Orders candidates for alignment.
    path_mismatch: float
    quorum: int
    tolerance: float


def _screen_dynamic_candidate(
    template: MovementTemplate,
    samples: Sequence[FrameSample],
    normalized: _PreparedSequence,
    reference: _ReferenceContext,
    movement_start: int,
    thresholds: Mapping[str, float],
    certified_gaps: frozenset[tuple[int, int]] = frozenset(),
) -> str | _ScreenedCandidate:
    """Cheap motion gates for one candidate beginning at ``movement_start``.

    Returns the non-completed status when a gate rejects the candidate, else
    the state ``_aligned_fit`` needs. Every gate that does not depend on the
    DTW alignment runs here, so a candidate that could never complete (too
    little motion, too short, wrong direction, unsustained, short of quorum,
    prop not following) is rejected without paying for DTW.
    """
    moving_modalities = list(thresholds)
    # Tolerances below were tuned in shoulder widths; widen (never tighten)
    # them for hand-anchored templates whose units are much smaller.
    tolerance_scale = max(1.0, _motion_unit(template) or 1.0)
    widening = _spread_widening(template)
    tolerance_scale *= 1.0 + widening
    min_progress = _MIN_DISPLACEMENT_PROGRESS - (
        (_MIN_DISPLACEMENT_PROGRESS - _MIN_WIDENED_DISPLACEMENT_PROGRESS)
        * widening / _MAX_SPREAD_WIDENING
    )

    candidate = normalized.tail(movement_start)
    if not candidate.frames:
        return WAITING_FOR_MOVEMENT
    candidate_start_ms = candidate.frames[0].timestamp_ms
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
        >= max(thresholds[modality], reference.motion[modality] * 0.20)
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
    # required modality still has to satisfy live observability later.
    evidence: list[DynamicMotionEvidence] = []
    learned = reference.sequence
    for modality in moving_modalities:
        expected_range = reference.range[modality]
        expected_path = reference.path[modality]
        observed_path = _sequence_path_length(
            candidate, modality, bridge_gap_ms=450,
            certified_gaps=certified_gaps if modality == "prop_translation" else frozenset())
        start_error = next(
            (error for j in range(min(3, len(candidate)))
             if (error := learned.error(0, candidate, j, modality)) is not None),
            None,
        )
        progress, end_error, reference_travel = _displacement_match(
            learned, candidate, modality,
        )
        ratio = observed_path / expected_path if expected_path > 0 else 0.0
        last = len(learned) - 1
        recent = next(
            (j for j in reversed(range(len(candidate)))
             if learned.error(last, candidate, j, modality) is not None),
            None,
        )
        phase_errors = [
            (error, -index) for index in range(len(learned))
            if recent is not None
            and (error := learned.error(index, candidate, recent, modality)) is not None
        ]
        phase_progress = (
            -min(phase_errors)[1] / max(1, len(learned) - 1)
            if phase_errors else 0.0
        )
        # Detector jitter accumulates path length but not sustained
        # displacement; a stationary attempt cannot satisfy this.
        sustained = candidate_motion(modality) >= max(
            0.6 * thresholds[modality],
            _MIN_SUSTAINED_MOTION_RATIO * reference.sustained_motion[modality],
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
            aligned_error=None,
            phase_progress=phase_progress,
            progress=progress,
            directional=directional,
            reference_travel=reference_travel,
            sustained=sustained,
            # Provisional: every gate except the aligned shape error.
            complete=(ratio >= _MIN_PATH_RATIO
                      and sustained
                      and _same_movement(directional, progress, phase_progress, min_progress)),
        ))
    # Alignment can only fail a modality, never pass one these gates rejected,
    # so a candidate short of the quorum here can never complete.
    quorum = len(moving_modalities) // 2 + 1 if len(moving_modalities) > 2 else 1
    if sum(item.complete for item in evidence) < quorum:
        return MOVEMENT_DETECTED
    # Prop presence is enforced by live validation. A learned prop path must
    # show real travel (not a set-down prop) that roughly follows the learned
    # action; its exact shape and endpoints are scored by compare_sequence
    # rather than vetoing completion.
    if any(item.modality == "prop_translation" and not _prop_follows(item)
           for item in evidence):
        return MOVEMENT_DETECTED
    gated = [item for item in evidence if item.complete]
    return _ScreenedCandidate(
        start=movement_start,
        candidate=candidate,
        source=tuple(frame for frame in samples if frame.timestamp_ms >= candidate_start_ms),
        gated=tuple(item.modality for item in gated),
        path_mismatch=sum(abs(math.log(item.path_ratio)) for item in gated) / len(gated),
        quorum=quorum,
        tolerance=_MAX_ALIGNED_MOTION_ERROR * tolerance_scale,
    )


def _aligned_fit(screened: _ScreenedCandidate, reference: _ReferenceContext) -> float | None:
    """Mean aligned shape error of a screened candidate, ``None`` if it fails.

    The fit is the distance from the learned movement (lower is better). A
    fit is provisional: the caller must still confirm live observability with
    ``_observable`` on the candidate's source.
    """
    aligned: list[float] = []
    for modality in screened.gated:
        centred_reference = reference.centred[modality]
        # Centre on the full candidate, then stride; path indexes below
        # refer to this exact bounded sequence.
        centred_candidate = _centred(
            screened.candidate, modality, _LIVE_ALIGNMENT_MAX_SAMPLES)
        alignment = _dtw(centred_reference, centred_candidate, (modality,))
        errors = [
            error for i, j in alignment
            if (error := _modality_error(
                centred_reference[i], centred_candidate[j], modality)) is not None
        ]
        if errors and sum(errors) / len(errors) <= screened.tolerance:
            aligned.append(sum(errors) / len(errors))
    if len(aligned) < screened.quorum:
        return None
    return sum(aligned) / len(aligned)


def _observable(template: MovementTemplate, source: Sequence[FrameSample]) -> bool:
    """Every required modality is observable enough in the raw source frames."""
    return validate_assessment_sequence(
        source,
        template.required_modalities,
        required_hand_sides=template.required_hand_sides,
        template=template,
    ).valid


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
