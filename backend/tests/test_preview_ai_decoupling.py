"""Preview cadence must stay independent of AI inference and scoring."""

from __future__ import annotations

import asyncio
import json
import time
from unittest.mock import MagicMock

import numpy as np
import pytest

from api import websocket as websocket_api
from assessment.rules.base import RuleResult
from assessment.scoring import RubricTracker
from schemas.feedback import PreviewFrameMessage
from test_session_lifecycle import (
    StubCamera,
    _patch_vision,
)
from vision.camera import CapturedFrame
from vision.overlay_snapshot import freeze_overlay
from vision.types import PropDetection


def _decode(payload: str) -> dict:
    return json.loads(payload)


def test_outbound_mailbox_keeps_latest_preview_only():
    async def _run():
        mailbox = websocket_api._OutboundMailbox()
        stop = asyncio.Event()
        mailbox.put(
            websocket_api._OutboundItem("preview", "old", None)
        )
        mailbox.put(
            websocket_api._OutboundItem("preview", "new", None)
        )
        assert mailbox.preview_replaced == 1
        batch = await mailbox.take_batch(stop)
        assert [item.payload for item in batch] == ["new"]

    asyncio.run(_run())


def test_outbound_mailbox_never_drops_must_deliver_feedback():
    async def _run():
        mailbox = websocket_api._OutboundMailbox()
        stop = asyncio.Event()
        for index in range(websocket_api._FEEDBACK_PENDING_MAX):
            mailbox.put(
                websocket_api._OutboundItem("feedback", f"f{index}", None)
            )
        mailbox.put(
            websocket_api._OutboundItem("feedback", "dropped", None)
        )
        mailbox.put(
            websocket_api._OutboundItem(
                "feedback",
                "hold",
                None,
                must_deliver=True,
            )
        )
        assert mailbox.feedback_replaced == 1
        batch = await mailbox.take_batch(stop)
        payloads = [item.payload for item in batch]
        assert "dropped" not in payloads
        assert "hold" in payloads
        assert len(payloads) == websocket_api._FEEDBACK_PENDING_MAX + 1

    asyncio.run(_run())


def test_preview_frame_message_has_no_scoring_fields():
    dumped = json.loads(
        PreviewFrameMessage(
            frame_jpeg_base64="abcd",
            camera_ready=True,
            session_state="active",
            capture_sequence=3,
        )
        .with_session("session-1")
        .model_dump_json()
    )
    assert dumped["message_type"] == "preview_frame"
    assert dumped["session_id"] == "session-1"
    assert "assessment" not in dumped
    assert "hold_confirmed" not in dumped
    assert "readiness_items" not in dumped
    assert "feedback" not in dumped


def test_analyze_tick_skips_prepared_lifecycle(monkeypatch):
    _patch_vision(monkeypatch)
    evaluate_calls = {"n": 0}

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
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
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    assert session.analyze_tick() is None
    assert evaluate_calls["n"] == 0
    session.close()


def test_stale_overlay_expires_instead_of_drawing(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic() - 1.0,
            captured_at_monotonic=time.monotonic() - 1.1,
            capture_sequence=1,
            boxes=[PropDetection(1, 2, 3, 4, 0.9)],
            hands=None,
            pose=None,
            feedback="ghost",
            feedback_type="positive",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    assert session._read_fresh_overlay() is None
    session.close()


def test_fresh_overlay_is_readable(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session._publish_overlay(
        freeze_overlay(
            published_at_monotonic=time.monotonic(),
            captured_at_monotonic=time.monotonic(),
            capture_sequence=2,
            boxes=[PropDetection(1, 2, 3, 4, 0.9)],
            hands=None,
            pose=None,
            feedback="ok",
            feedback_type="positive",
            movement="Hand Stall",
            prop_label="Bottle",
        )
    )
    snapshot = session._read_fresh_overlay()
    assert snapshot is not None
    assert snapshot.capture_sequence == 2
    session.close()


def test_render_preview_does_not_evaluate_or_score(monkeypatch):
    _patch_vision(monkeypatch)
    evaluate_calls = {"n": 0}
    record_calls = {"n": 0}
    real_record = RubricTracker.record

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        raise AssertionError("preview must not evaluate movement")

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)
    monkeypatch.setattr(RubricTracker, "record", tracking_record)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    ok, error = session.activate()
    assert (ok, error) == (True, None)
    message = session.render_preview()
    assert message is not None
    assert message.message_type == "preview_frame"
    assert message.frame_jpeg_base64
    assert evaluate_calls["n"] == 0
    assert record_calls["n"] == 0
    session.close()


def test_render_preview_skips_duplicate_capture_sequence(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()

    def peek_latest(*, newer_than=None, timeout=None):
        frame = np.full((48, 64, 3), 120, dtype=np.uint8)
        sequence = 7
        if newer_than is not None and sequence <= newer_than:
            return None
        return CapturedFrame(
            frame=frame,
            captured_at_monotonic=time.monotonic(),
            sequence=sequence,
        )

    session.camera.peek_latest = peek_latest
    first = session.render_preview()
    second = session.render_preview()
    assert first is not None
    assert first.capture_sequence == 7
    assert second is None
    session.close()


def test_analyze_tick_rejects_second_in_flight_call(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    ok, error = session.activate()
    assert (ok, error) == (True, None)
    assert session._ai_tick_lock.acquire(blocking=False)
    try:
        with pytest.raises(RuntimeError, match="single in-flight"):
            session.analyze_tick()
    finally:
        session._ai_tick_lock.release()
    assert session._ai_state_lock.acquire(blocking=False)
    try:
        assert session.analyze_tick() is None
    finally:
        session._ai_state_lock.release()
    session.close()


def test_ai_worker_single_in_flight_and_preview_continues(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)
    monkeypatch.setattr(websocket_api, "FPS_LOG_INTERVAL", 1000)

    in_flight = {"count": 0, "max": 0}
    original = websocket_api.VisionSession.analyze_tick

    def slow_analyze(self):
        in_flight["count"] += 1
        in_flight["max"] = max(in_flight["max"], in_flight["count"])
        time.sleep(0.18)
        try:
            return original(self)
        finally:
            in_flight["count"] -= 1

    monkeypatch.setattr(websocket_api.VisionSession, "analyze_tick", slow_analyze)

    evaluate_calls = {"n": 0}
    real_evaluate = websocket_api.evaluate_movement

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        return real_evaluate(*args, **kwargs)

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    async def _run():
        sent: list[str] = []

        async def fake_send(text):
            sent.append(text)

        ws = MagicMock()
        session_ref: dict = {"session": None}
        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=True,
                send_text=fake_send,
            )
        )

        deadline = time.monotonic() + 3.0
        preview_n = 0
        feedback_n = 0
        while time.monotonic() < deadline:
            preview_n = sum(
                1
                for payload in sent
                if _decode(payload).get("message_type") == "preview_frame"
            )
            feedback_n = sum(
                1
                for payload in sent
                if _decode(payload).get("message_type") == "feedback"
            )
            if (
                preview_n >= 3
                and feedback_n >= 1
                and evaluate_calls["n"] >= 1
            ):
                break
            await asyncio.sleep(0.02)

        await websocket_api._stop_session_task(task)
        preview_n = sum(
            1
            for payload in sent
            if _decode(payload).get("message_type") == "preview_frame"
        )
        feedback_n = sum(
            1
            for payload in sent
            if _decode(payload).get("message_type") == "feedback"
        )
        sequences = [
            _decode(payload).get("capture_sequence")
            for payload in sent
            if _decode(payload).get("message_type") == "preview_frame"
        ]
        assert in_flight["max"] == 1
        assert preview_n >= 3
        assert preview_n > evaluate_calls["n"]
        assert evaluate_calls["n"] >= 1
        assert feedback_n >= 1
        assert sequences == sorted(sequences)
        assert len(set(sequences)) == len(sequences)

    asyncio.run(_run())


def test_serialized_websocket_sends_never_overlap(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)
    monkeypatch.setattr(websocket_api, "FPS_LOG_INTERVAL", 1000)

    original = websocket_api.VisionSession.analyze_tick

    def slow_analyze(self):
        time.sleep(0.05)
        return original(self)

    monkeypatch.setattr(websocket_api.VisionSession, "analyze_tick", slow_analyze)

    in_send = {"n": 0, "max": 0}

    async def _run():
        async def fake_send(_text):
            in_send["n"] += 1
            in_send["max"] = max(in_send["max"], in_send["n"])
            await asyncio.sleep(0.03)
            in_send["n"] -= 1

        ws = MagicMock()
        session_ref: dict = {"session": None, "mailbox": None}
        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=True,
                send_text=fake_send,
            )
        )
        for _ in range(80):
            mailbox = session_ref.get("mailbox")
            if mailbox is not None and mailbox.max_sends_in_flight >= 1:
                break
            await asyncio.sleep(0.02)

        mailbox = session_ref.get("mailbox")
        await websocket_api._stop_session_task(task)
        assert in_send["max"] == 1
        assert mailbox is not None
        assert mailbox.max_sends_in_flight == 1

    asyncio.run(_run())


def test_stop_cancels_preview_and_ai_without_task_leak(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)
    monkeypatch.setattr(websocket_api, "TARGET_FPS", 50)

    async def _run():
        before = {id(task) for task in asyncio.all_tasks()}

        async def fake_send(_text):
            return None

        ws = MagicMock()
        session_ref: dict = {"session": None}
        task = asyncio.create_task(
            websocket_api._cv_session_loop(
                ws,
                "Hand Stall",
                session_ref=session_ref,
                start_active=True,
                send_text=fake_send,
            )
        )
        for _ in range(50):
            if session_ref.get("session") is not None:
                break
            await asyncio.sleep(0.01)

        await websocket_api._stop_session_task(task)
        await asyncio.sleep(0)
        leftover = [
            t
            for t in asyncio.all_tasks()
            if id(t) not in before and t is not asyncio.current_task()
        ]
        assert leftover == []
        assert StubCamera.instances[-1].released is True
        assert session_ref.get("session") is None

    asyncio.run(_run())


def test_active_analysis_without_preview_jpeg_still_scores_once(monkeypatch):
    _patch_vision(monkeypatch)
    record_calls = {"n": 0}
    real_record = RubricTracker.record

    def tracking_record(self, *args, **kwargs):
        record_calls["n"] += 1
        return real_record(self, *args, **kwargs)

    monkeypatch.setattr(RubricTracker, "record", tracking_record)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    ok, error = session.activate()
    assert (ok, error) == (True, None)
    message = session.process_frame(emit_preview_jpeg=False)
    assert message is not None
    assert message.frame_jpeg_base64 is None
    assert message.message_type == "feedback"
    assert message.session_state == "active"
    assert record_calls["n"] == 1
    session.close()
