"""Protocol version 1 WebSocket command parsing and lifecycle acknowledgments."""

from __future__ import annotations

import asyncio
import json

import numpy as np
import pytest
from pydantic import ValidationError

from api import websocket as websocket_api
from assessment.rule_engine import validate_movement_difficulty, validate_movement_name
from schemas.commands import (
    ActivateCommand,
    PrepareCommand,
    StartCommand,
    StopCommand,
    parse_v1_command,
)
from schemas.protocol import CommandAck, ProtocolError


def _frame(h: int = 48, w: int = 64) -> np.ndarray:
    frame = np.full((h, w, 3), 120, dtype=np.uint8)
    frame[10:20, 10:20] = 200
    return frame


class StubCamera:
    open_calls = 0
    open_result = True
    instances: list["StubCamera"] = []

    def __init__(self, *args, **kwargs):
        self.read_count = 0
        self.released = False
        self.active_index = kwargs.get("camera_index") or 0
        self.active_device_id = kwargs.get("camera_device_id")
        self.used_fallback = False
        StubCamera.instances.append(self)

    def open(self) -> bool:
        StubCamera.open_calls += 1
        return StubCamera.open_result

    def read(self):
        self.read_count += 1
        return _frame()

    def release(self) -> None:
        self.released = True


class StubBottleDetector:
    def __init__(self, *, enabled: bool):
        self.enabled = enabled

    def ensure_ready(self):
        pass

    def detect(self, current_frame):
        return []


class StubHandsDetector:
    def __init__(self, **kwargs):
        pass

    def detect(self, current_frame, bottle=None):
        return None

    def close(self):
        pass


class StubPoseDetector:
    def __init__(self, **kwargs):
        pass

    def detect(self, current_frame):
        return None

    def close(self):
        pass


def _patch_vision(monkeypatch):
    StubCamera.open_calls = 0
    StubCamera.open_result = True
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
    monkeypatch.setattr(websocket_api, "CAMERA_REOPEN_DELAY_S", 0)


def _prepare_payload(**overrides):
    payload = {
        "protocol_version": 1,
        "request_id": "req-1",
        "session_id": "session-1",
        "action": "prepare",
        "movement": "Normal Grip",
        "difficulty": "Easy",
        "bottle_detection_enabled": True,
        "camera_device_id": None,
    }
    payload.update(overrides)
    return payload


def test_valid_prepare_command_parses():
    cmd = parse_v1_command(_prepare_payload())
    assert isinstance(cmd, PrepareCommand)
    assert cmd.movement == "Normal Grip"
    assert cmd.bottle_detection_enabled is True
    assert cmd.prop_type == "bottle"


@pytest.mark.parametrize("prop_type", ["bottle", "shaker"])
def test_prepare_and_start_accept_supported_props(prop_type):
    prepare = parse_v1_command(_prepare_payload(prop_type=prop_type))
    start = parse_v1_command(
        _prepare_payload(
            action="start",
            prop_type=prop_type,
            request_id="req-start",
        )
    )

    assert isinstance(prepare, PrepareCommand)
    assert isinstance(start, StartCommand)
    assert prepare.prop_type == prop_type
    assert start.prop_type == prop_type


def test_missing_prop_defaults_to_bottle():
    payload = _prepare_payload()
    payload.pop("prop_type", None)

    command = parse_v1_command(payload)

    assert isinstance(command, PrepareCommand)
    assert command.prop_type == "bottle"


def test_unknown_prop_is_rejected_with_structured_ack(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_prepare_payload(prop_type="cup"))
        ack = await _wait_for_ack(ws, "req-1")()

        assert ack["accepted"] is False
        assert ack["error_code"] == "invalid_prop_type"
        assert "bottle" in ack["message"]
        assert StubCamera.open_calls == 0

        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_valid_activate_and_stop_parse():
    activate = parse_v1_command(
        {
            "protocol_version": 1,
            "request_id": "req-a",
            "session_id": "session-a",
            "action": "activate",
        }
    )
    stop = parse_v1_command(
        {
            "protocol_version": 1,
            "request_id": "req-s",
            "session_id": "session-a",
            "action": "stop",
        }
    )
    assert isinstance(activate, ActivateCommand)
    assert isinstance(stop, StopCommand)


@pytest.mark.parametrize("value", [True, False])
def test_strict_boolean_accepts_bool(value):
    cmd = PrepareCommand.model_validate(
        _prepare_payload(bottle_detection_enabled=value)
    )
    assert cmd.bottle_detection_enabled is value


@pytest.mark.parametrize("value", ["true", "false", 1, 0])
def test_strict_boolean_rejects_coercions(value):
    with pytest.raises(ValidationError):
        PrepareCommand.model_validate(
            _prepare_payload(bottle_detection_enabled=value)
        )


def test_missing_protocol_fields_rejected():
    with pytest.raises(ValidationError):
        PrepareCommand.model_validate(
            {
                "protocol_version": 1,
                "action": "prepare",
                "movement": "Normal Grip",
                "difficulty": "Easy",
            }
        )


def test_unsupported_protocol_version_rejected():
    with pytest.raises(ValidationError):
        PrepareCommand.model_validate(_prepare_payload(protocol_version=2))


def test_unknown_movement_helper_rejects_coming_soon_route():
    assert validate_movement_name("Not A Real Move") == "invalid_movement"
    difficulty, error = validate_movement_difficulty("Normal Grip", "Hard")
    assert error == "difficulty_mismatch"
    assert difficulty == "Easy"


def test_one_finger_stall_registry_accepts_medium_only():
    assert validate_movement_name("One Finger Stall") is None

    difficulty, error = validate_movement_difficulty(
        "One Finger Stall",
        "Medium",
    )
    assert (difficulty, error) == ("Medium", None)

    difficulty, error = validate_movement_difficulty(
        "One Finger Stall",
        "Easy",
    )
    assert (difficulty, error) == ("Medium", "difficulty_mismatch")


def test_dual_camera_selection_rejected():
    with pytest.raises(ValidationError):
        PrepareCommand.model_validate(
            _prepare_payload(camera_device_id="dev-a", camera_index=1)
        )


class FakeWebSocket:
    def __init__(self):
        self.accepted = False
        self.sent: list[str] = []
        self._incoming: asyncio.Queue = asyncio.Queue()

    async def accept(self):
        self.accepted = True

    async def send_text(self, text: str):
        self.sent.append(text)

    async def receive_text(self) -> str:
        item = await self._incoming.get()
        if item is None:
            from fastapi import WebSocketDisconnect

            raise WebSocketDisconnect()
        return item

    async def push(self, payload: dict | str):
        if isinstance(payload, dict):
            await self._incoming.put(json.dumps(payload))
        else:
            await self._incoming.put(payload)

    async def close_client(self):
        await self._incoming.put(None)


def _decode_sent(ws: FakeWebSocket) -> list[dict]:
    return [json.loads(item) for item in ws.sent]


def _wait_for_ack(ws: FakeWebSocket, request_id: str, timeout: float = 2.0):
    async def _run():
        deadline = asyncio.get_event_loop().time() + timeout
        while asyncio.get_event_loop().time() < deadline:
            for message in _decode_sent(ws):
                if (
                    message.get("message_type") == "command_ack"
                    and message.get("request_id") == request_id
                ):
                    return message
            await asyncio.sleep(0.01)
        raise AssertionError(f"Timed out waiting for ack {request_id}")

    return _run


def test_malformed_json_protocol_error_keeps_socket_usable(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push("{not-json")
        await asyncio.sleep(0.05)

        messages = _decode_sent(ws)
        assert messages
        assert messages[0]["message_type"] == "protocol_error"
        assert messages[0]["error_code"] == "invalid_json"

        await ws.push(
            _prepare_payload(request_id="req-after", session_id="session-after")
        )
        ack = await _wait_for_ack(ws, "req-after")()
        assert ack["accepted"] is True

        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_unknown_action_structured_rejection(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            {
                "protocol_version": 1,
                "request_id": "req-u",
                "session_id": "session-u",
                "action": "explode",
            }
        )
        ack = await _wait_for_ack(ws, "req-u")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "unknown_action"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_unknown_movement_rejected(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            _prepare_payload(movement="Coming Soon Move", difficulty="Easy")
        )
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "invalid_movement"
        assert StubCamera.open_calls == 0
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_difficulty_mismatch_rejected(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_prepare_payload(movement="Normal Grip", difficulty="Hard"))
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "difficulty_mismatch"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_prepare_ack_after_camera_ready(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_prepare_payload())
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is True
        assert ack["session_state"] == "preparing"
        assert StubCamera.open_calls == 1
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_failed_prepare_never_succeeds(monkeypatch):
    _patch_vision(monkeypatch)
    StubCamera.open_result = False
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_prepare_payload())
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] in {
            "camera_unavailable",
            "selected_camera_unavailable",
        }
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_activate_ack_and_stale_session(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))

        await ws.push(
            _prepare_payload(session_id="session-live", request_id="req-p")
        )
        await _wait_for_ack(ws, "req-p")()

        await ws.push(
            {
                "protocol_version": 1,
                "request_id": "req-stale",
                "session_id": "session-old",
                "action": "activate",
            }
        )
        stale = await _wait_for_ack(ws, "req-stale")()
        assert stale["accepted"] is False
        assert stale["error_code"] == "session_id_mismatch"

        await ws.push(
            {
                "protocol_version": 1,
                "request_id": "req-ok",
                "session_id": "session-live",
                "action": "activate",
            }
        )
        ok = await _wait_for_ack(ws, "req-ok")()
        assert ok["accepted"] is True
        assert ok["session_state"] == "active"

        await ws.push(
            {
                "protocol_version": 1,
                "request_id": "req-again",
                "session_id": "session-live",
                "action": "activate",
            }
        )
        again = await _wait_for_ack(ws, "req-again")()
        assert again["accepted"] is True

        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_stale_stop_does_not_stop_newer_session(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))

        await ws.push(
            _prepare_payload(session_id="session-new", request_id="req-p")
        )
        await _wait_for_ack(ws, "req-p")()
        assert StubCamera.open_calls == 1

        await ws.push(
            {
                "protocol_version": 1,
                "request_id": "req-stale-stop",
                "session_id": "session-old",
                "action": "stop",
            }
        )
        stale = await _wait_for_ack(ws, "req-stale-stop")()
        assert stale["accepted"] is False
        assert stale["error_code"] == "session_id_mismatch"
        assert StubCamera.instances[-1].released is False

        await ws.push(
            {
                "protocol_version": 1,
                "request_id": "req-stop",
                "session_id": "session-new",
                "action": "stop",
            }
        )
        stop = await _wait_for_ack(ws, "req-stop")()
        assert stop["accepted"] is True
        assert stop["session_state"] == "idle"

        await ws.push(
            {
                "protocol_version": 1,
                "request_id": "req-stop-2",
                "session_id": "session-new",
                "action": "stop",
            }
        )
        stop2 = await _wait_for_ack(ws, "req-stop-2")()
        assert stop2["accepted"] is True

        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_v1_feedback_includes_session_id(monkeypatch):
    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession(
        "Hand Stall",
        session_id="session-feedback",
    )
    assert session.start() is True
    message = session.process_preview_frame()
    assert message is not None
    assert message.session_id == "session-feedback"
    assert message.message_type == "feedback"
    assert message.protocol_version == 1
    session.close()


def test_legacy_start_still_compatible(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            {
                "action": "start",
                "movement": "Hand Stall",
                "difficulty": "Medium",
                "bottle_detection_enabled": True,
                "camera_device_id": None,
            }
        )
        deadline = asyncio.get_event_loop().time() + 2
        while asyncio.get_event_loop().time() < deadline:
            if StubCamera.open_calls == 1:
                break
            await asyncio.sleep(0.01)
        assert StubCamera.open_calls == 1
        assert not any(
            m.get("message_type") == "command_ack" for m in _decode_sent(ws)
        )
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_disconnect_releases_resources(monkeypatch):
    _patch_vision(monkeypatch)
    released = {"n": 0}
    monkeypatch.setattr(
        websocket_api,
        "release_shared_camera",
        lambda: released.__setitem__("n", released["n"] + 1),
    )

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            _prepare_payload(session_id="session-d", request_id="req-d")
        )
        await _wait_for_ack(ws, "req-d")()
        assert StubCamera.open_calls == 1
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)
        assert released["n"] == 1
        assert StubCamera.instances[-1].released is True

    asyncio.run(_run())


def test_command_ack_schema_roundtrip():
    ack = CommandAck(
        request_id="req-1",
        session_id="session-1",
        action="activate",
        accepted=True,
        session_state="active",
    )
    dumped = json.loads(ack.model_dump_json())
    assert dumped["message_type"] == "command_ack"
    assert dumped["protocol_version"] == 1


def test_protocol_error_schema_roundtrip():
    err = ProtocolError(
        error_code="invalid_json",
        message="The WebSocket message is not valid JSON.",
    )
    dumped = json.loads(err.model_dump_json())
    assert dumped["message_type"] == "protocol_error"
    assert dumped["request_id"] is None


def test_activate_before_prepare_rejected(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            {
                "protocol_version": 1,
                "request_id": "req-a",
                "session_id": "session-a",
                "action": "activate",
            }
        )
        ack = await _wait_for_ack(ws, "req-a")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "session_not_prepared"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())
