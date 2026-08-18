"""VisionSession must construct and run only the readiness landmark modality."""

from __future__ import annotations

import pytest

from api import websocket as websocket_api
from test_readiness_requirements import EXPECTED_READINESS_DETECTORS
from test_session_lifecycle import (
    StubHandsDetector,
    StubPoseDetector,
    _patch_vision,
)


def _timing_log(session: websocket_api.VisionSession) -> str:
    return session.timings.format_averages_ms(frame_budget_ms=33.3)


@pytest.mark.parametrize(
    "movement,expect_hands,expect_pose",
    [
        (name, hands, pose)
        for name, (hands, pose) in EXPECTED_READINESS_DETECTORS.items()
    ],
)
def test_readiness_session_uses_only_required_detectors(
    monkeypatch, movement: str, expect_hands: bool, expect_pose: bool
):
    _patch_vision(monkeypatch)

    hands_inits = {"n": 0}
    pose_inits = {"n": 0}
    annotated = {"hands": "unset", "pose": "unset"}

    class TrackingHands(StubHandsDetector):
        def __init__(self, **kwargs):
            hands_inits["n"] += 1
            super().__init__(**kwargs)

    class TrackingPose(StubPoseDetector):
        def __init__(self, **kwargs):
            pose_inits["n"] += 1
            super().__init__(**kwargs)

    def capture_annotate(frame, bottles, hands, *args, pose=None, **kwargs):
        annotated["hands"] = hands
        annotated["pose"] = pose
        return frame

    monkeypatch.setattr(websocket_api, "HandsDetector", TrackingHands)
    monkeypatch.setattr(websocket_api, "PoseDetector", TrackingPose)
    monkeypatch.setattr(websocket_api, "annotate_frame", capture_annotate)

    session = websocket_api.VisionSession(movement)
    session.start()
    assert session.begin_readiness() is True

    expected_max = {
        "Normal Grip": 1,
        "Bartender's Grip": 1,
        "Reverse Grip": 1,
        "Claw Grip": 1,
        "Hand Stall": 1,
        "One Finger Stall": 1,
        "Double Hand Stall": 2,
        "Bottle in a tin": 1,
    }

    if expect_hands:
        assert session.hands_detector is not None, movement
        assert hands_inits["n"] == 1, movement
        assert session.hands_detector.max_num_hands == expected_max[movement], movement
    else:
        assert session.hands_detector is None, movement
        assert hands_inits["n"] == 0, movement

    if expect_pose:
        assert session.pose_detector is not None, movement
        assert pose_inits["n"] == 1, movement
    else:
        assert session.pose_detector is None, movement
        assert pose_inits["n"] == 0, movement

    assert not (
        session.hands_detector is not None and session.pose_detector is not None
    ), movement

    msg = session.process_readiness_frame()
    assert msg is not None
    assert msg.session_state == "readying"

    if expect_hands:
        assert session.hands_detector.detect_calls >= 1, movement
        assert "hands=" in _timing_log(session), movement
    else:
        assert hands_inits["n"] == 0, movement
        assert annotated["hands"] is None, movement
        assert "hands=" not in _timing_log(session), movement

    if expect_pose:
        assert session.pose_detector.detect_calls >= 1, movement
        assert "pose=" in _timing_log(session), movement
    else:
        assert pose_inits["n"] == 0, movement
        assert annotated["pose"] is None, movement
        assert "pose=" not in _timing_log(session), movement

    session.close()
