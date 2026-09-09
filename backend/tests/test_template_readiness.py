"""Wrist Stall template readiness must run PoseDetector, not HandsDetector."""

from __future__ import annotations

from assessment.readiness import (
    ReadinessObservation,
    ReadinessTracker,
    template_readiness_profile,
)
from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.capability import template_requires_hands, template_requires_pose
from assessment.specs.session_profile import build_session_profile
from api import websocket as websocket_api
from test_session_lifecycle import StubHandsDetector, StubPoseDetector, _patch_vision
from vision.types import Point2D, PoseLandmarks, PropDetection


def _spec(laterality: str = "left") -> dict:
    return {
        "schema_version": 1,
        "template_id": "balance_stall.wrist_v1",
        "prop": "bottle",
        "target": "wrist",
        "laterality": laterality,
    }


def _pose(*, left: bool = False, right: bool = False) -> PoseLandmarks:
    points: dict[int, Point2D] = {}
    visibility: dict[int, float] = {}
    if left:
        points[15] = Point2D(0.45, 0.55)
        visibility[15] = 1.0
    if right:
        points[16] = Point2D(0.65, 0.55)
        visibility[16] = 1.0
    return PoseLandmarks(points=points, visibility=visibility)


def _item(snapshot, code: str):
    return next(i for i in snapshot.items if i.code == code)


class _BottleReturningDetector:
    def __init__(self, *, enabled: bool):
        self.enabled = enabled
        self.detect_calls = 0

    def ensure_ready(self):
        pass

    def detect(self, current_frame):
        self.detect_calls += 1
        return [
            PropDetection(x1=20, y1=20, x2=60, y2=100, confidence=0.92),
        ]


class _ReturningPose(StubPoseDetector):
    def __init__(self, pose: PoseLandmarks | None, **kwargs):
        super().__init__(**kwargs)
        self._pose = pose

    def detect(self, current_frame):
        self.detect_calls += 1
        return self._pose


def _template_session(
    monkeypatch,
    *,
    laterality: str = "left",
    pose: PoseLandmarks | None = None,
    purpose: str = "live_test",
):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "BottleDetector", _BottleReturningDetector)
    monkeypatch.setattr(websocket_api, "HandsDetector", StubHandsDetector)
    monkeypatch.setattr(
        websocket_api,
        "PoseDetector",
        lambda **kwargs: _ReturningPose(pose, **kwargs),
    )
    annotated = {"pose": "unset", "hands": "unset"}

    def capture_annotate(frame, bottles, hands, *args, pose=None, **kwargs):
        annotated["pose"] = pose
        annotated["hands"] = hands
        return frame

    monkeypatch.setattr(websocket_api, "annotate_frame", capture_annotate)
    session = websocket_api.VisionSession(
        "Wrist Stall",
        session_purpose=purpose,
        assessment_spec=_spec(laterality),
    )
    session.start()
    assert session.begin_readiness() is True
    return session, annotated


def test_wrist_stall_template_requires_pose_not_hands():
    spec = AssessmentSpec.model_validate(_spec("left"))
    assert template_requires_pose(spec) is True
    assert template_requires_hands(spec) is False

    profile = build_session_profile(
        purpose="live_test",
        movement="Wrist Stall",
        prop_type="bottle",
        assessment_spec=spec,
    )
    assert profile.requires_pose is True
    assert profile.requires_hands is False
    assert profile.max_hands == 0
    assert profile.readiness_profile is not None
    assert profile.readiness_profile.needs_pose() is True
    assert profile.readiness_profile.needs_hands() is False
    assert profile.readiness_profile.codes() == (
        "camera_frame",
        "bottle_detected",
        "pose_visible",
        "wrist_visible",
    )


def test_template_readiness_creates_pose_detector_not_hands(monkeypatch):
    session, _ = _template_session(monkeypatch, pose=_pose(left=True))
    assert session.pose_detector is not None
    assert session.hands_detector is None
    session.close()


def test_valid_template_pose_reaches_readiness_and_annotate(monkeypatch):
    pose = _pose(left=True)
    session, annotated = _template_session(monkeypatch, laterality="left", pose=pose)
    assert session._readiness_tracker is not None
    session._readiness_tracker.pass_frames = 1
    session._readiness_tracker.fail_frames = 1

    before = session.pose_detector.detect_calls
    msg = session.process_readiness_frame()
    assert msg is not None
    assert session.pose_detector.detect_calls == before + 1
    assert annotated["pose"] is pose
    assert annotated["hands"] is None

    items = {item.code: item.status for item in (msg.readiness_items or [])}
    assert items["pose_visible"] == "ready"
    assert items["wrist_visible"] == "ready"
    session.close()


def test_valid_right_wrist_is_selected_for_right_laterality(monkeypatch):
    pose = _pose(right=True)
    session, annotated = _template_session(
        monkeypatch, laterality="right", pose=pose, purpose="template_scored"
    )
    session._readiness_tracker.pass_frames = 1
    session._readiness_tracker.fail_frames = 1
    msg = session.process_readiness_frame()
    assert msg is not None
    items = {item.code: item.status for item in (msg.readiness_items or [])}
    assert items["pose_visible"] == "ready"
    assert items["wrist_visible"] == "ready"
    assert annotated["pose"] is pose
    session.close()


def test_wrong_wrist_does_not_pass_selected_laterality():
    tracker = ReadinessTracker(
        "Template Assessment",
        "bottle",
        profile=template_readiness_profile(AssessmentSpec.model_validate(_spec("left"))),
        pass_frames=1,
        fail_frames=1,
        stable_duration_s=0.1,
    )
    obs = ReadinessObservation(
        has_camera_frame=True,
        bottles=[PropDetection(x1=20, y1=20, x2=60, y2=100, confidence=0.9)],
        pose=_pose(right=True),
    )
    snap = tracker.update(obs)
    assert _item(snap, "pose_visible").status == "ready"
    assert _item(snap, "wrist_visible").status == "waiting"
    assert snap.readiness_complete is False


def test_missing_template_pose_stays_waiting_and_cannot_complete(monkeypatch):
    session, annotated = _template_session(monkeypatch, pose=None)
    session._readiness_tracker.pass_frames = 1
    session._readiness_tracker.fail_frames = 1
    msg = session.process_readiness_frame()
    assert msg is not None
    assert session.pose_detector.detect_calls >= 1
    assert annotated["pose"] is None
    items = {item.code: item.status for item in (msg.readiness_items or [])}
    assert items["pose_visible"] == "waiting"
    assert items["wrist_visible"] == "waiting"
    assert msg.readiness_complete is not True
    session.close()
