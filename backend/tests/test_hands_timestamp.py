"""Timestamp clocks for MediaPipe VIDEO. Production default remains +33 ms."""

from __future__ import annotations

from types import SimpleNamespace

import numpy as np

from vision.hands_timestamp import (
    CaptureMonotonicTimestampClock,
    Synthetic33TimestampClock,
    VideoTimestampClock,
    relative_captured_at,
)


def test_first_frame_at_origin_is_zero():
    clock = VideoTimestampClock()
    assert clock.next_ms(1000.0) == 0
    assert clock.last_timestamp_ms == 0
    assert clock.origin_monotonic == 1000.0


def test_actual_frame_dt_is_preserved_in_milliseconds():
    clock = VideoTimestampClock()
    assert clock.next_ms(10.000) == 0
    assert clock.next_ms(10.090) == 90
    assert clock.next_ms(10.180) == 180


def test_rounding_collision_still_increases():
    clock = VideoTimestampClock()
    first = clock.next_ms(1.0)
    # 0.4 ms rounds to 0, then collides with the origin timestamp.
    second = clock.next_ms(1.0004)
    assert first == 0
    assert second == 1


def test_sub_millisecond_frames_do_not_collide():
    clock = VideoTimestampClock()
    first = clock.next_ms(5.0)
    second = clock.next_ms(5.0004)
    third = clock.next_ms(5.0004)
    assert first == 0
    assert second == 1
    assert third == 2
    assert second > first
    assert third > second


def test_duplicate_capture_timestamp_still_increases():
    clock = VideoTimestampClock()
    first = clock.next_ms(3.5)
    second = clock.next_ms(3.5)
    assert second == first + 1


def test_backward_monotonic_jump_still_increases():
    clock = VideoTimestampClock()
    first = clock.next_ms(20.0)
    second = clock.next_ms(19.5)
    assert second == first + 1


def test_reset_matches_detector_recreation():
    clock = VideoTimestampClock()
    clock.next_ms(1.0)
    clock.next_ms(1.2)
    clock.reset()
    assert clock.origin_monotonic is None
    assert clock.last_timestamp_ms is None
    assert clock.next_ms(50.0) == 0


def test_capture_clock_normal_increasing_timestamps():
    clock = CaptureMonotonicTimestampClock()
    assert clock.next_ms(1.000) == 1000
    assert clock.next_ms(1.050) == 1050
    assert clock.next_ms(1.083) == 1083


def test_capture_clock_equal_rounded_ms_uses_last_plus_one():
    clock = CaptureMonotonicTimestampClock()
    first = clock.next_ms(1.0)
    second = clock.next_ms(1.0004)
    assert first == 1000
    assert second == 1001


def test_capture_clock_slightly_backwards_uses_last_plus_one():
    clock = CaptureMonotonicTimestampClock()
    first = clock.next_ms(2.0)
    second = clock.next_ms(1.999)
    assert first == 2000
    assert second == 2001


def test_capture_clock_preserves_large_forward_gap():
    clock = CaptureMonotonicTimestampClock()
    first = clock.next_ms(1.0)
    second = clock.next_ms(1.5)
    assert first == 1000
    assert second == 1500


def test_capture_clock_reset_starts_fresh():
    clock = CaptureMonotonicTimestampClock()
    clock.next_ms(9.0)
    clock.reset()
    assert clock.last_timestamp_ms is None
    assert clock.next_ms(0.25) == 250


def test_relative_monotonic_replay_works():
    origin = 100.0
    samples = [100.0, 100.090, 100.180]
    clock = CaptureMonotonicTimestampClock()
    stamps = [
        clock.next_ms(relative_captured_at(sample, origin)) for sample in samples
    ]
    assert stamps == [0, 90, 180]


def test_synthetic_clock_increments_exactly_plus_33():
    clock = Synthetic33TimestampClock()
    assert clock.next_ms() == 33
    assert clock.next_ms(12.345) == 66
    assert clock.next_ms(None) == 99
    clock.reset()
    assert clock.last_timestamp_ms == 0
    assert clock.next_ms() == 33


def _fake_landmarker(timestamps: list[int]):
    class FakeLandmarker:
        def detect_for_video(self, image, timestamp_ms):
            timestamps.append(int(timestamp_ms))
            return SimpleNamespace(hand_landmarks=None, handedness=[])

        def close(self):
            pass

    return FakeLandmarker()


def _patch_detector_without_mediapipe(monkeypatch, timestamps: list[int]):
    from vision import hands_detector as hands_detector_module
    from vision.hands_detector import HandsDetector

    monkeypatch.setattr(
        hands_detector_module,
        "ensure_hand_model",
        lambda: "unused-model",
    )
    monkeypatch.setattr(
        HandsDetector,
        "_create_landmarker",
        lambda self, running_mode: _fake_landmarker(timestamps),
    )
    monkeypatch.setattr(
        HandsDetector,
        "_to_mp_image",
        staticmethod(lambda frame: frame),
    )
    return HandsDetector


def test_hands_detector_default_uses_synthetic_plus_33(monkeypatch):
    timestamps: list[int] = []
    HandsDetector = _patch_detector_without_mediapipe(monkeypatch, timestamps)
    detector = HandsDetector(max_num_hands=1)
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    detector.detect(frame, captured_at_monotonic=5.0)
    detector.detect(frame, captured_at_monotonic=5.1)
    assert timestamps == [33, 66]
    detector.close()


def test_injected_capture_clock_receives_frame_timestamp(monkeypatch):
    timestamps: list[int] = []
    HandsDetector = _patch_detector_without_mediapipe(monkeypatch, timestamps)
    clock = CaptureMonotonicTimestampClock()
    detector = HandsDetector(max_num_hands=1, timestamp_clock=clock)
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    detector.detect(frame, captured_at_monotonic=1.234)
    detector.detect(frame, captured_at_monotonic=1.300)
    assert timestamps == [1234, 1300]
    assert clock.last_timestamp_ms == 1300
    detector.close()


def test_readiness_to_active_detector_reuse_does_not_reset_clock(monkeypatch):
    from api import websocket as websocket_api
    from test_session_lifecycle import (
        StubHandsDetector,
        _activate_after_readiness,
        _patch_vision,
    )
    from vision.hands_timestamp import Synthetic33TimestampClock

    _patch_vision(monkeypatch)

    class TrackingHands(StubHandsDetector):
        def __init__(self, **kwargs):
            super().__init__(**kwargs)
            self.timestamp_clock = kwargs.get("timestamp_clock")
            if self.timestamp_clock is None:
                self.timestamp_clock = Synthetic33TimestampClock()
            self.close_calls = 0

        def detect(self, current_frame, bottle=None, captured_at_monotonic=None):
            self.timestamp_clock.next_ms(captured_at_monotonic)
            return super().detect(current_frame, bottle)

        def close(self):
            self.close_calls += 1
            self.timestamp_clock.reset()

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)

    session = websocket_api.VisionSession("Normal Grip")
    session.start()
    session.begin_readiness()
    detector = session.hands_detector
    assert detector is not None
    clock = detector.timestamp_clock
    session.process_readiness_frame()
    stamp_after_readiness = clock.last_timestamp_ms
    assert stamp_after_readiness == 33
    _activate_after_readiness(session)
    assert session.hands_detector is detector
    assert session.hands_detector.timestamp_clock is clock
    assert detector.close_calls == 0
    assert clock.last_timestamp_ms == stamp_after_readiness
    session.close()


def test_detector_recreation_resets_clock_state(monkeypatch):
    timestamps: list[int] = []
    HandsDetector = _patch_detector_without_mediapipe(monkeypatch, timestamps)
    clock = Synthetic33TimestampClock()
    frame = np.zeros((8, 8, 3), dtype=np.uint8)
    first = HandsDetector(max_num_hands=1, timestamp_clock=clock)
    first.detect(frame)
    first.detect(frame)
    assert clock.last_timestamp_ms == 66
    first.close()
    assert clock.last_timestamp_ms == 0
    timestamps.clear()
    second = HandsDetector(max_num_hands=1, timestamp_clock=clock)
    second.detect(frame)
    assert timestamps == [33]
    second.close()
