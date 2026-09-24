"""Bounded same-frame YOLO/MediaPipe concurrency tests."""

from __future__ import annotations

import threading
import time

import pytest

from api import websocket as websocket_api
from assessment.rules.base import RuleResult
from test_session_lifecycle import (
    StubHandsDetector,
    StubPoseDetector,
    _patch_vision,
)
from test_custom_movement_session import _template
from vision.types import HandLandmarks, HandsResult, Point2D, PoseLandmarks, PropDetection


_BRANCH_DELAY_S = 0.12


def _positive_rule(*args, **kwargs):
    return (
        RuleResult(
            feedback="ok",
            feedback_type="positive",
            posture_status="stable",
        ),
        None,
        None,
    )


class _CoordinatedPropDetector:
    instances: list["_CoordinatedPropDetector"] = []
    barrier: threading.Barrier | None = None

    def __init__(self, *args, enabled: bool = True, **kwargs):
        self.enabled = enabled
        self.detect_calls = 0
        self.frame_ids: list[int] = []
        self.finished = threading.Event()
        self.detection = PropDetection(10, 10, 30, 50, 0.9, track_id=7)
        self.__class__.instances.append(self)

    def ensure_ready(self):
        pass

    def detect(self, frame):
        self.detect_calls += 1
        self.frame_ids.append(id(frame))
        if self.__class__.barrier is not None:
            self.__class__.barrier.wait(timeout=2.0)
        time.sleep(_BRANCH_DELAY_S)
        self.finished.set()
        return [self.detection]


def _patch_prop(monkeypatch, detector_cls=_CoordinatedPropDetector):
    detector_cls.instances = []
    monkeypatch.setattr(websocket_api, "BottleDetector", detector_cls)
    monkeypatch.setattr(websocket_api, "PropDetector", detector_cls)


def _start_active(session: websocket_api.VisionSession) -> None:
    assert session.start() is True
    assert session.activate() == (True, None)


def test_safe_hand_frame_overlaps_yolo_and_hands_and_joins_before_evaluation(
    monkeypatch,
):
    _patch_vision(monkeypatch)
    _patch_prop(monkeypatch)
    barrier = threading.Barrier(2)
    _CoordinatedPropDetector.barrier = barrier

    class CoordinatedHands(StubHandsDetector):
        instances: list["CoordinatedHands"] = []

        def __init__(self, **kwargs):
            super().__init__(**kwargs)
            self.frame_ids: list[int] = []
            self.finished = threading.Event()
            self.__class__.instances.append(self)

        def detect(self, frame, bottle=None):
            self.detect_calls += 1
            self.frame_ids.append(id(frame))
            assert bottle is None
            barrier.wait(timeout=2.0)
            time.sleep(_BRANCH_DELAY_S)
            self.finished.set()
            return None

    monkeypatch.setattr(websocket_api, "HandsDetector", CoordinatedHands)

    def evaluate_after_join(*args, **kwargs):
        assert _CoordinatedPropDetector.instances[-1].finished.is_set()
        assert CoordinatedHands.instances[-1].finished.is_set()
        return _positive_rule()

    monkeypatch.setattr(websocket_api, "evaluate_movement", evaluate_after_join)
    session = websocket_api.VisionSession("Hand Stall")
    try:
        _start_active(session)
        assert session.analyze_tick() is not None

        prop = _CoordinatedPropDetector.instances[-1]
        hands = CoordinatedHands.instances[-1]
        assert prop.frame_ids == hands.frame_ids
        assert session.timings.average_ms("inference_join") < (
            session.timings.average_ms("yolo")
            + session.timings.average_ms("hands")
        ) * 0.8
        assert session.timings.inference_concurrency_summary() == {
            "parallel_frames": 1,
            "sequential_frames": 0,
        }
        assert session._ai_inflight_max == 1
    finally:
        _CoordinatedPropDetector.barrier = None
        session.close()


def test_pose_frame_overlaps_yolo_and_pose(monkeypatch):
    _patch_vision(monkeypatch)
    _patch_prop(monkeypatch)
    barrier = threading.Barrier(2)
    _CoordinatedPropDetector.barrier = barrier

    class CoordinatedPose(StubPoseDetector):
        instances: list["CoordinatedPose"] = []

        def __init__(self, **kwargs):
            super().__init__(**kwargs)
            self.frame_ids: list[int] = []
            self.__class__.instances.append(self)

        def detect(self, frame):
            self.detect_calls += 1
            self.frame_ids.append(id(frame))
            barrier.wait(timeout=2.0)
            time.sleep(_BRANCH_DELAY_S)
            return None

    monkeypatch.setattr(websocket_api, "PoseDetector", CoordinatedPose)
    monkeypatch.setattr(websocket_api, "evaluate_movement", _positive_rule)
    session = websocket_api.VisionSession("Forearm Stall")
    try:
        _start_active(session)
        assert session.analyze_tick() is not None
        assert _CoordinatedPropDetector.instances[-1].frame_ids == (
            CoordinatedPose.instances[-1].frame_ids
        )
        assert session.timings.inference_concurrency_summary()["parallel_frames"] == 1
        assert session.timings.count("pose") == 1
    finally:
        _CoordinatedPropDetector.barrier = None
        session.close()


def test_skipped_yolo_frame_uses_cached_prop_and_only_runs_hands(monkeypatch):
    _patch_vision(monkeypatch)
    _patch_prop(monkeypatch)
    _CoordinatedPropDetector.barrier = None
    seen_bottles: list[PropDetection | None] = []

    class TrackingHands(StubHandsDetector):
        def detect(self, frame, bottle=None):
            self.detect_calls += 1
            seen_bottles.append(bottle)
            return None

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)
    monkeypatch.setattr(websocket_api, "evaluate_movement", _positive_rule)
    session = websocket_api.VisionSession("Hand Stall")
    try:
        _start_active(session)
        cached = PropDetection(1, 2, 11, 22, 0.8, track_id=4)
        session._last_live_bottles = [cached]
        session._frame_index = 1  # The next analyzed frame is a YOLO-skip frame.

        assert session.analyze_tick() is not None
        assert _CoordinatedPropDetector.instances[-1].detect_calls == 0
        assert seen_bottles == [cached]
        assert session.timings.inference_concurrency_summary() == {
            "parallel_frames": 0,
            "sequential_frames": 1,
        }
    finally:
        session.close()


def test_bartender_grip_keeps_current_yolo_prop_before_hands(monkeypatch):
    _patch_vision(monkeypatch)
    _patch_prop(monkeypatch)
    _CoordinatedPropDetector.barrier = None
    observed: list[PropDetection | None] = []

    class BartenderHands(StubHandsDetector):
        def detect(self, frame, bottle=None):
            prop = _CoordinatedPropDetector.instances[-1]
            assert prop.finished.is_set()
            observed.append(bottle)
            return None

    monkeypatch.setattr(websocket_api, "HandsDetector", BartenderHands)
    monkeypatch.setattr(websocket_api, "evaluate_movement", _positive_rule)
    session = websocket_api.VisionSession("Bartender's Grip")
    try:
        _start_active(session)
        assert session.analyze_tick() is not None
        prop = _CoordinatedPropDetector.instances[-1]
        assert observed == [prop.detection]
        assert session.timings.inference_concurrency_summary() == {
            "parallel_frames": 0,
            "sequential_frames": 1,
        }
    finally:
        session.close()


@pytest.mark.parametrize("movement", ("Normal Grip", "Claw Grip"))
def test_rotated_fallback_movements_remain_parallel_safe(monkeypatch, movement):
    _patch_vision(monkeypatch)
    _patch_prop(monkeypatch)
    _CoordinatedPropDetector.barrier = None
    constructed: list[StubHandsDetector] = []

    class TrackingHands(StubHandsDetector):
        def __init__(self, **kwargs):
            super().__init__(**kwargs)
            constructed.append(self)

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)
    monkeypatch.setattr(websocket_api, "evaluate_movement", _positive_rule)
    session = websocket_api.VisionSession(movement)
    try:
        _start_active(session)
        assert session.analyze_tick() is not None
        assert constructed[-1].rotated_fallback is True
        assert session.timings.inference_concurrency_summary()["parallel_frames"] == 1
    finally:
        session.close()


def test_custom_frame_keeps_prop_hands_pose_and_capture_identity_together(monkeypatch):
    _patch_vision(monkeypatch)
    _patch_prop(monkeypatch)
    _CoordinatedPropDetector.barrier = None
    frame_ids: dict[str, int] = {}

    class CustomHands(StubHandsDetector):
        def detect(self, frame, bottle=None):
            assert _CoordinatedPropDetector.instances[-1].finished.is_set()
            frame_ids["hands"] = id(frame)
            return None

    class CustomPose(StubPoseDetector):
        def detect(self, frame):
            frame_ids["pose"] = id(frame)
            return None

    monkeypatch.setattr(websocket_api, "HandsDetector", CustomHands)
    monkeypatch.setattr(websocket_api, "PoseDetector", CustomPose)
    session = websocket_api.VisionSession(
        "Custom Movement",
        session_mode="custom_capture",
    )
    recorded: dict = {}
    session._record_custom_sample = lambda **kwargs: recorded.update(kwargs)
    try:
        _start_active(session)
        assert session.analyze_tick() is not None
        prop_frame_id = _CoordinatedPropDetector.instances[-1].frame_ids[-1]
        assert frame_ids == {"hands": prop_frame_id, "pose": prop_frame_id}
        assert id(recorded["frame"]) == prop_frame_id
        assert recorded["captured"].frame is recorded["frame"]
        assert recorded["captured"].sequence == session._last_ai_sequence
        assert recorded["captured"].generation == 0
        assert recorded["yolo_attempted"] is True
        assert session.timings.inference_concurrency_summary()["sequential_frames"] == 1
    finally:
        session.close()


@pytest.mark.parametrize("prop_type", ("bottle", "shaker"))
@pytest.mark.parametrize("session_mode", ("custom_capture", "custom_assessment"))
def test_custom_stages_hand_recovery_after_parallel_yolo_and_pose(
    monkeypatch, prop_type, session_mode,
):
    _patch_vision(monkeypatch)
    _patch_prop(monkeypatch)
    barrier = threading.Barrier(2)
    _CoordinatedPropDetector.barrier = barrier
    frame_ids: dict[str, int] = {}
    observed_hands = HandsResult(
        hands=[HandLandmarks(points={0: Point2D(0.2, 0.3)})]
    )
    observed_pose = PoseLandmarks(points={11: Point2D(0.4, 0.3)})

    class StagedHands(StubHandsDetector):
        def detect_independent(self, frame, *, captured_at_monotonic=None):
            self.detect_calls += 1
            frame_ids["hands"] = id(frame)
            barrier.wait(timeout=2.0)
            return "current-hand-stage"

        def finish_with_prop(self, frame, stage, bottle):
            assert _CoordinatedPropDetector.instances[-1].finished.is_set()
            assert stage == "current-hand-stage"
            assert bottle is _CoordinatedPropDetector.instances[-1].detection
            frame_ids["recovery"] = id(frame)
            return observed_hands

    class StagedPose(StubPoseDetector):
        def detect(self, frame):
            self.detect_calls += 1
            frame_ids["pose"] = id(frame)
            return observed_pose

    monkeypatch.setattr(websocket_api, "HandsDetector", StagedHands)
    monkeypatch.setattr(websocket_api, "PoseDetector", StagedPose)
    kwargs = (
        {"custom_movement_template": _template(
            sides=("left", "right"), moving_pose=True,
        ).to_dict()}
        if session_mode == "custom_assessment" else {}
    )
    session = websocket_api.VisionSession(
        "Custom Movement", prop_type=prop_type, session_mode=session_mode,
        **kwargs,
    )
    try:
        session._sync_landmark_detectors(needs_hands=True, needs_pose=True)
        frame = object()
        normalized, hands, pose = session._run_frame_inference(
            frame, captured_at_monotonic=time.monotonic(), run_yolo=True,
            needs_hands=True, needs_pose=True,
        )
        assert frame_ids == {"hands": id(frame), "pose": id(frame), "recovery": id(frame)}
        assert normalized.primary == (_CoordinatedPropDetector.instances[-1].detection,)
        assert hands is observed_hands and pose is observed_pose
        assert session.hands_detector.detect_calls == 1
        assert session.pose_detector.detect_calls == 1
        assert session.timings.count("hands") == 1
        assert session.timings.count("pose") == 1
        assert session.timings.inference_concurrency_summary() == {
            "parallel_frames": 1, "sequential_frames": 0,
        }
    finally:
        _CoordinatedPropDetector.barrier = None
        session.close()


def test_failed_custom_hand_stage_still_records_one_timing_sample(monkeypatch):
    _patch_vision(monkeypatch)

    class FailingHands(StubHandsDetector):
        def detect_independent(self, frame, *, captured_at_monotonic=None):
            raise RuntimeError("hand inference failed")

    session = websocket_api.VisionSession(
        "Custom Movement", session_mode="custom_capture",
    )
    session.hands_detector = FailingHands()
    try:
        with pytest.raises(RuntimeError, match="hand inference failed"):
            session._detect_landmarks(
                object(), captured_at_monotonic=time.monotonic(),
                needs_hands=True, needs_pose=False, hand_reference=None,
                defer_prop_recovery=True,
            )
        assert session.timings.count("hands") == 1
    finally:
        session.close()


def test_generation_replacement_discards_joined_results_before_scoring(monkeypatch):
    _patch_vision(monkeypatch)
    generation = {"current": 1}

    class ReplacingProp(_CoordinatedPropDetector):
        instances: list["ReplacingProp"] = []

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.reset_calls = 0

        def detect(self, frame):
            result = super().detect(frame)
            generation["current"] = 2
            return result

        def reset_cache(self):
            self.reset_calls += 1

    _patch_prop(monkeypatch, ReplacingProp)
    ReplacingProp.barrier = None
    evaluated = {"count": 0}

    def unexpected_evaluate(*args, **kwargs):
        evaluated["count"] += 1
        return _positive_rule()

    monkeypatch.setattr(websocket_api, "evaluate_movement", unexpected_evaluate)
    session = websocket_api.VisionSession("Hand Stall")
    try:
        _start_active(session)
        session.camera.last_capture_generation = 1
        session.camera.current_capture_generation = lambda: generation["current"]

        assert session.analyze_tick() is None
        assert evaluated["count"] == 0
        assert session._overlay_snapshot is None
        assert session._last_live_bottles == []
        assert session._last_bottles == []
        assert session._frame_index == 0
        assert session._last_ai_sequence is None
        assert ReplacingProp.instances[-1].reset_calls == 1
        assert session._custom_previous_prop is None
    finally:
        session.close()


def test_close_waits_for_direct_sequential_process_call(monkeypatch):
    _patch_vision(monkeypatch)
    _patch_prop(monkeypatch)
    _CoordinatedPropDetector.barrier = None

    class BlockingHands(StubHandsDetector):
        instances: list["BlockingHands"] = []

        def __init__(self, **kwargs):
            super().__init__(**kwargs)
            self.entered = threading.Event()
            self.release = threading.Event()
            self.closed = False
            self.closed_during_detect = False
            self.__class__.instances.append(self)

        def detect(self, frame, bottle=None):
            self.entered.set()
            assert self.release.wait(timeout=2.0)
            self.closed_during_detect = self.closed
            return None

        def close(self):
            self.closed = True

    monkeypatch.setattr(websocket_api, "HandsDetector", BlockingHands)
    monkeypatch.setattr(websocket_api, "evaluate_movement", _positive_rule)
    session = websocket_api.VisionSession("Bartender's Grip")
    _start_active(session)
    hands = BlockingHands.instances[-1]
    process_thread = threading.Thread(
        target=lambda: session.process_frame(emit_preview_jpeg=False),
        name="elixr-test-direct-process",
    )
    process_thread.start()
    assert hands.entered.wait(timeout=2.0)

    close_done = threading.Event()
    close_thread = threading.Thread(
        target=lambda: (session.close(), close_done.set()),
        name="elixr-test-direct-close",
    )
    close_thread.start()
    assert not close_done.wait(timeout=0.1)
    assert hands.closed is False

    hands.release.set()
    process_thread.join(timeout=2.0)
    close_thread.join(timeout=2.0)
    assert not process_thread.is_alive()
    assert not close_thread.is_alive()
    assert close_done.is_set()
    assert hands.closed is True
    assert hands.closed_during_detect is False
    assert session.process_frame(emit_preview_jpeg=False) is None
