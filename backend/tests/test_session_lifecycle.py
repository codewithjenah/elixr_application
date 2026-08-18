"""Unit tests for prepare / activate / stop WebSocket session lifecycle."""

from __future__ import annotations

import asyncio
from unittest.mock import MagicMock

import numpy as np
import pytest

from api import websocket as websocket_api
from assessment.readiness import (
    ReadinessSnapshot,
    ReadinessTracker,
    readiness_needs_hands,
    readiness_needs_pose,
)
from assessment.scoring import RubricTracker
from assessment.hold_validator import HoldSnapshot
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
        self.max_num_hands = kwargs.get("max_num_hands", 2)
        self.rotated_fallback = kwargs.get("rotated_fallback", False)
        self.bartender_roi_fallback = kwargs.get("bartender_roi_fallback", False)

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


def _stable_readiness_snapshot() -> ReadinessSnapshot:
    return ReadinessSnapshot(
        items=(),
        readiness_complete=True,
        readiness_stable=True,
        readiness_stable_progress=1.0,
    )


def _confirm_session_readiness(session: websocket_api.VisionSession) -> None:
    import time

    session._latest_readiness_snapshot = _stable_readiness_snapshot()
    session._latest_readiness_observed_at = time.monotonic()
    ok, error = session.confirm_readiness()
    assert ok, error


def _activate_prepared(session: websocket_api.VisionSession) -> None:
    ok, error = session.activate()
    assert (ok, error) == (True, None)


def _activate_after_readiness(session: websocket_api.VisionSession) -> None:
    _confirm_session_readiness(session)
    ok, error = session.activate()
    assert (ok, error) == (True, None)


def test_prepare_opens_one_camera_session(monkeypatch):
    _patch_vision(monkeypatch)
    evaluate_calls = {"n": 0}
    record_calls = {"n": 0}

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        raise AssertionError("evaluate_movement must not run while prepared")

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    real_record = RubricTracker.record

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    monkeypatch.setattr(RubricTracker, "record", tracking_record)

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
    assert session.rubric.snapshot(HoldSnapshot()).total == 0
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

    _activate_prepared(session)
    active = session.process_frame()

    assert active is not None
    assert active.prop_type == "shaker"
    assert detector.ensure_calls == 1
    session.close()


class _TaggedPropDetector:
    """Like StubPropDetector but detect() returns a prop_type-tagged box."""

    instances: list["_TaggedPropDetector"] = []

    def __init__(self, *, prop_type: str, enabled: bool):
        self.prop_type = prop_type
        self.enabled = enabled
        self.ensure_calls = 0
        self.detect_calls = 0
        self._fail = False
        _TaggedPropDetector.instances.append(self)

    def ensure_ready(self):
        self.ensure_calls += 1
        if self._fail:
            raise websocket_api.ModelLoadError(f"{self.prop_type} model broken")

    def detect(self, current_frame):
        self.detect_calls += 1
        from vision.types import PropDetection

        offset = 0 if self.prop_type == "bottle" else 100
        return [
            PropDetection(
                x1=offset, y1=offset, x2=offset + 10, y2=offset + 10, confidence=0.9
            )
        ]


class _StubDualPropDetector:
    """Stands in for DualPropDetector in bottle_and_shaker sessions."""

    instances: list["_StubDualPropDetector"] = []

    def __init__(self, *, enabled: bool, **kwargs):
        self.enabled = enabled
        self.ensure_calls = 0
        self.detect_calls = 0
        self._fail = False
        _StubDualPropDetector.instances.append(self)

    def ensure_ready(self):
        self.ensure_calls += 1
        if self._fail:
            raise websocket_api.ModelLoadError("combined model broken")

    def reset_cache(self):
        pass

    def detect(self, current_frame):
        self.detect_calls += 1
        from vision.dual_prop_detector import DualPropResult
        from vision.types import PropDetection

        return DualPropResult(
            bottles=[
                PropDetection(
                    x1=0, y1=0, x2=10, y2=10, confidence=0.9
                )
            ],
            shakers=[
                PropDetection(
                    x1=100, y1=100, x2=110, y2=110, confidence=0.9
                )
            ],
        )


def test_bottle_and_shaker_session_constructs_single_dual_detector(monkeypatch):
    _patch_vision(monkeypatch)
    _StubDualPropDetector.instances = []
    monkeypatch.setattr(websocket_api, "DualPropDetector", _StubDualPropDetector)

    session = websocket_api.VisionSession(
        "Bottle in a tin", prop_type="bottle_and_shaker"
    )
    session.start()
    _activate_prepared(session)
    session.process_frame()

    assert len(_StubDualPropDetector.instances) == 1
    session.close()


def test_bottle_and_shaker_model_failure_is_fatal(monkeypatch):
    _patch_vision(monkeypatch)
    _StubDualPropDetector.instances = []

    class _FailingDual(_StubDualPropDetector):
        def __init__(self, *, enabled: bool, **kwargs):
            super().__init__(enabled=enabled, **kwargs)
            self._fail = True

    monkeypatch.setattr(websocket_api, "DualPropDetector", _FailingDual)

    session = websocket_api.VisionSession(
        "Bottle in a tin", prop_type="bottle_and_shaker"
    )
    session.start()
    _activate_prepared(session)

    message = session.process_frame()

    assert message is not None
    assert message.error_code == "model_load_failed"
    session.close()


def test_bottle_and_shaker_evaluate_receives_bottles_and_shakers_separately(
    monkeypatch,
):
    _patch_vision(monkeypatch)
    _StubDualPropDetector.instances = []
    monkeypatch.setattr(websocket_api, "DualPropDetector", _StubDualPropDetector)

    captured: dict = {}

    def tracking_evaluate(*args, **kwargs):
        captured.update(kwargs)
        from assessment.rules.base import RuleResult

        return (
            RuleResult(
                feedback="ok", feedback_type="positive", posture_status="stable"
            ),
            None,
            None,
        )

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    session = websocket_api.VisionSession(
        "Bottle in a tin", prop_type="bottle_and_shaker"
    )
    session.start()
    _activate_prepared(session)
    session.process_frame()

    assert captured["prop_type"] == "bottle_and_shaker"
    assert len(captured["bottles"]) == 1
    assert len(captured["shakers"]) == 1
    assert captured["bottles"] != captured["shakers"]
    session.close()


def test_bottle_and_shaker_annotation_receives_combined_boxes(monkeypatch):
    _patch_vision(monkeypatch)
    _StubDualPropDetector.instances = []
    monkeypatch.setattr(websocket_api, "DualPropDetector", _StubDualPropDetector)

    captured_boxes = {"boxes": None}

    def tracking_annotate(current_frame, boxes, *a, **k):
        captured_boxes["boxes"] = boxes
        return current_frame

    monkeypatch.setattr(websocket_api, "annotate_frame", tracking_annotate)

    session = websocket_api.VisionSession(
        "Bottle in a tin", prop_type="bottle_and_shaker"
    )
    session.start()
    _activate_prepared(session)
    session.process_frame()

    assert captured_boxes["boxes"] is not None
    assert len(captured_boxes["boxes"]) == 2
    session.close()


def test_bottle_and_shaker_caches_reset_on_activation(monkeypatch):
    """Re-preparing and reactivating a dual-prop session must clear stale

    detections rather than inheriting cached state from a prior activation.
    """
    _patch_vision(monkeypatch)
    _StubDualPropDetector.instances = []
    monkeypatch.setattr(websocket_api, "DualPropDetector", _StubDualPropDetector)

    session = websocket_api.VisionSession(
        "Bottle in a tin", prop_type="bottle_and_shaker"
    )
    session.start()
    _activate_prepared(session)
    session.process_frame()

    assert session._last_bottles
    assert session._last_shakers

    session._lifecycle = websocket_api.SESSION_PREPARED
    _activate_prepared(session)

    assert session._last_bottles == []
    assert session._last_shakers == []
    session.close()


def test_single_prop_session_still_uses_one_detector_without_dual_overhead(
    monkeypatch,
):
    _patch_vision(monkeypatch)
    _TaggedPropDetector.instances = []
    monkeypatch.setattr(websocket_api, "PropDetector", _TaggedPropDetector)

    session = websocket_api.VisionSession("Hand Stall", prop_type="shaker")
    session.start()
    _activate_prepared(session)
    session.process_frame()

    assert len(_TaggedPropDetector.instances) == 1
    assert _TaggedPropDetector.instances[0].prop_type == "shaker"
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
    _activate_prepared(session)

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
    session.rubric.activate()
    session.rubric.record(
        feedback_code="prop_not_steady",
        feedback_type="warning",
        posture_status="unstable",
        timestamp=1.0,
    )
    session._prev_hip_center = object()  # type: ignore[assignment]
    session._movement_state = {"stale": True}
    session._last_bottles = [object()]  # type: ignore[list-item]
    session._frame_index = 9

    _activate_prepared(session)
    assert session.is_active
    assert session.hands_detector is not None
    assert StubCamera.open_calls == 1
    assert cam.released is False
    assert session.rubric.snapshot(HoldSnapshot()).total == 0
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


def test_skipped_yolo_frames_extrapolate_cached_props(monkeypatch):
    """Guided, free-practice, and readiness skip frames all coast via the detector."""
    from config import YOLO_FRAME_SKIP
    from vision.types import PropDetection

    _patch_vision(monkeypatch)

    class TrackingDetector:
        instances: list["TrackingDetector"] = []

        def __init__(self, *args, enabled: bool = True, prop_type: str = "bottle", **kwargs):
            self.enabled = enabled
            self.prop_type = prop_type
            self.detect_calls = 0
            self.extrapolate_calls = 0
            TrackingDetector.instances.append(self)

        def ensure_ready(self):
            pass

        def detect(self, current_frame):
            self.detect_calls += 1
            return [
                PropDetection(
                    x1=10, y1=10, x2=50, y2=90, confidence=0.9, track_id=1
                )
            ]

        def extrapolate_detections(self, *, bottles, shakers, now):
            self.extrapolate_calls += 1
            assert now > 0
            return bottles, shakers

    monkeypatch.setattr(websocket_api, "BottleDetector", TrackingDetector)
    monkeypatch.setattr(websocket_api, "PropDetector", TrackingDetector)

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

    def _drive_skip_frames(session: websocket_api.VisionSession) -> TrackingDetector:
        detector = TrackingDetector.instances[-1]
        for _ in range(YOLO_FRAME_SKIP):
            msg = session.process_tick()
            assert msg is not None
        assert detector.detect_calls == 1
        assert detector.extrapolate_calls == YOLO_FRAME_SKIP - 1
        return detector

    TrackingDetector.instances = []
    guided = websocket_api.VisionSession("Hand Stall")
    guided.start()
    _activate_prepared(guided)
    _drive_skip_frames(guided)
    guided.close()

    TrackingDetector.instances = []
    free = websocket_api.VisionSession("Free Practice", prop_type="shaker")
    free.start()
    _activate_prepared(free)
    _drive_skip_frames(free)
    free.close()

    TrackingDetector.instances = []
    readiness = websocket_api.VisionSession("Hand Stall")
    readiness.start()
    readiness.begin_readiness()
    _drive_skip_frames(readiness)
    readiness.close()


def test_repeated_activate_is_idempotent(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()

    _activate_prepared(session)
    _activate_prepared(session)
    assert session.is_active
    assert StubCamera.open_calls == 1
    session.close()


def test_activate_after_close_returns_false(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.close()
    assert session.activate() == (False, "session_not_prepared")


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
    assert message.hold_target_ms == 0
    assert message.feedback_code is None
    assert message.feedback_category is None
    session.close()


def test_active_frame_derives_feedback_category_from_registry(monkeypatch):
    _patch_vision(monkeypatch)
    from assessment.feedback_codes import FeedbackCategory, FeedbackCode
    from assessment.rules.base import RuleResult

    monkeypatch.setattr(
        websocket_api,
        "evaluate_movement",
        lambda *a, **k: (
            RuleResult(
                feedback="Hand stall locked in.",
                feedback_type="positive",
                posture_status="stable",
                feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
            ),
            None,
            None,
        ),
    )

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    _activate_prepared(session)
    message = session.process_frame()
    assert message is not None
    assert message.feedback_code == FeedbackCode.HAND_STALL_LOCKED.value
    assert message.feedback_category == FeedbackCategory.TECHNIQUE.value
    assert message.hold_target_ms > 0
    session.close()


def test_active_frame_unknown_code_leaves_category_null(monkeypatch):
    _patch_vision(monkeypatch)
    from assessment.rules.base import RuleResult

    monkeypatch.setattr(
        websocket_api,
        "evaluate_movement",
        lambda *a, **k: (
            RuleResult(
                feedback="Keep steady",
                feedback_type="warning",
                posture_status="unstable",
                feedback_code="not_a_registered_code",
            ),
            None,
            None,
        ),
    )

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    _activate_prepared(session)
    message = session.process_frame()
    assert message is not None
    assert message.feedback_code == "not_a_registered_code"
    assert message.feedback_category is None
    session.close()


def test_active_frame_missing_code_remains_legacy_safe(monkeypatch):
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
    _activate_prepared(session)
    message = session.process_frame()
    assert message is not None
    assert message.feedback_code is None
    assert message.feedback_category is None
    assert message.hold_target_ms > 0
    session.close()


def test_free_practice_active_frame_has_no_coaching_identity(monkeypatch):
    _patch_vision(monkeypatch)
    StubPropDetector.instances = []
    monkeypatch.setattr(websocket_api, "PropDetector", StubPropDetector)

    session = websocket_api.VisionSession("Free Practice", prop_type="shaker")
    session.start()
    _activate_prepared(session)
    message = session.process_frame()
    assert message is not None
    assert message.movement == "Free Practice"
    assert message.feedback_code is None
    assert message.feedback_category is None
    assert message.hold_target_ms == 0
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
    _activate_prepared(session)
    message = session.process_frame()
    assert message is not None
    assert message.feedback == "Hold steady"
    assert message.feedback_type == "positive"
    assert message.session_state == "active"
    assert message.frame_jpeg_base64
    assert session.timings._counts["processing_total"] >= 1
    assert session.timings._frame_age_count >= 1
    session.close()


def test_free_practice_skips_hands_pose_scoring_and_hold(monkeypatch):
    _patch_vision(monkeypatch)
    StubPropDetector.instances = []
    monkeypatch.setattr(websocket_api, "PropDetector", StubPropDetector)

    hands_inits = {"n": 0}
    pose_inits = {"n": 0}
    evaluate_calls = {"n": 0}
    record_calls = {"n": 0}
    hold_calls = {"n": 0}

    class TrackingHands(StubHandsDetector):
        def __init__(self, **kwargs):
            hands_inits["n"] += 1
            super().__init__(**kwargs)

    class TrackingPose(StubPoseDetector):
        def __init__(self, **kwargs):
            pose_inits["n"] += 1
            super().__init__(**kwargs)

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)
    monkeypatch.setattr(websocket_api, "PoseDetector", TrackingPose)

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        raise AssertionError("Free Practice must not evaluate movements")

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    real_record = RubricTracker.record

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    monkeypatch.setattr(RubricTracker, "record", tracking_record)

    real_hold_update = websocket_api.HoldValidator.update

    def tracking_hold(self, *args, **kwargs):
        hold_calls["n"] += 1
        return real_hold_update(self, *args, **kwargs)

    monkeypatch.setattr(websocket_api.HoldValidator, "update", tracking_hold)

    session = websocket_api.VisionSession("Free Practice", prop_type="shaker")
    assert session.is_prop_detection_only
    session.start()
    _activate_prepared(session)
    assert session.hands_detector is None
    assert session.pose_detector is None
    assert hands_inits["n"] == 0
    assert pose_inits["n"] == 0

    message = session.process_frame()
    assert message is not None
    assert message.movement == "Free Practice"
    assert message.prop_type == "shaker"
    assert message.session_state == "active"
    assert message.assessment is None
    assert message.hold_progress == 0.0
    assert message.hold_confirmed is False
    assert message.frame_jpeg_base64

    detector = StubPropDetector.instances[-1]
    assert detector.ensure_calls == 1
    assert detector.detect_calls >= 1
    assert evaluate_calls["n"] == 0
    assert record_calls["n"] == 0
    assert hold_calls["n"] == 0
    assert hands_inits["n"] == 0
    assert pose_inits["n"] == 0
    assert session.hands_detector is None
    assert session.pose_detector is None
    session.close()


def test_free_practice_is_registered_but_internal():
    from assessment.rule_engine import (
        is_known_movement,
        movement_is_internal,
        movement_is_prop_detection_only,
        movement_requires_hands,
        validate_movement_difficulty,
    )

    assert is_known_movement("Free Practice")
    assert movement_is_internal("Free Practice")
    assert movement_is_prop_detection_only("Free Practice")
    assert movement_requires_hands("Free Practice") is False
    difficulty, error = validate_movement_difficulty("Free Practice", "Easy")
    assert error is None
    assert difficulty == "Easy"
    assert movement_is_internal("Normal Grip") is False


def test_cv_session_loop_keeps_one_processing_task_in_flight(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)
    monkeypatch.setattr(websocket_api, "FPS_LOG_INTERVAL", 1000)

    in_flight = {"count": 0, "max": 0}
    original = websocket_api.VisionSession.render_preview

    def slow_tick(self):
        in_flight["count"] += 1
        in_flight["max"] = max(in_flight["max"], in_flight["count"])
        try:
            return original(self)
        finally:
            in_flight["count"] -= 1

    monkeypatch.setattr(websocket_api.VisionSession, "render_preview", slow_tick)

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


def test_slow_session_start_does_not_block_event_loop(monkeypatch):
    """Blocking camera open runs off the event loop."""
    import time

    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)

    def slow_open(self) -> bool:
        time.sleep(0.25)
        StubCamera.open_calls += 1
        return True

    monkeypatch.setattr(StubCamera, "open", slow_open)

    async def _run():
        sleep_deltas: list[float] = []

        async def ticker():
            for _ in range(5):
                t0 = time.monotonic()
                await asyncio.sleep(0.05)
                sleep_deltas.append(time.monotonic() - t0)

        prepare_gate = {
            "event": asyncio.Event(),
            "ok": False,
            "error_code": None,
            "message": None,
            "signaled": False,
        }

        async def fake_send(_text):
            return None

        ws = MagicMock()
        session_ref: dict = {"session": None, "session_id": None}
        loop_task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                prepare_gate=prepare_gate,
                send_text=fake_send,
            )
        )
        tick_task = asyncio.create_task(ticker())

        await asyncio.wait_for(prepare_gate["event"].wait(), timeout=5.0)
        assert prepare_gate["ok"] is True

        await websocket_api._stop_session_task(loop_task)
        await tick_task

        assert sleep_deltas, "ticker never ran"
        for delta in sleep_deltas:
            assert delta < 0.15, f"event loop blocked during camera open: {delta:.3f}s"

    asyncio.run(_run())


def test_slow_session_close_does_not_block_event_loop(monkeypatch):
    """Blocking camera release runs off the event loop."""
    import time

    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)

    def slow_release(self) -> None:
        time.sleep(0.25)
        self.released = True

    monkeypatch.setattr(StubCamera, "release", slow_release)

    async def _run():
        sleep_deltas: list[float] = []

        async def ticker():
            for _ in range(5):
                t0 = time.monotonic()
                await asyncio.sleep(0.05)
                sleep_deltas.append(time.monotonic() - t0)

        async def fake_send(_text):
            return None

        ws = MagicMock()
        session_ref: dict = {"session": None}
        loop_task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=False,
                send_text=fake_send,
            )
        )

        for _ in range(50):
            if session_ref.get("session") is not None:
                break
            await asyncio.sleep(0.01)

        tick_task = asyncio.create_task(ticker())
        await websocket_api._stop_session_task(loop_task)
        await tick_task

        assert sleep_deltas, "ticker never ran"
        for delta in sleep_deltas:
            assert delta < 0.15, f"event loop blocked during camera close: {delta:.3f}s"

    asyncio.run(_run())


def test_cancel_waits_for_in_flight_frame_before_close(monkeypatch):
    """Cancelled session awaits the active frame task before releasing camera."""
    import threading

    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)

    frame_started = threading.Event()
    frame_can_finish = threading.Event()
    release_after_frame = {"ok": False}
    original_tick = websocket_api.VisionSession.render_preview

    def gated_tick(self):
        frame_started.set()
        frame_can_finish.wait(timeout=2.0)
        try:
            return original_tick(self)
        finally:
            release_after_frame["ok"] = True

    monkeypatch.setattr(websocket_api.VisionSession, "render_preview", gated_tick)

    original_release = StubCamera.release

    def tracking_release(self):
        assert release_after_frame["ok"], "release ran before in-flight frame finished"
        return original_release(self)

    monkeypatch.setattr(StubCamera, "release", tracking_release)

    async def _run():
        async def fake_send(_text):
            return None

        ws = MagicMock()
        session_ref: dict = {"session": None}
        loop_task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                send_text=fake_send,
            )
        )

        for _ in range(100):
            if frame_started.is_set():
                break
            await asyncio.sleep(0.01)
        assert frame_started.is_set()

        loop_task.cancel()
        frame_can_finish.set()
        try:
            await loop_task
        except asyncio.CancelledError:
            pass

        assert release_after_frame["ok"]
        assert StubCamera.instances[-1].released is True

    asyncio.run(_run())


def test_cancel_reraises_after_cleanup(monkeypatch):
    """CancelledError propagates after in-flight frame and camera cleanup."""
    import threading

    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)

    frame_started = threading.Event()
    frame_can_finish = threading.Event()
    original_tick = websocket_api.VisionSession.render_preview

    def gated_tick(self):
        frame_started.set()
        frame_can_finish.wait(timeout=2.0)
        return original_tick(self)

    monkeypatch.setattr(websocket_api.VisionSession, "render_preview", gated_tick)

    async def _run():
        async def fake_send(_text):
            return None

        ws = MagicMock()
        loop_task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                send_text=fake_send,
            )
        )

        for _ in range(100):
            if frame_started.is_set():
                break
            await asyncio.sleep(0.01)
        assert frame_started.is_set()

        loop_task.cancel()
        frame_can_finish.set()
        cancelled = False
        try:
            await loop_task
        except asyncio.CancelledError:
            cancelled = True

        assert cancelled
        assert StubCamera.instances[-1].released is True

    asyncio.run(_run())


def test_cancel_releases_camera_exactly_once(monkeypatch):
    """Camera release runs once during cancellation cleanup."""
    import threading

    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)

    frame_started = threading.Event()
    frame_can_finish = threading.Event()
    release_calls = {"n": 0}
    original_tick = websocket_api.VisionSession.render_preview
    original_release = StubCamera.release

    def gated_tick(self):
        frame_started.set()
        frame_can_finish.wait(timeout=2.0)
        return original_tick(self)

    def counting_release(self):
        release_calls["n"] += 1
        return original_release(self)

    monkeypatch.setattr(websocket_api.VisionSession, "render_preview", gated_tick)
    monkeypatch.setattr(StubCamera, "release", counting_release)

    async def _run():
        async def fake_send(_text):
            return None

        ws = MagicMock()
        loop_task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                send_text=fake_send,
            )
        )

        for _ in range(100):
            if frame_started.is_set():
                break
            await asyncio.sleep(0.01)

        loop_task.cancel()
        frame_can_finish.set()
        try:
            await loop_task
        except asyncio.CancelledError:
            pass

        assert release_calls["n"] == 1

    asyncio.run(_run())


def test_process_tick_exception_still_closes_camera(monkeypatch):
    """A frame-processing failure still releases the camera on loop exit."""
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)

    def failing_tick(self):
        raise RuntimeError("synthetic frame failure")

    monkeypatch.setattr(websocket_api.VisionSession, "render_preview", failing_tick)

    async def _run():
        sent: list[str] = []

        async def fake_send(text):
            sent.append(text)

        ws = MagicMock()
        session_ref: dict = {"session": None}
        loop_task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                send_text=fake_send,
            )
        )

        for _ in range(100):
            if session_ref.get("session") is not None:
                break
            await asyncio.sleep(0.01)

        await loop_task
        assert StubCamera.instances[-1].released is True
        assert len(sent) == 1
        assert "pipeline_error" in sent[0]

    asyncio.run(_run())


def test_cancel_cleanup_does_not_start_second_frame(monkeypatch):
    """Cancellation cleanup does not launch another render_preview."""
    import threading

    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)

    frame_started = threading.Event()
    frame_can_finish = threading.Event()
    tick_calls = {"n": 0}
    original_tick = websocket_api.VisionSession.render_preview

    def gated_tick(self):
        tick_calls["n"] += 1
        frame_started.set()
        frame_can_finish.wait(timeout=2.0)
        return original_tick(self)

    monkeypatch.setattr(websocket_api.VisionSession, "render_preview", gated_tick)

    async def _run():
        async def fake_send(_text):
            return None

        ws = MagicMock()
        loop_task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                send_text=fake_send,
            )
        )

        for _ in range(100):
            if frame_started.is_set():
                break
            await asyncio.sleep(0.01)

        loop_task.cancel()
        frame_can_finish.set()
        try:
            await loop_task
        except asyncio.CancelledError:
            pass

        assert tick_calls["n"] == 1

    asyncio.run(_run())


def test_startup_failure_clears_session_identity(monkeypatch):
    """Failed camera open rejects prepare and clears session_ref identity."""
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)

    def failing_open(self) -> bool:
        StubCamera.open_calls += 1
        return False

    monkeypatch.setattr(StubCamera, "open", failing_open)

    async def _run():
        prepare_gate = {
            "event": asyncio.Event(),
            "ok": False,
            "error_code": None,
            "message": None,
            "signaled": False,
        }
        sent: list[str] = []

        async def fake_send(text):
            sent.append(text)

        ws = MagicMock()
        session_ref: dict = {"session": None, "session_id": "session-fail"}
        loop_task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                session_id="session-fail",
                prepare_gate=prepare_gate,
                send_text=fake_send,
            )
        )

        await asyncio.wait_for(prepare_gate["event"].wait(), timeout=2.0)
        await loop_task

        assert prepare_gate["ok"] is False
        assert session_ref["session"] is None
        assert session_ref["session_id"] is None
        assert len(sent) == 1
        assert "error_code" in sent[0]

    asyncio.run(_run())


# ---------------------------------------------------------------------------
# Phase 2: Readiness Gate lifecycle tests
# ---------------------------------------------------------------------------


def test_readiness_needs_helpers_classify_movements():
    """readiness_needs_hands/pose return the expected values per movement."""
    # Grip movements: hands only.
    for mv in ("Normal Grip", "Bartender's Grip", "Reverse Grip", "Claw Grip"):
        assert readiness_needs_hands(mv) is True, mv
        assert readiness_needs_pose(mv) is False, mv

    # Hand Stall / One Finger Stall: hands only.
    assert readiness_needs_hands("Hand Stall") is True
    assert readiness_needs_pose("Hand Stall") is False
    assert readiness_needs_hands("One Finger Stall") is True
    assert readiness_needs_pose("One Finger Stall") is False

    # Forearm / Elbow Stall: pose only (upper_body_visible; no hand fallback).
    for mv in ("Forearm Stall", "Elbow Stall", "Arm Stall"):
        assert readiness_needs_hands(mv) is False, mv
        assert readiness_needs_pose(mv) is True, mv

    # Reverse Forearm / Upper Forearm / Shoulder: pose only.
    for mv in ("Reverse Forearm Stall", "Upper Forearm Stall", "Shoulder Stall"):
        assert readiness_needs_hands(mv) is False, mv
        assert readiness_needs_pose(mv) is True, mv

    # Double Hand Stall: hands only.
    assert readiness_needs_hands("Double Hand Stall") is True
    assert readiness_needs_pose("Double Hand Stall") is False

    # Bottle in a tin: hands only (supporting_hand_visible).
    assert readiness_needs_hands("Bottle in a tin") is True
    assert readiness_needs_pose("Bottle in a tin") is False


def test_begin_readiness_transitions_prepared_to_readying(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()

    assert session.is_prepared
    result = session.begin_readiness()
    assert result is True
    assert session.is_readying
    assert not session.is_prepared
    assert not session.is_active
    session.close()


def test_begin_readiness_is_idempotent_when_already_readying(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()

    assert session.begin_readiness() is True
    assert session.begin_readiness() is True  # second call is idempotent
    assert session.is_readying
    assert StubCamera.open_calls == 1
    session.close()


def test_begin_readiness_after_close_returns_false(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.close()
    assert session.begin_readiness() is False


def test_begin_readiness_after_activate_returns_false(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    _activate_prepared(session)
    assert session.begin_readiness() is False


def test_process_readiness_frame_does_not_evaluate_or_score(monkeypatch):
    """prepare -> begin_readiness -> process_readiness_frame must not call
    evaluate_movement or rubric.record."""
    _patch_vision(monkeypatch)
    evaluate_calls = {"n": 0}
    record_calls = {"n": 0}

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        raise AssertionError("evaluate_movement must not run during readiness")

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    real_record = RubricTracker.record

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    monkeypatch.setattr(RubricTracker, "record", tracking_record)

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()

    msg = session.process_readiness_frame()

    assert msg is not None
    assert msg.session_state == "readying"
    assert msg.camera_ready is True
    assert msg.frame_jpeg_base64 is not None
    assert msg.readiness_items is not None
    assert msg.readiness_complete is not None
    assert msg.readiness_stable is not None
    assert msg.readiness_stable_progress is not None
    assert evaluate_calls["n"] == 0
    assert record_calls["n"] == 0
    # Score must be the unmodified baseline (no recording happened).
    assert msg.assessment is None
    session.close()


def test_process_tick_dispatches_readiness_frame_when_readying(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()

    msg = session.process_tick()
    assert msg is not None
    assert msg.session_state == "readying"
    session.close()


def test_camera_opens_once_across_readying_and_activate(monkeypatch):
    _patch_vision(monkeypatch)
    from assessment.rules.base import RuleResult

    monkeypatch.setattr(
        websocket_api,
        "evaluate_movement",
        lambda *a, **k: (
            RuleResult(feedback="ok", feedback_type="positive", posture_status="stable"),
            None,
            None,
        ),
    )

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert StubCamera.open_calls == 1

    session.begin_readiness()
    session.process_readiness_frame()
    _activate_after_readiness(session)
    session.process_frame()

    assert StubCamera.open_calls == 1, "camera must open only once"
    session.close()


def test_hands_detector_created_once_across_readiness_and_activate(monkeypatch):
    """For a grip movement that needs hands, the detector is created during
    begin_readiness and reused by activate; no second instance is created."""
    _patch_vision(monkeypatch)

    hands_inits = {"n": 0}

    class TrackingHands(StubHandsDetector):
        def __init__(self, **kwargs):
            hands_inits["n"] += 1
            super().__init__(**kwargs)

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)
    from assessment.rules.base import RuleResult

    monkeypatch.setattr(
        websocket_api,
        "evaluate_movement",
        lambda *a, **k: (
            RuleResult(feedback="ok", feedback_type="positive", posture_status="stable"),
            None,
            None,
        ),
    )

    session = websocket_api.VisionSession("Hand Stall")
    session.start()

    # begin_readiness creates the hands detector (Hand Stall needs hands).
    assert session.hands_detector is None
    session.begin_readiness()
    assert session.hands_detector is not None
    assert hands_inits["n"] == 1

    # activate calls _ensure_detectors, but hands_detector is not None → no new creation.
    _activate_after_readiness(session)
    assert hands_inits["n"] == 1, "hands detector must not be re-created on activate"
    session.close()


_POSE_ONLY_STALLS = (
    "Forearm Stall",
    "Elbow Stall",
    "Reverse Forearm Stall",
    "Shoulder Stall",
    "Arm Stall",
    "Upper Forearm Stall",
)


@pytest.mark.parametrize("movement", _POSE_ONLY_STALLS)
def test_pose_only_movement_creates_pose_on_readiness_not_hands_on_activate(
    monkeypatch, movement
):
    """Pose-only stalls load Pose for readiness and must not construct
    Hands on activate. Pose is reused, not recreated."""
    _patch_vision(monkeypatch)

    hands_inits = {"n": 0}
    pose_inits = {"n": 0}

    class TrackingHands(StubHandsDetector):
        def __init__(self, **kwargs):
            hands_inits["n"] += 1
            super().__init__(**kwargs)

    class TrackingPose(StubPoseDetector):
        def __init__(self, **kwargs):
            pose_inits["n"] += 1
            super().__init__(**kwargs)

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)
    monkeypatch.setattr(websocket_api, "PoseDetector", TrackingPose)

    from assessment.rules.base import RuleResult

    monkeypatch.setattr(
        websocket_api,
        "evaluate_movement",
        lambda *a, **k: (
            RuleResult(feedback="ok", feedback_type="positive", posture_status="stable"),
            None,
            None,
        ),
    )

    session = websocket_api.VisionSession(movement)
    session.start()

    session.begin_readiness()
    assert session.hands_detector is None, movement
    assert session.pose_detector is not None, movement
    assert pose_inits["n"] == 1
    assert hands_inits["n"] == 0

    _activate_after_readiness(session)
    assert pose_inits["n"] == 1, "pose must not be re-created on activate"
    assert hands_inits["n"] == 0, "pose-only stalls must not construct Hands"
    assert session.hands_detector is None, movement
    assert session.pose_detector is not None, movement
    session.close()


@pytest.mark.parametrize("movement", _POSE_ONLY_STALLS)
def test_pose_only_active_frame_never_calls_hands_detect(monkeypatch, movement):
    """Pose-only active frames run Pose, never Hands.detect, and pass
    hands=None into evaluate_movement. Hands must not appear in CV PERF."""
    _patch_vision(monkeypatch)

    class TrackingHands(StubHandsDetector):
        detect_total = 0

        def detect(self, current_frame, bottle=None):
            TrackingHands.detect_total += 1
            return super().detect(current_frame, bottle)

    class TrackingPose(StubPoseDetector):
        pass

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)
    monkeypatch.setattr(websocket_api, "PoseDetector", TrackingPose)

    from assessment.rules.base import RuleResult

    captured = {}

    def tracking_evaluate(eval_movement, bottle, pose, hands, *args, **kwargs):
        captured["hands"] = hands
        return (
            RuleResult(feedback="ok", feedback_type="positive", posture_status="stable"),
            None,
            None,
        )

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    session = websocket_api.VisionSession(movement)
    session.start()
    session.begin_readiness()
    _activate_after_readiness(session)

    assert session.hands_detector is None, movement
    assert session.pose_detector is not None, movement

    msg = session.process_frame()
    assert msg is not None
    assert session.hands_detector is None, movement
    assert TrackingHands.detect_total == 0, movement
    assert session.pose_detector.detect_calls >= 1, movement
    assert captured.get("hands") is None, movement
    timing = session.timings.format_averages_ms(frame_budget_ms=33.3)
    assert "hands=" not in timing, timing
    assert "pose=" in timing, timing
    session.close()


def test_hand_stall_active_calls_hands_and_drops_pose(monkeypatch):
    """Hand Stall keeps HandsDetector, calls Hands.detect, and does not keep Pose."""
    _patch_vision(monkeypatch)

    class TrackingHands(StubHandsDetector):
        pass

    class TrackingPose(StubPoseDetector):
        pass

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)
    monkeypatch.setattr(websocket_api, "PoseDetector", TrackingPose)

    from assessment.rules.base import RuleResult

    monkeypatch.setattr(
        websocket_api,
        "evaluate_movement",
        lambda *a, **k: (
            RuleResult(feedback="ok", feedback_type="positive", posture_status="stable"),
            None,
            None,
        ),
    )

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()
    assert session.hands_detector is not None
    assert session.pose_detector is None

    _activate_after_readiness(session)
    assert session.hands_detector is not None
    assert session.pose_detector is None

    msg = session.process_frame()
    assert msg is not None
    assert session.hands_detector is not None
    assert session.hands_detector.detect_calls >= 1
    assert session.pose_detector is None
    session.close()


def test_readying_to_active_via_activate_clears_readiness_tracker(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()

    assert session._readiness_tracker is not None
    _activate_after_readiness(session)
    assert session._readiness_tracker is None
    assert session.is_active
    session.close()


def test_close_clears_readiness_tracker(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()
    assert session._readiness_tracker is not None
    session.close()
    assert session._readiness_tracker is None


def test_prepared_to_active_directly_still_works(monkeypatch):
    """Free Practice / direct-activate path: prepare -> activate without readiness."""
    _patch_vision(monkeypatch)
    StubPropDetector.instances = []
    monkeypatch.setattr(websocket_api, "PropDetector", StubPropDetector)

    session = websocket_api.VisionSession("Free Practice", prop_type="shaker")
    session.start()
    assert session.is_prepared

    assert session.activate() == (True, None)
    assert session.is_active
    assert session._readiness_tracker is None

    msg = session.process_tick()
    assert msg is not None
    assert msg.session_state == "active"
    session.close()


def test_readiness_frame_session_state_is_readying_not_preparing(monkeypatch):
    """process_readiness_frame must emit session_state='readying', not 'preparing'."""
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Normal Grip")
    session.start()
    session.begin_readiness()

    msg = session.process_readiness_frame()
    assert msg is not None
    assert msg.session_state == "readying"
    assert msg.readiness_items is not None
    session.close()


def test_readiness_stop_cleans_up(monkeypatch):
    """Stopping from the READYING state must release the camera and clear state."""
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)

    async def _run():
        async def fake_send(text):
            return None

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

        for _ in range(100):
            if session_ref.get("session") is not None:
                break
            await asyncio.sleep(0.01)

        session = session_ref["session"]
        assert session is not None
        assert session.is_prepared

        # Transition to readying.
        session.begin_readiness()
        assert session.is_readying

        await websocket_api._stop_session_task(task)
        assert task.done()
        assert session_ref.get("session") is None
        assert StubCamera.instances[-1].released is True

    asyncio.run(_run())
