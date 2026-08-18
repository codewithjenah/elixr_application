"""Diagnostic Hands counters and benchmark helpers. No MediaPipe required."""

from __future__ import annotations

import numpy as np

from vision.hands_benchmark import (
    agreement_rates,
    classify_scene,
    cycle_frames,
    result_signature,
    synthetic_scene_frames,
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
