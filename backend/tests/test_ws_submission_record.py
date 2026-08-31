"""Protocol v1 submission-record commands. No physical webcam."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path

import numpy as np
import pytest

from api import websocket as websocket_api
from schemas.commands import (
    CancelSubmissionRecordCommand,
    StartSubmissionRecordCommand,
    StopSubmissionRecordCommand,
    parse_v1_command,
)
from test_ws_protocol import (
    FakeWebSocket,
    _patch_vision,
    _prepare_payload,
    _wait_for_ack,
)


def _record_payload(action: str, **overrides):
    payload = {
        "protocol_version": 1,
        "action": action,
        "request_id": "req-rec",
        "session_id": "session-1",
    }
    payload.update(overrides)
    return payload


def test_submission_record_commands_parse():
    start = parse_v1_command(_record_payload("start_submission_record"))
    stop = parse_v1_command(_record_payload("stop_submission_record"))
    cancel = parse_v1_command(_record_payload("cancel_submission_record"))
    assert isinstance(start, StartSubmissionRecordCommand)
    assert isinstance(stop, StopSubmissionRecordCommand)
    assert isinstance(cancel, CancelSubmissionRecordCommand)


def test_submission_record_commands_forbid_extra_fields():
    with pytest.raises(Exception):
        parse_v1_command(
            _record_payload("start_submission_record", video_base64="nope")
        )


class _FakeWriter:
    def __init__(self, path: Path):
        self.path = path
        path.write_bytes(b"")
        self.released = False

    def isOpened(self) -> bool:
        return True

    def write(self, frame: np.ndarray) -> bool:
        with self.path.open("ab") as handle:
            handle.write(b"frame")
        return True

    def release(self) -> None:
        self.released = True


def _install_fake_writer(monkeypatch, tmp_path: Path):
    from vision.submission_recorder import SubmissionRecorder as RealRecorder

    def factory(path: Path, fps: float, size: tuple[int, int]) -> _FakeWriter:
        return _FakeWriter(path)

    class PatchedRecorder(RealRecorder):
        def __init__(self, *args, **kwargs):
            kwargs.setdefault("writer_factory", factory)
            kwargs.setdefault("temp_root", tmp_path)
            super().__init__(*args, **kwargs)

    monkeypatch.setattr(websocket_api, "SubmissionRecorder", PatchedRecorder)
    monkeypatch.setattr(
        "vision.submission_recorder.submission_temp_dir",
        lambda root=None: tmp_path,
    )


async def _wait_for_written_clip(tmp_path: Path, *, timeout: float = 2.0) -> Path:
    deadline = asyncio.get_event_loop().time() + timeout
    while True:
        clips = [
            path
            for path in tmp_path.glob("clip_*.mp4")
            if path.exists() and path.stat().st_size > 0
        ]
        if clips:
            return clips[0]
        if asyncio.get_event_loop().time() >= deadline:
            raise AssertionError("Submission recorder did not receive camera frames")
        await asyncio.sleep(0.02)


def _assignment_prepare(**overrides):
    payload = _prepare_payload(
        movement="Free Practice",
        difficulty="Easy",
        allow_submission_recording=True,
        **overrides,
    )
    return payload


def test_start_stop_ack_has_path_not_bytes(monkeypatch, tmp_path: Path):
    _patch_vision(monkeypatch)
    _install_fake_writer(monkeypatch, tmp_path)
    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_assignment_prepare(request_id="req-p", session_id="session-1"))
        prepare_ack = await _wait_for_ack(ws, "req-p")()
        assert prepare_ack["accepted"] is True

        await ws.push(_record_payload("start_submission_record", request_id="req-s"))
        start_ack = await _wait_for_ack(ws, "req-s")()
        assert start_ack["accepted"] is True
        assert start_ack.get("local_file_path") in (None, "")

        await _wait_for_written_clip(tmp_path)
        await ws.push(_record_payload("stop_submission_record", request_id="req-t"))
        stop_ack = await _wait_for_ack(ws, "req-t", timeout=4.0)()
        assert stop_ack["accepted"] is True
        assert isinstance(stop_ack.get("local_file_path"), str)
        assert "clip_" in Path(stop_ack["local_file_path"]).name
        assert stop_ack["content_type"] == "video/mp4"
        assert stop_ack["video_duration_ms"] >= 0
        assert stop_ack["video_size_bytes"] >= 0
        dumped = json.dumps(stop_ack)
        assert "frame_jpeg_base64" not in dumped
        assert "video_base64" not in dumped
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_start_without_assignment_context_rejected(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_prepare_payload(request_id="req-p", session_id="session-1"))
        await _wait_for_ack(ws, "req-p")()
        await ws.push(_record_payload("start_submission_record", request_id="req-s"))
        ack = await _wait_for_ack(ws, "req-s")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "submission_recording_not_allowed"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_stop_without_start_rejected(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            _assignment_prepare(request_id="req-p", session_id="session-1")
        )
        await _wait_for_ack(ws, "req-p")()
        await ws.push(_record_payload("stop_submission_record", request_id="req-t"))
        ack = await _wait_for_ack(ws, "req-t")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "submission_not_recording"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_duplicate_start_rejected(monkeypatch, tmp_path: Path):
    _patch_vision(monkeypatch)
    _install_fake_writer(monkeypatch, tmp_path)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            _assignment_prepare(request_id="req-p", session_id="session-1")
        )
        await _wait_for_ack(ws, "req-p")()
        await ws.push(_record_payload("start_submission_record", request_id="req-s1"))
        first = await _wait_for_ack(ws, "req-s1")()
        assert first["accepted"] is True
        await ws.push(_record_payload("start_submission_record", request_id="req-s2"))
        second = await _wait_for_ack(ws, "req-s2")()
        assert second["accepted"] is False
        assert second["error_code"] == "submission_already_recording"
        await ws.push(_record_payload("cancel_submission_record", request_id="req-c"))
        await _wait_for_ack(ws, "req-c")()
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_cancel_deletes_temp_and_is_idempotent(monkeypatch, tmp_path: Path):
    _patch_vision(monkeypatch)
    _install_fake_writer(monkeypatch, tmp_path)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            _assignment_prepare(request_id="req-p", session_id="session-1")
        )
        await _wait_for_ack(ws, "req-p")()
        await ws.push(_record_payload("start_submission_record", request_id="req-s"))
        await _wait_for_ack(ws, "req-s")()
        await _wait_for_written_clip(tmp_path)
        await ws.push(_record_payload("stop_submission_record", request_id="req-t"))
        stop_ack = await _wait_for_ack(ws, "req-t", timeout=4.0)()
        clip = Path(stop_ack["local_file_path"])
        assert clip.exists()
        await ws.push(_record_payload("cancel_submission_record", request_id="req-c1"))
        first = await _wait_for_ack(ws, "req-c1")()
        assert first["accepted"] is True
        assert clip.exists() is False
        await ws.push(_record_payload("cancel_submission_record", request_id="req-c2"))
        second = await _wait_for_ack(ws, "req-c2")()
        assert second["accepted"] is True
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_disconnect_cleans_temp_file(monkeypatch, tmp_path: Path):
    _patch_vision(monkeypatch)
    _install_fake_writer(monkeypatch, tmp_path)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            _assignment_prepare(request_id="req-p", session_id="session-1")
        )
        await _wait_for_ack(ws, "req-p")()
        await ws.push(_record_payload("start_submission_record", request_id="req-s"))
        await _wait_for_ack(ws, "req-s")()
        before = [await _wait_for_written_clip(tmp_path)]
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)
        after = [path for path in before if path.exists()]
        assert after == []

    asyncio.run(_run())
