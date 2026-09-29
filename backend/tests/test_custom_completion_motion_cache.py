"""Live custom completion motion measures stay bit-exact but are shared.

The per-tick completion evaluation screens many candidate tails of one
window; each tail's sustained motion must equal a from-scratch computation
while tracks are built once per evaluation (the source of practice lag).
"""

import math
import random

from assessment.custom_movement import FrameSample, Landmark
from assessment.custom_movement import completion
from assessment.custom_movement import template_engine
from assessment.custom_movement.completion import (
    _prepare,
    estimate_sequence_progress,
    _bounded_samples,
)
from assessment.custom_movement.template_engine import (
    MEANINGFUL_POSE_KEYS,
    _median,
    landmark_tracks_motion,
    normalize_sequence,
)


def _legacy_smoothed_range(points):
    if len(points) < 3:
        return 0.0
    filtered = [
        Landmark(_median([p.x for p in points[i - 1:i + 2]]),
                 _median([p.y for p in points[i - 1:i + 2]]))
        for i in range(1, len(points) - 1)
    ]
    origin = filtered[0]
    return max(math.hypot(p.x - origin.x, p.y - origin.y) for p in filtered)


def test_smoothed_range_matches_sorted_median_exactly():
    rng = random.Random(7)
    for _ in range(2000):
        points = [Landmark(rng.random(), rng.random())
                  for _ in range(rng.randint(0, 30))]
        assert template_engine._smoothed_range(points) == _legacy_smoothed_range(points)
    # Ties and duplicates.
    same = [Landmark(0.5, 0.5)] * 5 + [Landmark(0.5, 0.9)]
    assert template_engine._smoothed_range(same) == _legacy_smoothed_range(same)


def _live_sequence(seed, count=90):
    rng = random.Random(seed)
    frames = []
    for i in range(count):
        pose = {}
        if rng.random() > 0.1:
            pose = {str(k): Landmark(rng.random(), rng.random(), rng.choice((0.2, 0.9)))
                    for k in range(33)}
        hands = {}
        for side in ("left", "right"):
            if rng.random() > 0.2:
                for k in range(21):
                    hands[f"{side}:0:{k}"] = Landmark(rng.random(), rng.random(), 1.0)
        prop = Landmark(rng.random(), rng.random(), 0.8) if rng.random() > 0.3 else None
        frames.append(FrameSample(i * 33, pose, hands, prop))
    return tuple(frames)


def _from_scratch(frames, modality):
    tracks = {}
    for frame in frames:
        value = template_engine._prepare_dtw_modality(frame, modality)
        if value is None:
            continue
        for key, point in value[1].items():
            if point is not None and (modality != "pose" or key in MEANINGFUL_POSE_KEYS):
                tracks.setdefault(key, []).append(point)
    return landmark_tracks_motion(tracks)


def test_tail_and_span_motion_equal_from_scratch_tracks():
    for seed in range(6):
        frames = normalize_sequence(_live_sequence(seed), use_pose_anchor=seed % 2 == 0)
        prepared = _prepare(frames, ("hands", "pose", "prop_translation"))
        for modality in ("hands", "pose", "prop_translation"):
            for start in range(len(frames)):
                tail = prepared.tail(start)
                expected = (template_engine.sequence_motion(tail.frames, modality)
                            if modality == "prop_translation"
                            else _from_scratch(tail.frames, modality))
                assert completion._sequence_motion(tail, modality) == expected
            for start, stop in ((0, 10), (5, 40), (20, 21), (30, 90)):
                span = prepared.span(start, stop)
                inner = span.tail(2) if len(span) > 2 else span
                for view in (span, inner):
                    expected = (template_engine.sequence_motion(view.frames, modality)
                                if modality == "prop_translation"
                                else _from_scratch(view.frames, modality))
                    assert completion._sequence_motion(view, modality) == expected


def test_tracks_are_built_once_per_prepared_sequence(monkeypatch):
    frames = normalize_sequence(_live_sequence(3))
    prepared = _prepare(frames, ("hands",))
    calls = []
    original = completion._build_motion_tracks
    monkeypatch.setattr(completion, "_build_motion_tracks",
                        lambda *args: calls.append(1) or original(*args))
    for start in range(0, 60, 5):
        completion._sequence_motion(prepared.tail(start), "hands")
    assert len(calls) == 1


def test_progress_estimate_normalises_only_last_frames_identically():
    from test_custom_movement_template_engine import _template, _sequence

    template = _template()
    samples = _sequence(count=40)
    bounded = _bounded_samples(samples)
    full = normalize_sequence(bounded, use_pose_anchor="pose" in template.required_modalities,
                              required_hand_sides=template.required_hand_sides)[-3:]
    tail = normalize_sequence(bounded[-3:], use_pose_anchor="pose" in template.required_modalities,
                              required_hand_sides=template.required_hand_sides)
    assert full == tail
    assert 0.0 <= estimate_sequence_progress(template, samples) <= 1.0


# --- Cross-tick preparation cache ---------------------------------------------

def _live_ticks(kwargs):
    from dataclasses import replace
    from test_custom_movement_tolerance import _dynamic

    idle = _dynamic(noise=0.01)
    motion = _dynamic(**kwargs)
    reverse = {key: -value for key, value in kwargs.items()}
    frames = idle + _dynamic(**reverse) + motion + idle
    return [replace(frame, timestamp_ms=index * 100) for index, frame in enumerate(frames)]


def test_cached_live_evaluation_matches_uncached_on_every_tick():
    from test_custom_movement_tolerance import _dynamic

    from assessment.custom_movement.completion import (
        LiveCompletionCache, MOVEMENT_COMPLETED, evaluate_completion_segment,
        live_completion_window,
    )
    from assessment.custom_movement import build_template

    outcomes = set()
    for kwargs in ({"tip_step": 0.004}, {"wrist_step": 0.003, "prop_step": 0.002},
                   {"prop_step": 0.006}):
        template = build_template([_dynamic(**kwargs), _dynamic(count=10, interval=120, **kwargs)])
        live = _live_ticks(kwargs)
        cache = LiveCompletionCache()
        for end in range(2, len(live) + 1):
            window = tuple(live_completion_window(template, live[:end]))
            expected = evaluate_completion_segment(template, window)
            assert evaluate_completion_segment(template, window, cache=cache) == expected
            outcomes.add(expected[0])
    # The sweep exercised waiting, in-progress and completed decisions.
    assert MOVEMENT_COMPLETED in outcomes and len(outcomes) == 3


def test_cache_normalises_each_live_sample_once(monkeypatch):
    from test_custom_movement_tolerance import _dynamic

    from assessment.custom_movement import build_template
    from assessment.custom_movement.completion import (
        LiveCompletionCache, evaluate_completion_segment,
    )

    kwargs = {"prop_step": 0.006}
    template = build_template([_dynamic(**kwargs), _dynamic(count=10, interval=120, **kwargs)])
    live = _live_ticks(kwargs)
    normalised = []
    original = completion.normalize_sequence
    monkeypatch.setattr(completion, "normalize_sequence",
                        lambda frames, **kw: normalised.append(len(frames)) or original(frames, **kw))
    cache = LiveCompletionCache()
    for end in range(2, len(live) + 1):
        evaluate_completion_segment(template, tuple(live[:end]), cache=cache)
    # Every live sample is normalised exactly once across all ticks.
    assert sum(normalised) == len(live)


def test_vectorised_track_range_equals_scalar_hypot_scan():
    import numpy as np

    rng = random.Random(11)
    for _ in range(3000):
        n = rng.randint(1, 40)
        quantum = rng.choice((None, 0.01, 0.25))  # ties and exact repeats
        values = [rng.random() if quantum is None else round(rng.random() / quantum) * quantum
                  for _ in range(2 * n)]
        fx, fy = np.asarray(values[:n]), np.asarray(values[n:])
        start = rng.randint(0, n - 1)
        stop = rng.randint(start + 1, n)
        expected = max(math.hypot(float(fx[i]) - float(fx[start]), float(fy[i]) - float(fy[start]))
                       for i in range(start, stop))
        assert completion._track_range(fx, fy, start, stop) == expected


def test_incremental_tracks_match_fresh_tracks_on_sliding_windows():
    from test_custom_movement_template_engine import _template

    template = _template()
    live = list(_live_sequence(5, count=120))
    cache = completion.LiveCompletionCache()
    modalities = ("hands", "pose", "prop_translation")
    for end in range(3, len(live) + 1, 3):
        window = tuple(live[max(0, end - 45):end])  # front drops as it slides
        cached = cache.prepare(template, window, modalities)
        fresh = _prepare(normalize_sequence(
            window, use_pose_anchor="pose" in template.required_modalities,
            required_hand_sides=template.required_hand_sides), modalities)
        assert cached.frames == fresh.frames
        for modality in ("hands", "pose"):
            for start in range(0, len(window), 4):
                assert (completion._sequence_motion(cached.tail(start), modality)
                        == completion._sequence_motion(fresh.tail(start), modality))
