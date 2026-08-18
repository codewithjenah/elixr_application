"""Diagnostic Hands counters and benchmark helpers. No MediaPipe required."""

from __future__ import annotations

import numpy as np

from vision.hands_benchmark import (
    agreement_rates,
    apply_scene_tags,
    classify_scene,
    continuity_metrics,
    cycle_frames,
    fallback_ab_replay,
    landmark_jitter_metrics,
    load_capture_manifest,
    parse_scene_tag_spec,
    production_hands_defaults,
    relative_time_ms,
    result_signature,
    save_capture_manifest,
    synthetic_scene_frames,
    TimedCaptureFrame,
)
from vision.hands_detector import HandsDetector
from vision.hands_diagnostics import HandsCallStats, timing_stats
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D


def _hand(cx: float = 0.5, cy: float = 0.5) -> HandLandmarks:
    return HandLandmarks(
        points={0: Point2D(cx, cy + 0.04), 9: Point2D(cx, cy)},
        handedness="Right",
    )


def test_timing_stats_mean_median_p95_and_fps():
    samples = [0.050, 0.060, 0.070, 0.080, 0.200]
    stats = timing_stats(samples)
    assert abs(stats["mean_ms"] - 92.0) < 0.01
    assert abs(stats["median_ms"] - 70.0) < 0.01
    assert stats["p95_ms"] == 200.0
    assert abs(stats["fps"] - (1.0 / 0.092)) < 0.01


def test_empty_timing_stats_are_zero():
    stats = timing_stats([])
    assert stats == {
        "count": 0.0,
        "mean_ms": 0.0,
        "median_ms": 0.0,
        "p95_ms": 0.0,
        "fps": 0.0,
    }


def test_fallback_activation_rate_and_reset():
    stats = HandsCallStats()
    stats.detect_calls = 10
    stats.record_primary(0.060)
    stats.record_rotated(0.085)
    stats.mark_fallback_activated()
    stats.record_bartender_roi(0.090, ran_image=True)
    stats.mark_fallback_activated()
    snap = stats.snapshot()
    assert snap["detect_calls"] == 10
    assert snap["rotated_calls"] == 1
    assert snap["bartender_image_calls"] == 1
    assert abs(snap["fallback_activation_rate"] - 0.2) < 1e-9
    assert "hands_primary=" in stats.format_line()
    assert "hands_fallback=20.0%" in stats.format_line()
    stats.reset()
    assert stats.detect_calls == 0
    assert stats.snapshot()["rotated_calls"] == 0


def test_detect_records_primary_and_rotated_without_changing_results():
    class Stub(HandsDetector):
        def __init__(self):
            self._rotated_fallback = True
            self._bartender_roi_fallback = False
            self._max_num_hands = 2
            self._primary_hits = 0

        def _detect_primary(self, frame):
            self._primary_hits += 1
            if self._primary_hits == 1:
                return HandsResult(hands=[_hand()])
            return None

        def _detect_rotated(self, frame):
            return HandsResult(hands=[_hand(0.2, 0.3)])

    detector = Stub()
    hit = detector.detect(np.zeros((8, 8, 3), dtype=np.uint8))
    miss = detector.detect(np.zeros((8, 8, 3), dtype=np.uint8))
    assert hit is not None and len(hit.hands) == 1
    assert miss is not None and miss.hands[0].points[0].x == 0.2
    snap = detector.stats.snapshot()
    assert snap["detect_calls"] == 2
    assert snap["primary_calls"] == 2
    assert snap["rotated_calls"] == 1
    assert abs(snap["fallback_activation_rate"] - 0.5) < 1e-9


def test_bartender_roi_attempt_is_counted_when_candidate_missing():
    class Stub(HandsDetector):
        def __init__(self):
            self._rotated_fallback = False
            self._bartender_roi_fallback = True
            self._max_num_hands = 2

        def _detect_primary(self, frame):
            return HandsResult(hands=[_hand(0.9, 0.9)])

        def _detect_bartender_roi(self, frame, bottle):
            return HandsResult(hands=[_hand(0.5, 0.2)])

    detector = Stub()
    bottle = BottleDetection(x1=200, y1=100, x2=280, y2=300, confidence=0.9)
    result = detector.detect(np.zeros((480, 640, 3), dtype=np.uint8), bottle)
    assert result is not None
    snap = detector.stats.snapshot()
    assert snap["bartender_calls"] == 1
    assert snap["fallback_activated_calls"] == 1


def test_result_signature_and_agreement():
    none = result_signature(None)
    one = result_signature(HandsResult(hands=[_hand()]))
    two = result_signature(HandsResult(hands=[_hand(), _hand(0.2, 0.2)]))
    assert none == (0, 0)
    assert one[0] == 1 and one[1] == 2
    assert two[0] == 2
    rates = agreement_rates([one, two], [one, one])
    assert rates["frames"] == 2
    assert abs(rates["detection_count_agree"] - 0.5) < 1e-9
    assert rates["landmark_availability_agree"] == 1.0


def test_hands_detector_default_constructor_keeps_two_hands():
    import inspect

    signature = inspect.signature(HandsDetector.__init__)
    assert signature.parameters["max_num_hands"].default == 2


def test_rotated_fallback_landmarker_inherits_configured_max_num_hands():
    recorded: list[tuple[object, int]] = []

    class Stub(HandsDetector):
        def __init__(self, max_num_hands: int):
            self._model_path = "unused"
            self._max_num_hands = max_num_hands
            self._fallback_landmarker = None

        def _create_landmarker(self, running_mode):
            recorded.append((running_mode, self._max_num_hands))
            return object()

    detector = Stub(max_num_hands=1)
    detector._image_landmarker()
    from mediapipe.tasks.python import vision

    assert recorded == [(vision.RunningMode.IMAGE, 1)]
    assert detector.max_num_hands == 1


def test_bartender_roi_fallback_landmarker_inherits_configured_max_num_hands():
    recorded: list[tuple[object, int]] = []

    class Stub(HandsDetector):
        def __init__(self, max_num_hands: int):
            self._model_path = "unused"
            self._max_num_hands = max_num_hands
            self._fallback_landmarker = None

        def _create_landmarker(self, running_mode):
            recorded.append((running_mode, self._max_num_hands))
            return object()

    detector = Stub(max_num_hands=1)
    first = detector._image_landmarker()
    second = detector._image_landmarker()
    from mediapipe.tasks.python import vision

    assert first is second
    assert recorded == [(vision.RunningMode.IMAGE, 1)]
    assert detector.max_num_hands == 1


def test_primary_and_fallback_landmarkers_share_configured_max_num_hands():
    recorded: list[tuple[object, int]] = []

    class Stub(HandsDetector):
        def __init__(self, max_num_hands: int):
            self._model_path = "unused"
            self._max_num_hands = max_num_hands
            self._fallback_landmarker = None

        def _create_landmarker(self, running_mode):
            recorded.append((running_mode, self._max_num_hands))
            return object()

    detector = Stub(max_num_hands=2)
    from mediapipe.tasks.python import vision

    detector._create_landmarker(vision.RunningMode.VIDEO)
    detector._image_landmarker()
    assert recorded == [
        (vision.RunningMode.VIDEO, 2),
        (vision.RunningMode.IMAGE, 2),
    ]


def test_classify_scene_occlusion_uses_palm_inside_bottle():
    bottle = BottleDetection(x1=300, y1=200, x2=400, y2=320, confidence=0.9)
    inside = HandsResult(hands=[_hand(0.55, 0.50)])
    outside = HandsResult(hands=[_hand(0.10, 0.10)])
    two = HandsResult(hands=[_hand(0.2, 0.2), _hand(0.8, 0.8)])
    assert classify_scene(None) == "no_hand"
    assert classify_scene(inside, bottle) == "hand_occluded_by_bottle"
    assert classify_scene(outside, bottle) == "one_hand_and_bottle"
    assert classify_scene(two, bottle) == "two_hands"


def test_cycle_frames_and_synthetic_scenes_are_deterministic():
    scenes = synthetic_scene_frames()
    assert set(scenes) >= {
        "no_hand",
        "one_hand_and_bottle",
        "two_hands",
        "hand_occluded_by_bottle",
    }
    replay = cycle_frames([scenes["no_hand"], scenes["two_hands"]], 5)
    assert len(replay) == 5
    assert replay[0] is scenes["no_hand"]
    assert replay[1] is scenes["two_hands"]
    assert replay[4] is scenes["no_hand"]
    second = synthetic_scene_frames()
    assert np.array_equal(scenes["no_hand"], second["no_hand"])


def test_hands_detector_timestamp_clock_defaults_to_none():
    import inspect

    signature = inspect.signature(HandsDetector.__init__)
    assert signature.parameters["timestamp_clock"].default is None


def test_primary_success_counters_and_last_primary_hit():
    stats = HandsCallStats()
    stats.detect_calls = 3
    stats.record_primary_outcome(True)
    stats.record_primary_outcome(False)
    stats.record_primary_outcome(True)
    snap = stats.snapshot()
    assert snap["primary_success_calls"] == 2
    assert snap["primary_empty_calls"] == 1
    assert abs(snap["primary_success_rate"] - (2 / 3)) < 1e-9
    assert stats.last_primary_hit is True
    stats.reset()
    assert stats.primary_success_calls == 0
    assert stats.last_primary_hit is False


def test_detect_records_primary_success_without_changing_results():
    class Stub(HandsDetector):
        def __init__(self):
            self._rotated_fallback = False
            self._bartender_roi_fallback = False
            self._max_num_hands = 1

        def _detect_primary(self, frame):
            if int(frame[0, 0, 0]) == 1:
                return HandsResult(hands=[_hand()])
            return None

    detector = Stub()
    hit = detector.detect(np.ones((8, 8, 3), dtype=np.uint8))
    miss = detector.detect(np.zeros((8, 8, 3), dtype=np.uint8))
    assert hit is not None
    assert miss is None
    snap = detector.stats.snapshot()
    assert snap["primary_success_calls"] == 1
    assert snap["primary_empty_calls"] == 1
    assert detector.stats.last_primary_hit is False


def test_continuity_metrics_count_miss_runs_and_hand_count_changes():
    hits = [True, True, False, False, False, True, False]
    counts = [1, 1, 0, 0, 0, 1, 0]
    available = [True, True, False, False, False, True, False]
    stats = continuity_metrics(
        primary_hits=hits,
        hand_counts=counts,
        landmark_available=available,
    )
    assert stats["primary_miss_transitions"] == 2
    assert stats["longest_primary_miss_run"] == 3
    assert stats["hand_count_changes"] == 3
    assert abs(stats["landmark_availability_continuity"] - (3 / 6)) < 1e-9


def test_continuity_metrics_empty_sequence():
    stats = continuity_metrics(primary_hits=[], hand_counts=[], landmark_available=[])
    assert stats["primary_miss_transitions"] == 0
    assert stats["longest_primary_miss_run"] == 0
    assert stats["hand_count_changes"] == 0
    assert stats["landmark_availability_continuity"] == 0.0


def test_landmark_jitter_ignores_legitimate_disappearance():
    present = HandsResult(hands=[_hand(0.50, 0.50)])
    moved = HandsResult(hands=[_hand(0.51, 0.50)])
    gone = None
    stats = landmark_jitter_metrics([present, moved, gone, present])
    assert stats["pairs"] == 1
    assert stats["mean_displacement"] > 0
    assert stats["p95_displacement"] > 0


def test_scene_tag_annotation_is_human_not_detector_inferred():
    frames = [
        TimedCaptureFrame(
            filename="0001.jpg",
            sequence=10,
            captured_at_monotonic=1.0,
            relative_time_ms=0,
            movement_label="Bartender's Grip",
        ),
        TimedCaptureFrame(
            filename="0002.jpg",
            sequence=11,
            captured_at_monotonic=1.04,
            relative_time_ms=40,
            movement_label="Bartender's Grip",
        ),
    ]
    ranges = parse_scene_tag_spec("valid_hold:1-1,leaving_contact_zone:2-2")
    tagged = apply_scene_tags(frames, ranges)
    assert tagged[0].scene_tag == "valid_hold"
    assert tagged[1].scene_tag == "leaving_contact_zone"
    assert tagged[0].movement_label == "Bartender's Grip"


def test_capture_manifest_roundtrip_preserves_relative_timing(tmp_path):
    frames = [
        TimedCaptureFrame(
            filename="0001.jpg",
            sequence=10,
            captured_at_monotonic=5.0,
            relative_time_ms=0,
        ),
        TimedCaptureFrame(
            filename="0002.jpg",
            sequence=11,
            captured_at_monotonic=5.090,
            relative_time_ms=90,
        ),
    ]
    path = tmp_path / "manifest.json"
    save_capture_manifest(path, frames)
    loaded = load_capture_manifest(path)
    assert [frame.filename for frame in loaded] == ["0001.jpg", "0002.jpg"]
    assert [frame.sequence for frame in loaded] == [10, 11]
    assert [frame.relative_time_ms for frame in loaded] == [0, 90]
    assert relative_time_ms(5.180, 5.0) == 180


def _blank() -> np.ndarray:
    return np.zeros((480, 640, 3), dtype=np.uint8)


def _zone_hand(cx: float, cy: float) -> HandLandmarks:
    return HandLandmarks(
        points={
            0: Point2D(cx, cy + 0.04),
            4: Point2D(cx - 0.01, cy),
            8: Point2D(cx + 0.01, cy),
            9: Point2D(cx, cy),
        },
        handedness="Right",
    )


def _bartender_bottle() -> BottleDetection:
    return BottleDetection(x1=200, y1=100, x2=280, y2=300, confidence=0.9)


def test_primary_success_does_not_count_rotated_attempt():
    class Stub(HandsDetector):
        def __init__(self):
            self._rotated_fallback = True
            self._bartender_roi_fallback = False
            self._max_num_hands = 1

        def _detect_primary(self, frame):
            return HandsResult(hands=[_hand()])

        def _detect_rotated(self, frame):
            raise AssertionError("rotated fallback must not run")

    detector = Stub()
    result = detector.detect(_blank())
    assert result is not None
    snap = detector.stats.snapshot()
    assert snap["fallback_attempts"] == 0
    assert snap["rotated_attempts"] == 0
    assert snap["fallback_successes"] == 0
    assert snap["primary_successes"] == 1
    assert snap["primary_failures"] == 0


def test_primary_miss_and_rotated_success_counts_recovery():
    class Stub(HandsDetector):
        def __init__(self):
            self._rotated_fallback = True
            self._bartender_roi_fallback = False
            self._max_num_hands = 1

        def _detect_primary(self, frame):
            return None

        def _detect_rotated(self, frame):
            return HandsResult(hands=[_hand(0.2, 0.3)])

    detector = Stub()
    result = detector.detect(_blank())
    assert result is not None and result.hands
    snap = detector.stats.snapshot()
    assert snap["primary_failures"] == 1
    assert snap["rotated_attempts"] == 1
    assert snap["rotated_successes"] == 1
    assert snap["rotated_failures"] == 0
    assert snap["fallback_attempts"] == 1
    assert snap["fallback_successes"] == 1
    assert snap["fallback_recovery_rate"] == 1.0
    assert snap["fallback_wasted_rate"] == 0.0


def test_primary_miss_and_rotated_miss_counts_failure():
    class Stub(HandsDetector):
        def __init__(self):
            self._rotated_fallback = True
            self._bartender_roi_fallback = False
            self._max_num_hands = 1

        def _detect_primary(self, frame):
            return None

        def _detect_rotated(self, frame):
            return None

    detector = Stub()
    assert detector.detect(_blank()) is None
    snap = detector.stats.snapshot()
    assert snap["rotated_attempts"] == 1
    assert snap["rotated_successes"] == 0
    assert snap["rotated_failures"] == 1
    assert snap["fallback_failures"] == 1
    assert snap["fallback_wasted_rate"] == 1.0
    assert snap["fallback_recovery_rate"] == 0.0


def test_bartender_roi_landmarks_without_candidate_are_not_recovery():
    class Stub(HandsDetector):
        def __init__(self):
            self._rotated_fallback = False
            self._bartender_roi_fallback = True
            self._max_num_hands = 1

        def _detect_primary(self, frame):
            return HandsResult(hands=[_hand(0.9, 0.9)])

        def _detect_bartender_roi(self, frame, bottle):
            return HandsResult(hands=[_zone_hand(0.9, 0.9)])

    detector = Stub()
    result = detector.detect(_blank(), _bartender_bottle())
    assert result is not None
    snap = detector.stats.snapshot()
    assert snap["bartender_attempts"] == 1
    assert snap["bartender_successes"] == 0
    assert snap["bartender_failures"] == 1
    assert snap["fallback_successes"] == 0
    assert snap["fallback_failures"] == 1
    assert snap["fallback_wasted_rate"] == 1.0


def test_bartender_roi_usable_candidate_counts_recovery():
    class Stub(HandsDetector):
        def __init__(self):
            self._rotated_fallback = False
            self._bartender_roi_fallback = True
            self._max_num_hands = 1

        def _detect_primary(self, frame):
            return HandsResult(hands=[_hand(0.9, 0.9)])

        def _detect_bartender_roi(self, frame, bottle):
            return HandsResult(hands=[_zone_hand(0.375, 0.32)])

    detector = Stub()
    result = detector.detect(_blank(), _bartender_bottle())
    assert result is not None
    snap = detector.stats.snapshot()
    assert snap["bartender_attempts"] == 1
    assert snap["bartender_successes"] == 1
    assert snap["bartender_failures"] == 0
    assert snap["fallback_successes"] == 1
    assert abs(snap["fallback_recovery_rate"] - 1.0) < 1e-9


def test_fallback_ab_helper_reuses_identical_frames_and_bottles():
    frames = [_blank(), np.ones((480, 640, 3), dtype=np.uint8)]
    bottles = [_bartender_bottle(), None]
    captured_at = [0.0, 0.033]
    replay = fallback_ab_replay(
        frames,
        bottles=bottles,
        captured_at=captured_at,
        max_num_hands=1,
        rotated_fallback=True,
        bartender_roi_fallback=False,
    )
    assert replay["frames_a"] is frames
    assert replay["frames_b"] is frames
    assert replay["bottles_a"] is bottles
    assert replay["bottles_b"] is bottles
    assert replay["captured_at_a"] is captured_at
    assert replay["captured_at_b"] is captured_at
    assert replay["kwargs_a"]["rotated_fallback"] is True
    assert replay["kwargs_b"]["rotated_fallback"] is False
    assert replay["kwargs_a"]["bartender_roi_fallback"] is False
    assert replay["kwargs_b"]["bartender_roi_fallback"] is False
    assert replay["kwargs_a"]["max_num_hands"] == 1
    assert replay["kwargs_b"]["max_num_hands"] == 1


def test_fallback_disabled_benchmark_does_not_mutate_production_defaults():
    before = production_hands_defaults()
    fallback_ab_replay(
        [_blank()],
        bottles=[None],
        captured_at=[None],
        max_num_hands=1,
        rotated_fallback=True,
        bartender_roi_fallback=True,
    )
    after = production_hands_defaults()
    assert before == after
    assert after["rotated_fallback"] is False
    assert after["bartender_roi_fallback"] is False
    assert after["max_num_hands"] == 2
    assert after["timestamp_clock"] is None


def test_max_num_hands_and_plus_33_remain_production_defaults():
    defaults = production_hands_defaults()
    assert defaults["max_num_hands"] == 2
    assert defaults["timestamp_clock"] is None
    from vision.hands_timestamp import default_timestamp_clock, Synthetic33TimestampClock

    clock = default_timestamp_clock(None)
    assert isinstance(clock, Synthetic33TimestampClock)
    assert clock.next_ms() == 33


def test_recovery_diagnostics_reset_between_runs():
    stats = HandsCallStats()
    stats.detect_calls = 4
    stats.record_primary_outcome(False)
    stats.record_rotated(0.04)
    stats.record_rotated_outcome(True)
    stats.record_bartender_roi(0.03, ran_image=True)
    stats.record_bartender_outcome(False)
    stats.record_fallback_frame(attempted=True, recovered=True)
    stats.reset()
    snap = stats.snapshot()
    assert snap["detect_calls"] == 0
    assert snap["fallback_attempts"] == 0
    assert snap["fallback_successes"] == 0
    assert snap["fallback_failures"] == 0
    assert snap["rotated_attempts"] == 0
    assert snap["bartender_attempts"] == 0
    assert snap["primary_successes"] == 0
    assert snap["primary_failures"] == 0
