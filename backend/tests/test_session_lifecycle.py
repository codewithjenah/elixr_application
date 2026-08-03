"""Unit tests for prepare / activate / stop WebSocket session lifecycle."""

from __future__ import annotations

import asyncio
from unittest.mock import MagicMock

import numpy as np

from api import websocket as websocket_api
from assessment.scoring import SessionScorer
from schemas.feedback import FeedbackMessage


def _frame(h: int = 48, w: int = 64) -> np.ndarray:
    frame = np.full((h, w, 3), 120, dtype=np.uint8)
    frame[10:20, 10:20] = 200
    return frame


class StubCamera:
    open_calls = 0
    instances: list["StubCamera"] = []

    def __init__(self, *args, **kwargs):
        self.read_count = 0
        self.released = False
        self.active_index = kwargs.get("camera_index") or 0
        self.active_device_id = kwargs.get("camera_device_id")
        self.used_fallback = False
        self.last_captured_at_monotonic = None
        self.last_capture_sequence = None
        StubCamera.instances.append(self)

    def open(self) -> bool:
        StubCamera.open_calls += 1
        return True

    def read(self):
        self.read_count += 1
        self.last_captured_at_monotonic = 1000.0 + self.read_count
        self.last_capture_sequence = self.read_count
        return _frame()

    def release(self) -> None:
        self.released = True


class StubBottleDetector:
    def __init__(self, *, enabled: bool):
        self.enabled = enabled
        self.detect_calls = 0

    def ensure_ready(self):
        pass

    def detect(self, current_frame):
        self.detect_calls += 1
        return []


class StubPropDetector:
    instances: list["StubPropDetector"] = []

    def __init__(self, *, prop_type: str, enabled: bool):
        self.prop_type = prop_type
        self.enabled = enabled
        self.ensure_calls = 0
        self.detect_calls = 0
        StubPropDetector.instances.append(self)

    def ensure_ready(self):
        self.ensure_calls += 1

    def detect(self, current_frame):
        self.detect_calls += 1
        return []


class StubHandsDetector:
    def __init__(self, **kwargs):
        self.detect_calls = 0

    def detect(self, current_frame, bottle=None):
        self.detect_calls += 1
        return None

    def close(self):
        pass


class StubPoseDetector:
    def __init__(self, **kwargs):
        self.detect_calls = 0

    def detect(self, current_frame):
        self.detect_calls += 1
        return None

    def close(self):
        pass


def _patch_vision(monkeypatch):
    StubCamera.open_calls = 0
    StubCamera.instances = []
    monkeypatch.setattr(websocket_api, "CameraCapture", StubCamera)
    monkeypatch.setattr(websocket_api, "BottleDetector", StubBottleDetector)
    monkeypatch.setattr(websocket_api, "HandsDetector", StubHandsDetector)
    monkeypatch.setattr(websocket_api, "PoseDetector", StubPoseDetector)
    monkeypatch.setattr(
        websocket_api,
        "annotate_frame",
        lambda current_frame, *a, **k: current_frame,
    )


def test_prepare_opens_one_camera_session(monkeypatch):
    _patch_vision(monkeypatch)
    evaluate_calls = {"n": 0}
    record_calls = {"n": 0}

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        raise AssertionError("evaluate_movement must not run while prepared")

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    real_record = SessionScorer.record

    def tracking_record(self, feedback_type):
        record_calls["n"] += 1
        return real_record(self, feedback_type)

    monkeypatch.setattr(SessionScorer, "record", tracking_record)

    session = websocket_api.VisionSession("Hand Stall")
    assert session.start() is True
    assert StubCamera.open_calls == 1
    assert session.is_prepared
    assert session.hands_detector is None

    message = session.process_preview_frame()
    assert message is not None
    assert message.session_state == "preparing"
    assert message.camera_ready is True
    assert message.frame_jpeg_base64 is not None
    assert evaluate_calls["n"] == 0
    assert record_calls["n"] == 0
    assert session.scorer.score == SessionScorer().score
    # Preview must not load YOLO / MediaPipe.
    assert session.hands_detector is None
    assert session._model_checked is False

    session.close()


def test_shaker_session_preserves_prop_and_loads_only_after_activation(monkeypatch):
    _patch_vision(monkeypatch)
    StubPropDetector.instances = []
    monkeypatch.setattr(websocket_api, "PropDetector", StubPropDetector)

    session = websocket_api.VisionSession("Hand Stall", prop_type="shaker")
    session.start()

    preview = session.process_preview_frame()
    assert preview is not None
    assert preview.prop_type == "shaker"
    detector = StubPropDetector.instances[-1]
    assert detector.ensure_calls == 0

    assert session.activate() is True
    active = session.process_frame()

    assert active is not None
    assert active.prop_type == "shaker"
    assert detector.ensure_calls == 1
    session.close()


def test_model_load_failure_is_structured_session_fatal_feedback(monkeypatch):
    _patch_vision(monkeypatch)

    class FailingDetector:
        def __init__(self, *, enabled: bool):
            self.enabled = enabled

        def ensure_ready(self):
            raise websocket_api.ModelLoadError("broken weights")

        def detect(self, current_frame):
            raise AssertionError("detection should not run after load failure")

    monkeypatch.setattr(websocket_api, "BottleDetector", FailingDetector)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.activate()

    message = session.process_frame()

    assert message is not None
    assert message.error_code == "model_load_failed"
    assert message.session_state == "unavailable"
    assert message.frame_jpeg_base64 is None
    session.close()


def test_prepared_process_tick_does_not_score_or_evaluate(monkeypatch):
    _patch_vision(monkeypatch)
    evaluate_calls = {"n": 0}

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        from assessment.rules.base import RuleResult

        return (
            RuleResult(
                feedback="should not run",
                feedback_type="positive",
                posture_status="stable",
            ),
            None,
            None,
        )

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    session = websocket_api.VisionSession("Normal Grip")
    session.start()

    for _ in range(3):
        msg = session.process_tick()
        assert msg is not None
        assert msg.session_state == "preparing"
        assert msg.feedback_type == "positive"

    assert evaluate_calls["n"] == 0
    assert session.hands_detector is None
    session.close()


def test_activate_reuses_same_camera_and_resets_state(monkeypatch):
    _patch_vision(monkeypatch)

    from assessment.rules.base import RuleResult

    def fake_evaluate(*args, **kwargs):
        return (
            RuleResult(
                feedback="Good form",
                feedback_type="positive",
                posture_status="stable",
            ),
            None,
            {"phase": "active"},
        )

    monkeypatch.setattr(websocket_api, "evaluate_movement", fake_evaluate)

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    cam = StubCamera.instances[0]

    session.process_preview_frame()
    session.scorer.record("error")
    session._prev_hip_center = object()  # type: ignore[assignment]
    session._movement_state = {"stale": True}
    session._last_bottles = [object()]  # type: ignore[list-item]
    session._frame_index = 9

    assert session.activate() is True
    assert session.is_active
    assert session.hands_detector is not None
    assert StubCamera.open_calls == 1
    assert cam.released is False
    assert session.scorer.score == SessionScorer().score
    assert session._prev_hip_center is None
    assert session._movement_state is None
    assert session._last_bottles == []
    assert session._frame_index == 0
    assert session._hold_validator.is_confirmed is False

    active_msg = session.process_tick()
    assert active_msg is not None
    assert active_msg.session_state == "active"
    assert active_msg.feedback == "Good form"
    assert active_msg.camera_ready is True

    # Same camera instance still in use.
    assert StubCamera.open_calls == 1
    assert not cam.released
    session.close()


def test_repeated_activate_is_idempotent(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()

    assert session.activate() is True
    assert session.activate() is True
    assert session.is_active
    assert StubCamera.open_calls == 1
    session.close()


def test_activate_after_close_returns_false(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.close()
    assert session.activate() is False


def test_stop_works_before_and_after_activation(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)

    from assessment.rules.base import RuleResult

    monkeypatch.setattr(
        websocket_api,
        "evaluate_movement",
        lambda *a, **k: (
            RuleResult(
                feedback="ok",
                feedback_type="positive",
                posture_status="stable",
            ),
            None,
            None,
        ),
    )

    async def _run():
        async def fake_send(text):
            return None

        ws = MagicMock()
        ws.send_text = fake_send

        # Stop before activation: cancel a prepared loop.
        session_ref: dict = {"session": None}
        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=False,
            )
        )

        for _ in range(50):
            if session_ref.get("session") is not None:
                break
            await asyncio.sleep(0.01)

        assert session_ref.get("session") is not None
        assert session_ref["session"].is_prepared

        await websocket_api._stop_session_task(task)
        assert task.done()
        assert session_ref.get("session") is None

        # Stop after activation.
        session_ref = {"session": None}
        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=True,
            )
        )

        for _ in range(50):
            session = session_ref.get("session")
            if session is not None and session.is_active:
                break
            await asyncio.sleep(0.01)

        assert session_ref["session"].is_active
        await websocket_api._stop_session_task(task)
        assert task.done()
        assert session_ref.get("session") is None

    asyncio.run(_run())


def test_feedback_message_optional_lifecycle_fields_default_none():
    msg = FeedbackMessage(
        bottle_detected=False,
        movement="Hand Stall",
        score=70,
        feedback="hi",
        feedback_type="positive",
        posture_status="unknown",
    )
    assert msg.camera_ready is None
    assert msg.session_state is None
    assert msg.hold_progress == 0.0
    assert msg.hold_confirmed is False
    dumped = msg.model_dump()
    assert "camera_ready" in dumped
    assert "session_state" in dumped
    assert dumped["hold_progress"] == 0.0
    assert dumped["hold_confirmed"] is False


def test_preview_frames_use_default_hold_values(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()

    message = session.process_preview_frame()
    assert message is not None
    assert message.hold_progress == 0.0
    assert message.hold_duration_ms == 0
    assert message.hold_confirmed is False
    assert message.positive_frame_ratio == 0.0
    session.close()


def test_pipeline_timing_does_not_change_feedback_payload(monkeypatch):
    _patch_vision(monkeypatch)
    from assessment.rules.base import RuleResult

    monkeypatch.setattr(
        websocket_api,
        "evaluate_movement",
        lambda *a, **k: (
            RuleResult(
                feedback="Hold steady",
                feedback_type="positive",
                posture_status="stable",
            ),
            None,
            None,
        ),
    )

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.activate() is True
    message = session.process_frame()
    assert message is not None
    assert message.feedback == "Hold steady"
    assert message.feedback_type == "positive"
    assert message.session_state == "active"
    assert message.frame_jpeg_base64
    assert session.timings._counts["total"] >= 1
    assert session.timings._frame_age_count >= 1
    session.close()


def test_cv_session_loop_keeps_one_processing_task_in_flight(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)
    monkeypatch.setattr(websocket_api, "FPS_LOG_INTERVAL", 1000)

    in_flight = {"count": 0, "max": 0}
    original = websocket_api.VisionSession.process_tick

    def slow_tick(self):
        in_flight["count"] += 1
        in_flight["max"] = max(in_flight["max"], in_flight["count"])
        try:
            return original(self)
        finally:
            in_flight["count"] -= 1

    monkeypatch.setattr(websocket_api.VisionSession, "process_tick", slow_tick)

    async def _run():
        sent = []

        async def fake_send(text):
            sent.append(text)

        ws = MagicMock()
        ws.send_text = fake_send
        session_ref: dict = {"session": None}
        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=False,
                send_text=fake_send,
            )
        )

        for _ in range(50):
            if session_ref.get("session") is not None and len(sent) >= 3:
                break
            await asyncio.sleep(0.02)

        await websocket_api._stop_session_task(task)
        assert task.done()
        assert in_flight["max"] == 1
        assert len(sent) >= 1

    asyncio.run(_run())
