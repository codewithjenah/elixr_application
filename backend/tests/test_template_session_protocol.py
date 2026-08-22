"""Phase 7C: template/live_test prepare path and Wrist Stall session runtime.

Official MOVEMENT_CONFIG / _RULES stay the dispatch identity for official
sessions. Template sessions dispatch by AssessmentSpec.template_id only.
"""

from __future__ import annotations

import asyncio
import json
from types import SimpleNamespace
import numpy as np
import pytest
from pydantic import ValidationError

from api import websocket as websocket_api
from assessment.hold_validator import HoldValidator
from assessment.readiness import (
    ReadinessObservation,
    ReadinessTracker,
    readiness_needs_hands,
    readiness_needs_pose,
    template_readiness_profile,
)
from assessment.rule_engine import _RULES
from assessment.rules import coming_soon
from assessment.scoring import RubricTracker
from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.capability import (
    capability_for,
    template_max_hands,
    template_prop_type,
    template_requires_hands,
    template_requires_pose,
)
from assessment.specs.wrist_v1 import evaluate as evaluate_wrist_v1
from config import MOVEMENT_CONFIG
from schemas.commands import PrepareCommand, StartCommand, parse_v1_command
from vision.types import BottleDetection, Point2D, PoseLandmarks


_LEFT_WRIST = 15
_RIGHT_WRIST = 16


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
        self.last_captured_at_monotonic = None
        self.last_capture_sequence = None
        StubCamera.instances.append(self)

    def open(self) -> bool:
        StubCamera.open_calls += 1
        return StubCamera.open_result

    def read(self):
        self.read_count += 1
        self.last_captured_at_monotonic = 1000.0 + self.read_count
        self.last_capture_sequence = self.read_count
        return _frame()

    def release(self) -> None:
        self.released = True


class StubBottleDetector:
    detections: list[BottleDetection] = []

    def __init__(self, *, enabled: bool):
        self.enabled = enabled
        self.detect_calls = 0

    def ensure_ready(self):
        pass

    def detect(self, current_frame):
        self.detect_calls += 1
        return list(StubBottleDetector.detections)


class StubHandsDetector:
    instances: list["StubHandsDetector"] = []

    def __init__(self, **kwargs):
        self.detect_calls = 0
        self.max_num_hands = kwargs.get("max_num_hands", 2)
        self.closed = False
        StubHandsDetector.instances.append(self)

    def detect(self, current_frame, bottle=None):
        self.detect_calls += 1
        return None

    def close(self):
        self.closed = True


class StubPoseDetector:
    landmarks: PoseLandmarks | None = None
    instances: list["StubPoseDetector"] = []

    def __init__(self, **kwargs):
        self.detect_calls = 0
        self.closed = False
        StubPoseDetector.instances.append(self)

    def detect(self, current_frame):
        self.detect_calls += 1
        return StubPoseDetector.landmarks

    def close(self):
        self.closed = True


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


def _patch_vision(monkeypatch):
    StubCamera.open_calls = 0
    StubCamera.open_result = True
    StubCamera.instances = []
    StubBottleDetector.detections = []
    StubHandsDetector.instances = []
    StubPoseDetector.instances = []
    StubPoseDetector.landmarks = None
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
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)


def _golden_spec(*, laterality: str = "either") -> dict:
    return {
        "schema_version": 1,
        "template_id": "balance_stall.wrist_v1",
        "prop": "bottle",
        "target": "wrist",
        "laterality": laterality,
    }


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


def _template_prepare_payload(**overrides):
    payload = _prepare_payload(
        movement="Template Assessment",
        difficulty="Standard",
        session_purpose="template_scored",
        assessment_spec=_golden_spec(),
    )
    payload.update(overrides)
    return payload


def _validated_spec(*, laterality: str = "either") -> AssessmentSpec:
    return AssessmentSpec.model_validate(_golden_spec(laterality=laterality))


def _upright_bottle() -> BottleDetection:
    return BottleDetection(x1=160, y1=200, x2=200, y2=280, confidence=0.9)


def _pose_wrists(*, left: bool = True, right: bool = True) -> PoseLandmarks:
    points: dict[int, Point2D] = {}
    visibility: dict[int, float] = {}
    if left:
        points[_LEFT_WRIST] = Point2D(0.30, 0.60)
        visibility[_LEFT_WRIST] = 0.9
    if right:
        points[_RIGHT_WRIST] = Point2D(0.70, 0.60)
        visibility[_RIGHT_WRIST] = 0.9
    return PoseLandmarks(points=points, visibility=visibility)


def _pose_ready() -> PoseLandmarks:
    return PoseLandmarks(
        points={
            11: Point2D(0.35, 0.30),
            12: Point2D(0.65, 0.30),
            13: Point2D(0.32, 0.45),
            14: Point2D(0.68, 0.45),
            _LEFT_WRIST: Point2D(0.30, 0.60),
            _RIGHT_WRIST: Point2D(0.70, 0.60),
        },
        visibility={
            11: 0.9,
            12: 0.9,
            13: 0.9,
            14: 0.9,
            _LEFT_WRIST: 0.9,
            _RIGHT_WRIST: 0.9,
        },
    )


def _advance_ready(tracker: ReadinessTracker, obs: ReadinessObservation, clock: list[float]):
    snapshot = None
    for _ in range(8):
        snapshot = tracker.update(obs)
        clock[0] += 0.25
    assert snapshot is not None
    return snapshot


def _template_session(
    *,
    purpose: str = "template_scored",
    laterality: str = "either",
    movement: str = "Template Assessment",
) -> websocket_api.VisionSession:
    return websocket_api.VisionSession(
        movement,
        prop_type="bottle",
        session_purpose=purpose,
        assessment_spec=_validated_spec(laterality=laterality),
    )


# ---------------------------------------------------------------------------
# Official 12 remains closed
# ---------------------------------------------------------------------------


def test_wrist_stall_absent_from_official_registries():
    assert "Wrist Stall" not in MOVEMENT_CONFIG
    assert "balance_stall.wrist_v1" not in MOVEMENT_CONFIG
    assert "Wrist Stall" not in _RULES
    assert "balance_stall.wrist_v1" not in _RULES


# ---------------------------------------------------------------------------
# Command schema
# ---------------------------------------------------------------------------


def test_legacy_official_prepare_unchanged():
    cmd = parse_v1_command(_prepare_payload())
    assert isinstance(cmd, PrepareCommand)
    assert cmd.session_purpose == "official"
    assert cmd.assessment_spec is None
    assert cmd.movement == "Normal Grip"
    assert cmd.difficulty == "Easy"
    assert cmd.allow_submission_recording is False


def test_official_prepare_without_session_purpose_accepted():
    payload = _prepare_payload()
    assert "session_purpose" not in payload
    cmd = PrepareCommand.model_validate(payload)
    assert cmd.session_purpose == "official"
    assert cmd.assessment_spec is None


def test_official_plus_assessment_spec_rejected():
    with pytest.raises(ValidationError) as exc:
        PrepareCommand.model_validate(
            _prepare_payload(assessment_spec=_golden_spec())
        )
    assert "unexpected_assessment_spec" in str(exc.value)


def test_template_scored_plus_valid_spec_accepted():
    cmd = PrepareCommand.model_validate(_template_prepare_payload())
    assert cmd.session_purpose == "template_scored"
    assert isinstance(cmd.assessment_spec, AssessmentSpec)
    assert cmd.assessment_spec.template_id == "balance_stall.wrist_v1"


def test_live_test_plus_valid_spec_accepted():
    cmd = PrepareCommand.model_validate(
        _template_prepare_payload(session_purpose="live_test")
    )
    assert cmd.session_purpose == "live_test"
    assert isinstance(cmd.assessment_spec, AssessmentSpec)


def test_template_missing_spec_rejected():
    payload = _template_prepare_payload()
    payload.pop("assessment_spec")
    with pytest.raises(ValidationError) as exc:
        PrepareCommand.model_validate(payload)
    assert "missing_assessment_spec" in str(exc.value)


def test_live_test_missing_spec_rejected():
    payload = _template_prepare_payload(session_purpose="live_test")
    payload.pop("assessment_spec")
    with pytest.raises(ValidationError) as exc:
        PrepareCommand.model_validate(payload)
    assert "missing_assessment_spec" in str(exc.value)


def test_threshold_and_extra_nested_key_rejected():
    extra = _golden_spec()
    extra["thresholds"] = {"proximity": 0.1}
    with pytest.raises(ValidationError):
        PrepareCommand.model_validate(_template_prepare_payload(assessment_spec=extra))

    extra = _golden_spec()
    extra["eval"] = "print(1)"
    with pytest.raises(ValidationError):
        PrepareCommand.model_validate(_template_prepare_payload(assessment_spec=extra))


def test_unknown_template_rejected():
    spec = _golden_spec()
    spec["template_id"] = "balance_stall.elbow_v1"
    with pytest.raises(ValidationError):
        PrepareCommand.model_validate(_template_prepare_payload(assessment_spec=spec))


def test_shaker_and_conflicting_prop_rejected():
    with pytest.raises(ValidationError) as exc:
        PrepareCommand.model_validate(_template_prepare_payload(prop_type="shaker"))
    assert "assessment_spec_prop_mismatch" in str(exc.value)

    with pytest.raises(ValidationError) as exc:
        PrepareCommand.model_validate(
            _template_prepare_payload(prop_type="bottle_and_shaker")
        )
    assert "assessment_spec_prop_mismatch" in str(exc.value)


def test_template_recording_true_rejected():
    with pytest.raises(ValidationError) as exc:
        PrepareCommand.model_validate(
            _template_prepare_payload(allow_submission_recording=True)
        )
    assert "template_submission_recording_not_allowed" in str(exc.value)

    with pytest.raises(ValidationError) as exc:
        PrepareCommand.model_validate(
            _template_prepare_payload(
                session_purpose="live_test",
                allow_submission_recording=True,
            )
        )
    assert "template_submission_recording_not_allowed" in str(exc.value)


def test_legacy_start_command_cannot_carry_template_fields():
    start_payload = _prepare_payload(action="start")
    start_payload["session_purpose"] = "template_scored"
    start_payload["assessment_spec"] = _golden_spec()
    with pytest.raises(ValidationError):
        StartCommand.model_validate(start_payload)

    with pytest.raises(ValidationError):
        parse_v1_command(start_payload)


def test_raw_dict_is_revalidated_as_assessment_spec():
    cmd = PrepareCommand.model_validate(_template_prepare_payload())
    assert type(cmd.assessment_spec) is AssessmentSpec
    assert cmd.assessment_spec.model_extra is None or cmd.assessment_spec.model_extra == {}


# ---------------------------------------------------------------------------
# WebSocket prepare acknowledgments
# ---------------------------------------------------------------------------


def test_official_prepare_still_validates_movement(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_prepare_payload(movement="Wrist Stall", difficulty="Easy"))
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "invalid_movement"
        assert StubCamera.open_calls == 0
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_official_prepare_without_purpose_is_accepted_on_wire(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_prepare_payload())
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is True
        assert ack["session_state"] == "preparing"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_template_purpose_skips_official_movement_validation(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            _template_prepare_payload(
                movement="Teacher Wrist Title",
                difficulty="Custom",
            )
        )
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is True
        assert ack["error_code"] is None
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_template_teacher_title_is_not_evaluator_identity(monkeypatch):
    _patch_vision(monkeypatch)
    official_calls: list[str] = []

    def tracking_official(movement, *args, **kwargs):
        official_calls.append(movement)
        raise AssertionError("official evaluate_movement must not run for templates")

    coming_calls = {"n": 0}

    def tracking_coming(*args, **kwargs):
        coming_calls["n"] += 1
        raise AssertionError("coming_soon must not run for templates")

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_official)
    monkeypatch.setattr(coming_soon, "evaluate", tracking_coming)

    session = _template_session(movement="Teacher Wrist Title")
    session.start()
    session.activate()
    StubBottleDetector.detections = [_upright_bottle()]
    StubPoseDetector.landmarks = _pose_ready()
    message = session.process_frame()
    assert message is not None
    assert official_calls == []
    assert coming_calls["n"] == 0
    session.close()


def test_official_plus_spec_rejected_on_wire(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_prepare_payload(assessment_spec=_golden_spec()))
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "unexpected_assessment_spec"
        assert StubCamera.open_calls == 0
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_template_missing_spec_rejected_on_wire(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        payload = _template_prepare_payload()
        payload.pop("assessment_spec")
        await ws.push(payload)
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "missing_assessment_spec"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_live_test_missing_spec_rejected_on_wire(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        payload = _template_prepare_payload(session_purpose="live_test")
        payload.pop("assessment_spec")
        await ws.push(payload)
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "missing_assessment_spec"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_unknown_template_rejected_on_wire(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        spec = _golden_spec()
        spec["template_id"] = "unknown.template"
        await ws.push(_template_prepare_payload(assessment_spec=spec))
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "unsupported_assessment_spec"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_template_recording_rejected_on_wire(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(_template_prepare_payload(allow_submission_recording=True))
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "template_submission_recording_not_allowed"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


def test_legacy_start_cannot_activate_template_session(monkeypatch):
    _patch_vision(monkeypatch)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))
        await ws.push(
            _prepare_payload(
                action="start",
                movement="Template Assessment",
                difficulty="Standard",
            )
        )
        ack = await _wait_for_ack(ws, "req-1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "invalid_movement"
        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


# ---------------------------------------------------------------------------
# Detector / capability contract
# ---------------------------------------------------------------------------


def test_template_requires_bottle_pose_not_hands():
    spec = _validated_spec()
    assert capability_for(spec).value == "supported"
    assert template_prop_type(spec) == "bottle"
    assert template_requires_pose(spec) is True
    assert template_requires_hands(spec) is False
    assert template_max_hands(spec) == 0


def test_template_session_constructs_pose_not_hands(monkeypatch):
    _patch_vision(monkeypatch)
    session = _template_session()
    session.start()
    assert session._pose_needed is True
    assert session._hands_needed is False
    assert session._hands_max == 0
    assert session._prop_detection_only is False

    session.begin_readiness()
    assert session.pose_detector is not None
    assert session.hands_detector is None
    assert readiness_needs_hands("Wrist Stall") is False
    session.close()
    assert session.pose_detector is None
    assert session.hands_detector is None


# ---------------------------------------------------------------------------
# Readiness laterality
# ---------------------------------------------------------------------------


def _wrist_obs(
    *,
    bottle: bool = True,
    pose: PoseLandmarks | None = None,
) -> ReadinessObservation:
    return ReadinessObservation(
        has_camera_frame=True,
        bottles=[_upright_bottle()] if bottle else [],
        pose=pose,
    )


def test_template_readiness_either_accepts_usable_wrist():
    profile = template_readiness_profile(_validated_spec(laterality="either"))
    clock = [0.0]
    tracker = ReadinessTracker(
        "Template Assessment",
        profile=profile,
        pass_frames=2,
        fail_frames=2,
        stable_duration_s=0.5,
        monotonic=lambda: clock[0],
    )
    left_only = _advance_ready(tracker, _wrist_obs(pose=_pose_wrists(right=False)), clock)
    assert left_only.readiness_stable is True

    clock = [0.0]
    tracker = ReadinessTracker(
        "Template Assessment",
        profile=profile,
        pass_frames=2,
        fail_frames=2,
        stable_duration_s=0.5,
        monotonic=lambda: clock[0],
    )
    right_only = _advance_ready(tracker, _wrist_obs(pose=_pose_wrists(left=False)), clock)
    assert right_only.readiness_stable is True


def test_template_readiness_left_requires_left_wrist():
    profile = template_readiness_profile(_validated_spec(laterality="left"))
    clock = [0.0]
    tracker = ReadinessTracker(
        "Template Assessment",
        profile=profile,
        pass_frames=2,
        fail_frames=2,
        stable_duration_s=0.5,
        monotonic=lambda: clock[0],
    )
    missing = tracker.update(_wrist_obs(pose=_pose_wrists(left=False)))
    codes = {item.code: item.status for item in missing.items}
    assert codes["wrist_visible"] == "waiting"
    assert missing.readiness_stable is False

    clock[0] = 0.0
    tracker.reset()
    ready = _advance_ready(tracker, _wrist_obs(pose=_pose_wrists(right=False)), clock)
    assert ready.readiness_stable is True


def test_template_readiness_right_requires_right_wrist():
    profile = template_readiness_profile(_validated_spec(laterality="right"))
    clock = [0.0]
    tracker = ReadinessTracker(
        "Template Assessment",
        profile=profile,
        pass_frames=2,
        fail_frames=2,
        stable_duration_s=0.5,
        monotonic=lambda: clock[0],
    )
    missing = tracker.update(_wrist_obs(pose=_pose_wrists(right=False)))
    codes = {item.code: item.status for item in missing.items}
    assert codes["wrist_visible"] == "waiting"

    clock[0] = 0.0
    tracker.reset()
    ready = _advance_ready(tracker, _wrist_obs(pose=_pose_wrists(left=False)), clock)
    assert ready.readiness_stable is True


def test_missing_selected_wrist_blocks_readiness():
    profile = template_readiness_profile(_validated_spec(laterality="left"))
    clock = [0.0]
    tracker = ReadinessTracker(
        "Template Assessment",
        profile=profile,
        pass_frames=1,
        fail_frames=1,
        stable_duration_s=0.0,
        monotonic=lambda: clock[0],
    )
    snapshot = tracker.update(_wrist_obs(pose=_pose_wrists(left=False)))
    assert snapshot.readiness_complete is False
    assert snapshot.readiness_stable is False


def test_missing_bottle_or_pose_blocks_template_readiness():
    profile = template_readiness_profile(_validated_spec())
    clock = [0.0]
    tracker = ReadinessTracker(
        "Template Assessment",
        profile=profile,
        pass_frames=1,
        fail_frames=1,
        stable_duration_s=0.0,
        monotonic=lambda: clock[0],
    )
    no_bottle = tracker.update(_wrist_obs(bottle=False, pose=_pose_wrists()))
    assert no_bottle.readiness_complete is False
    tracker.reset()
    no_pose = tracker.update(_wrist_obs(pose=None))
    assert no_pose.readiness_complete is False


def test_template_readiness_uses_stable_duration_not_frame_counts_only():
    profile = template_readiness_profile(_validated_spec())
    clock = [10.0]
    tracker = ReadinessTracker(
        "Template Assessment",
        profile=profile,
        pass_frames=1,
        fail_frames=1,
        stable_duration_s=1.0,
        monotonic=lambda: clock[0],
    )
    obs = _wrist_obs(pose=_pose_wrists())
    first = tracker.update(obs)
    assert first.readiness_complete is True
    assert first.readiness_stable is False
    clock[0] += 1.0
    second = tracker.update(obs)
    assert second.readiness_stable is True


def test_official_readiness_profiles_unchanged():
    assert readiness_needs_hands("Hand Stall") is True
    assert readiness_needs_pose("Hand Stall") is False
    assert readiness_needs_hands("Shoulder Stall") is False
    assert readiness_needs_pose("Shoulder Stall") is True
    assert "Wrist Stall" not in MOVEMENT_CONFIG


# ---------------------------------------------------------------------------
# Active evaluator dispatch
# ---------------------------------------------------------------------------


def test_active_template_dispatch_calls_wrist_v1(monkeypatch):
    _patch_vision(monkeypatch)
    calls = {"n": 0, "specs": []}
    real = evaluate_wrist_v1

    def tracking(spec, bottle, pose, movement_state=None):
        calls["n"] += 1
        calls["specs"].append(spec)
        return real(spec, bottle, pose, movement_state)

    monkeypatch.setattr(websocket_api, "evaluate_wrist_v1", tracking)
    official = {"n": 0}

    def tracking_official(*args, **kwargs):
        official["n"] += 1
        raise AssertionError("official evaluate_movement must not run")

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_official)

    session = _template_session()
    session.start()
    session.activate()
    StubBottleDetector.detections = [_upright_bottle()]
    StubPoseDetector.landmarks = _pose_ready()
    message = session.process_frame()
    assert message is not None
    assert calls["n"] == 1
    assert isinstance(calls["specs"][0], AssessmentSpec)
    assert official["n"] == 0
    session.close()


def test_unsupported_template_never_falls_into_coming_soon(monkeypatch):
    coming_calls = {"n": 0}

    def boom(*args, **kwargs):
        coming_calls["n"] += 1
        raise AssertionError("coming_soon must not run")

    monkeypatch.setattr(coming_soon, "evaluate", boom)
    monkeypatch.setattr("assessment.rules.coming_soon.evaluate", boom)

    foreign = SimpleNamespace(
        schema_version=1,
        template_id="balance_stall.elbow_v1",
        prop="bottle",
        target="wrist",
        laterality="either",
    )
    with pytest.raises(ValueError):
        evaluate_wrist_v1(foreign, _upright_bottle(), _pose_wrists(), None)

    with pytest.raises((ValueError, TypeError, ValidationError)):
        websocket_api.VisionSession(
            "Template Assessment",
            session_purpose="template_scored",
            assessment_spec={"template_id": "balance_stall.elbow_v1"},
        )
    assert coming_calls["n"] == 0


def test_hold_validator_and_rubric_receive_wrist_result(monkeypatch):
    _patch_vision(monkeypatch)
    hold_calls: list[dict] = []
    rubric_calls: list[dict] = []
    real_hold = HoldValidator.update
    real_record = RubricTracker.record

    def tracking_hold(self, **kwargs):
        hold_calls.append(kwargs)
        return real_hold(self, **kwargs)

    def tracking_record(self, **kwargs):
        rubric_calls.append(kwargs)
        return real_record(self, **kwargs)

    monkeypatch.setattr(HoldValidator, "update", tracking_hold)
    monkeypatch.setattr(RubricTracker, "record", tracking_record)

    session = _template_session()
    session.start()
    session.activate()
    StubBottleDetector.detections = [_upright_bottle()]
    StubPoseDetector.landmarks = _pose_ready()
    message = session.process_frame()
    assert message is not None
    assert hold_calls
    assert rubric_calls
    assert rubric_calls[0]["criterion_results"] is not None or (
        rubric_calls[0].get("posture_status") in {"unknown", "unstable", "stable"}
    )
    assert message.assessment is not None
    assert message.assessment.version == 2
    session.close()


def test_calibration_scale_is_stamped_into_template_state(monkeypatch):
    _patch_vision(monkeypatch)
    seen_scales: list[float] = []
    real = evaluate_wrist_v1

    def tracking(spec, bottle, pose, movement_state=None):
        if movement_state is not None:
            seen_scales.append(float(movement_state.get("calibration_scale", 1.0)))
        return real(spec, bottle, pose, movement_state)

    monkeypatch.setattr(websocket_api, "evaluate_wrist_v1", tracking)

    session = _template_session()
    session.start()
    session._calibration.scale = 0.8
    session._calibration.source = "shoulders"
    session._calibration.locked = True
    session.activate()
    StubBottleDetector.detections = [_upright_bottle()]
    StubPoseDetector.landmarks = _pose_ready()
    session.process_frame()
    assert seen_scales
    assert seen_scales[0] == pytest.approx(0.8)
    assert session._movement_state["calibration_scale"] == pytest.approx(0.8)
    session.close()


def test_stop_clears_template_session_state(monkeypatch):
    _patch_vision(monkeypatch)
    session = _template_session()
    session.start()
    session.begin_readiness()
    assert session._session_profile.is_template
    session.close()
    assert session.lifecycle == websocket_api.SESSION_CLOSED
    assert session._readiness_tracker is None
    assert session._movement_state is None
    assert session.pose_detector is None
    assert session.hands_detector is None
    assert StubCamera.instances[0].released is True


def test_new_official_session_does_not_inherit_wrist_state(monkeypatch):
    _patch_vision(monkeypatch)
    template = _template_session()
    template.start()
    template.activate()
    template._movement_state = {"calibration_scale": 0.5, "wrist": True}
    template.close()

    official = websocket_api.VisionSession("Hand Stall")
    official.start()
    assert official._session_profile.is_template is False
    assert official._session_profile.assessment_spec is None
    assert official._movement_state is None
    assert official._pose_needed is False
    assert official._hands_needed is True
    official.close()


def test_template_session_does_not_persist(monkeypatch):
    _patch_vision(monkeypatch)
    session = _template_session(purpose="live_test")
    assert not hasattr(session, "assignment_attempt_id")
    assert not hasattr(session, "teacher_uid")
    dumped = session.__dict__
    assert "firestore" not in dumped
    assert "assignment_attempt" not in dumped
    session.close()


def test_evaluator_rejects_non_assessment_spec_instances():
    with pytest.raises(ValueError):
        evaluate_wrist_v1(
            {"schema_version": 1, "template_id": "balance_stall.wrist_v1"},
            _upright_bottle(),
            _pose_wrists(),
            None,
        )
