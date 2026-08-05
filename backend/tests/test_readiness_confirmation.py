"""Authoritative readiness confirmation and upper-body observability tests."""

from __future__ import annotations

import asyncio

import pytest

from api import websocket as websocket_api
from assessment.readiness import (
    ReadinessObservation,
    ReadinessSnapshot,
    ReadinessTracker,
    requirements_for,
)
from schemas.commands import ConfirmReadinessCommand, parse_v1_command
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D, PoseLandmarks

from test_session_lifecycle import (
    StubCamera,
    StubHandsDetector,
    StubPoseDetector,
    _activate_after_readiness,
    _activate_prepared,
    _confirm_session_readiness,
    _patch_vision,
    _stable_readiness_snapshot,
)
from test_ws_protocol import FakeWebSocket, _prepare_payload, _wait_for_ack


def _confirm_readiness_payload(**overrides):
    payload = {
        "protocol_version": 1,
        "request_id": "req-cr1",
        "session_id": "session-1",
        "action": "confirm_readiness",
    }
    payload.update(overrides)
    return payload


def _bottle() -> BottleDetection:
    return BottleDetection(x1=200, y1=100, x2=280, y2=300, confidence=0.9)


def _hand() -> HandLandmarks:
    return HandLandmarks(
        points={0: Point2D(0.5, 0.5), 9: Point2D(0.5, 0.48)},
        handedness="Right",
    )


def _pose_upper_body(*, left_only: bool = False, low_visibility: bool = False) -> PoseLandmarks:
    vis = 0.2 if low_visibility else 1.0
    points = {
        11: Point2D(0.35, 0.3),
        12: Point2D(0.65, 0.3),
        13: Point2D(0.4, 0.4),
        15: Point2D(0.45, 0.55),
    }
    visibility = {11: vis, 12: vis, 13: vis, 15: vis}
    if not left_only:
        points.update({14: Point2D(0.6, 0.4), 16: Point2D(0.65, 0.55)})
        visibility.update({14: vis, 16: vis})
    return PoseLandmarks(points=points, visibility=visibility)


def _pose_shoulders_only() -> PoseLandmarks:
    return PoseLandmarks(
        points={11: Point2D(0.35, 0.3), 12: Point2D(0.65, 0.3)},
        visibility={11: 1.0, 12: 1.0},
    )


def test_valid_confirm_readiness_command_parses():
    cmd = parse_v1_command(_confirm_readiness_payload())
    assert isinstance(cmd, ConfirmReadinessCommand)
    assert cmd.action == "confirm_readiness"


def test_confirm_readiness_before_stable_rejected(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "release_shared_camera", lambda: None)

    async def _run():
        ws = FakeWebSocket()
        task = asyncio.create_task(websocket_api.websocket_endpoint(ws))

        await ws.push(_prepare_payload(movement="Hand Stall", difficulty="Medium"))
        await _wait_for_ack(ws, "req-1")()
        await ws.push({"protocol_version": 1, "request_id": "req-r1", "session_id": "session-1", "action": "begin_readiness"})
        await _wait_for_ack(ws, "req-r1")()

        await ws.push(_confirm_readiness_payload())
        ack = await _wait_for_ack(ws, "req-cr1")()
        assert ack["accepted"] is False
        assert ack["error_code"] == "readiness_not_stable"
        assert ack["session_state"] == "readying"

        await ws.close_client()
        await asyncio.wait_for(task, timeout=2)

    asyncio.run(_run())


class TestVisionSessionConfirmation:
    def test_confirm_after_stable_snapshot(self, monkeypatch):
        _patch_vision(monkeypatch)
        session = websocket_api.VisionSession("Hand Stall")
        session.start()
        session.begin_readiness()
        session._latest_readiness_snapshot = _stable_readiness_snapshot()
        ok, err = session.confirm_readiness()
        assert (ok, err) == (True, None)
        assert session.readiness_confirmed is True
        session.close()

    def test_confirm_before_stable_rejected(self, monkeypatch):
        _patch_vision(monkeypatch)
        session = websocket_api.VisionSession("Hand Stall")
        session.start()
        session.begin_readiness()
        ok, err = session.confirm_readiness()
        assert ok is False
        assert err == "readiness_not_stable"
        session.close()

    def test_duplicate_confirm_is_idempotent(self, monkeypatch):
        _patch_vision(monkeypatch)
        session = websocket_api.VisionSession("Hand Stall")
        session.start()
        session.begin_readiness()
        session._latest_readiness_snapshot = _stable_readiness_snapshot()
        assert session.confirm_readiness() == (True, None)
        assert session.confirm_readiness() == (True, None)
        session.close()

    def test_activate_from_readying_without_confirmation_rejected(self, monkeypatch):
        _patch_vision(monkeypatch)
        session = websocket_api.VisionSession("Hand Stall")
        session.start()
        session.begin_readiness()
        ok, err = session.activate()
        assert ok is False
        assert err == "readiness_not_confirmed"
        session.close()

    def test_activate_after_confirmation_succeeds(self, monkeypatch):
        _patch_vision(monkeypatch)
        session = websocket_api.VisionSession("Hand Stall")
        session.start()
        session.begin_readiness()
        _activate_after_readiness(session)
        assert session.is_active
        session.close()

    def test_detection_loss_after_confirmation_does_not_revoke(self, monkeypatch):
        _patch_vision(monkeypatch)
        session = websocket_api.VisionSession("Hand Stall")
        session.start()
        session.begin_readiness()
        session._latest_readiness_snapshot = _stable_readiness_snapshot()
        session.confirm_readiness()
        msg = session.process_readiness_frame()
        assert msg is not None
        assert msg.readiness_stable is True
        assert session.readiness_confirmed is True
        session.close()

    def test_new_prepare_resets_confirmation(self, monkeypatch):
        _patch_vision(monkeypatch)
        session = websocket_api.VisionSession("Hand Stall")
        session.start()
        session.begin_readiness()
        _confirm_session_readiness(session)
        session.close()

        session2 = websocket_api.VisionSession("Hand Stall")
        session2.start()
        session2.begin_readiness()
        assert session2.readiness_confirmed is False
        session2.close()

    def test_stop_resets_confirmation(self, monkeypatch):
        _patch_vision(monkeypatch)
        session = websocket_api.VisionSession("Hand Stall")
        session.start()
        session.begin_readiness()
        _confirm_session_readiness(session)
        session.close()
        assert session.readiness_confirmed is False

    def test_prepared_to_active_without_readiness_still_works(self, monkeypatch):
        _patch_vision(monkeypatch)
        session = websocket_api.VisionSession("Free Practice")
        session.start()
        _activate_prepared(session)
        assert session.is_active
        session.close()


class TestUpperBodyReadiness:
    POSE_MOVEMENTS = (
        "Forearm Stall",
        "Elbow Stall",
        "Reverse Forearm Stall",
        "Shoulder Stall",
    )

    @pytest.mark.parametrize("movement", POSE_MOVEMENTS)
    def test_pose_movements_include_upper_body_visible(self, movement: str):
        codes = [c for c, _, _ in requirements_for(movement)]
        assert "upper_body_visible" in codes

    def test_one_shoulder_alone_fails(self):
        tracker = ReadinessTracker(
            "Shoulder Stall", pass_frames=1, fail_frames=1, stable_duration_s=0.1
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            pose=PoseLandmarks(
                points={11: Point2D(0.35, 0.3)},
                visibility={11: 1.0},
            ),
        )
        snap = tracker.update(obs)
        upper = next(i for i in snap.items if i.code == "upper_body_visible")
        assert upper.status == "waiting"

    def test_shoulders_without_arm_chain_fail(self):
        tracker = ReadinessTracker(
            "Shoulder Stall", pass_frames=1, fail_frames=1, stable_duration_s=0.1
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            pose=_pose_shoulders_only(),
        )
        snap = tracker.update(obs)
        upper = next(i for i in snap.items if i.code == "upper_body_visible")
        assert upper.status == "waiting"

    def test_both_shoulders_and_arm_chain_pass(self):
        tracker = ReadinessTracker(
            "Shoulder Stall", pass_frames=1, fail_frames=1, stable_duration_s=0.1
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            pose=_pose_upper_body(),
        )
        snap = tracker.update(obs)
        upper = next(i for i in snap.items if i.code == "upper_body_visible")
        assert upper.status == "ready"

    def test_hand_without_pose_fails_forearm_readiness(self):
        tracker = ReadinessTracker(
            "Forearm Stall", pass_frames=1, fail_frames=1, stable_duration_s=0.1
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            hands=HandsResult(hands=[_hand()]),
            pose=None,
        )
        snap = tracker.update(obs)
        upper = next(i for i in snap.items if i.code == "upper_body_visible")
        assert upper.status == "waiting"

    def test_hand_without_pose_fails_elbow_readiness(self):
        tracker = ReadinessTracker(
            "Elbow Stall", pass_frames=1, fail_frames=1, stable_duration_s=0.1
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            hands=HandsResult(hands=[_hand()]),
            pose=None,
        )
        snap = tracker.update(obs)
        upper = next(i for i in snap.items if i.code == "upper_body_visible")
        assert upper.status == "waiting"

    def test_low_visibility_pose_fails(self):
        tracker = ReadinessTracker(
            "Forearm Stall", pass_frames=1, fail_frames=1, stable_duration_s=0.1
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            pose=_pose_upper_body(low_visibility=True),
        )
        snap = tracker.update(obs)
        upper = next(i for i in snap.items if i.code == "upper_body_visible")
        assert upper.status == "waiting"

    def test_wrong_arm_technique_still_passes_when_landmarks_observable(self):
        tracker = ReadinessTracker(
            "Forearm Stall", pass_frames=1, fail_frames=1, stable_duration_s=0.1
        )
        obs = ReadinessObservation(
            has_camera_frame=True,
            bottles=[_bottle()],
            pose=_pose_upper_body(),
        )
        for _ in range(tracker.pass_frames):
            snap = tracker.update(obs)
        upper = next(i for i in snap.items if i.code == "upper_body_visible")
        assert upper.status == "ready"


def test_readiness_does_not_call_evaluate_or_hold(monkeypatch):
    _patch_vision(monkeypatch)
    evaluate_calls = {"n": 0}
    hold_calls = {"n": 0}

    def tracking_evaluate(*args, **kwargs):
        evaluate_calls["n"] += 1
        raise AssertionError("evaluate_movement must not run during readiness")

    class TrackingHold:
        def activate(self):
            hold_calls["n"] += 1

        def update(self, **kwargs):
            hold_calls["n"] += 1
            raise AssertionError("hold must not run during readiness")

        def reset(self):
            pass

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)
    session = websocket_api.VisionSession("Forearm Stall")
    session._hold_validator = TrackingHold()
    session.start()
    session.begin_readiness()
    session.process_readiness_frame()
    assert evaluate_calls["n"] == 0
    assert hold_calls["n"] == 0
    session.close()
