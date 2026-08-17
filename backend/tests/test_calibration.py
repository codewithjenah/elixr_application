"""Per-session proximity calibration from shoulder width or palm length."""

from __future__ import annotations

import pytest

from assessment.calibration import (
    CalibrationTracker,
    compute_calibration_scale,
    scaled_proximity,
)
from assessment.rule_engine import evaluate_movement
from assessment.rules.common_checks import (
    check_hand_bottle_proximity,
    check_stall_proximity,
    track_bottle_stability,
)
from config import (
    ARM_STALL_PROXIMITY,
    CALIBRATION_REFERENCE_PALM_LENGTH,
    CALIBRATION_REFERENCE_SHOULDER_WIDTH,
    CALIBRATION_SCALE_MAX,
    CALIBRATION_SCALE_MIN,
    HAND_BOTTLE_PROXIMITY,
    STALL_STABILITY_THRESHOLD,
)
from vision.types import (
    BottleDetection,
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
)


def _pose_shoulders(
    left: Point2D = Point2D(0.35, 0.3),
    right: Point2D = Point2D(0.65, 0.3),
    *,
    visibility: float = 1.0,
) -> PoseLandmarks:
    return PoseLandmarks(
        points={11: left, 12: right},
        visibility={11: visibility, 12: visibility},
    )


def _hands_palm(
    wrist: Point2D = Point2D(0.5, 0.54),
    middle_mcp: Point2D = Point2D(0.5, 0.50),
) -> HandsResult:
    return HandsResult(
        hands=[HandLandmarks(points={0: wrist, 9: middle_mcp}, handedness="Right")]
    )


def _bottle(cx: int = 320, cy: int = 240) -> BottleDetection:
    return BottleDetection(x1=cx - 20, y1=cy - 40, x2=cx + 20, y2=cy + 40, confidence=0.9)


def _bottle_at(point: Point2D) -> BottleDetection:
    return _bottle(cx=int(round(point.x * 640)), cy=int(round(point.y * 480)))


def _arm_pose() -> PoseLandmarks:
    return PoseLandmarks(
        points={13: Point2D(0.40, 0.40), 15: Point2D(0.40, 0.70)},
        visibility={13: 0.9, 15: 0.9},
    )


def test_reference_shoulder_width_matches_readiness_upper_body_fixture():
    """Readiness _pose_upper_body places shoulders at x=0.35 and x=0.65."""
    left = Point2D(0.35, 0.3)
    right = Point2D(0.65, 0.3)
    observed = ((right.x - left.x) ** 2 + (right.y - left.y) ** 2) ** 0.5
    assert observed == pytest.approx(CALIBRATION_REFERENCE_SHOULDER_WIDTH)
    assert CALIBRATION_REFERENCE_SHOULDER_WIDTH == pytest.approx(0.30)


def test_reference_palm_length_matches_readiness_hand_fixture():
    """Readiness _hand() places wrist at cy+0.04 and middle MCP at cy."""
    wrist = Point2D(0.5, 0.54)
    mcp = Point2D(0.5, 0.50)
    observed = ((mcp.x - wrist.x) ** 2 + (mcp.y - wrist.y) ** 2) ** 0.5
    assert observed == pytest.approx(CALIBRATION_REFERENCE_PALM_LENGTH)
    assert CALIBRATION_REFERENCE_PALM_LENGTH == pytest.approx(0.04)


def test_shoulders_visible_scales_from_shoulder_width():
    pose = _pose_shoulders(Point2D(0.25, 0.3), Point2D(0.70, 0.3))
    scale, source = compute_calibration_scale(pose, _hands_palm())
    assert source == "shoulders"
    assert scale == pytest.approx(0.45 / 0.30)
    assert CALIBRATION_SCALE_MIN < scale < CALIBRATION_SCALE_MAX


def test_shoulders_absent_falls_back_to_palm_length():
    hands = _hands_palm(Point2D(0.5, 0.56), Point2D(0.5, 0.50))
    scale, source = compute_calibration_scale(None, hands)
    assert source == "palm_fallback"
    expected = 0.06 / CALIBRATION_REFERENCE_PALM_LENGTH
    assert scale == pytest.approx(expected)
    assert scale != pytest.approx(1.0)
    assert CALIBRATION_SCALE_MIN < scale < CALIBRATION_SCALE_MAX


def test_low_visibility_shoulders_fall_back_to_palm():
    pose = _pose_shoulders(visibility=0.2)
    hands = _hands_palm(Point2D(0.5, 0.56), Point2D(0.5, 0.50))
    scale, source = compute_calibration_scale(pose, hands)
    assert source == "palm_fallback"
    assert scale == pytest.approx(0.06 / CALIBRATION_REFERENCE_PALM_LENGTH)


def test_neither_visible_defaults_to_identity():
    scale, source = compute_calibration_scale(None, None)
    assert source == "default"
    assert scale == pytest.approx(1.0)

    empty_pose = PoseLandmarks(points={}, visibility={})
    empty_hands = HandsResult(hands=[])
    scale, source = compute_calibration_scale(empty_pose, empty_hands)
    assert (scale, source) == (pytest.approx(1.0), "default")


def test_clamp_bounds_hold_for_shoulders_and_palm():
    huge_shoulders = _pose_shoulders(Point2D(0.0, 0.3), Point2D(1.0, 0.3))
    scale, source = compute_calibration_scale(huge_shoulders, None)
    assert source == "shoulders"
    assert scale == pytest.approx(CALIBRATION_SCALE_MAX)

    tiny_shoulders = _pose_shoulders(Point2D(0.49, 0.3), Point2D(0.51, 0.3))
    scale, source = compute_calibration_scale(tiny_shoulders, None)
    assert source == "shoulders"
    assert scale == pytest.approx(CALIBRATION_SCALE_MIN)

    huge_palm = _hands_palm(Point2D(0.5, 0.90), Point2D(0.5, 0.10))
    scale, source = compute_calibration_scale(None, huge_palm)
    assert source == "palm_fallback"
    assert scale == pytest.approx(CALIBRATION_SCALE_MAX)

    tiny_palm = _hands_palm(Point2D(0.5, 0.500), Point2D(0.5, 0.501))
    scale, source = compute_calibration_scale(None, tiny_palm)
    assert source == "palm_fallback"
    assert scale == pytest.approx(CALIBRATION_SCALE_MIN)


def test_tracker_does_not_let_fallback_overwrite_shoulders():
    tracker = CalibrationTracker()
    tracker.sample(_pose_shoulders(), None)
    assert tracker.source == "shoulders"
    shoulder_scale = tracker.scale

    tracker.sample(None, _hands_palm(Point2D(0.5, 0.90), Point2D(0.5, 0.10)))
    assert tracker.source == "shoulders"
    assert tracker.scale == pytest.approx(shoulder_scale)


def test_tracker_upgrades_palm_fallback_to_shoulders():
    tracker = CalibrationTracker()
    tracker.sample(None, _hands_palm(Point2D(0.5, 0.58), Point2D(0.5, 0.50)))
    assert tracker.source == "palm_fallback"

    tracker.sample(_pose_shoulders(), None)
    assert tracker.source == "shoulders"
    assert tracker.scale == pytest.approx(1.0)


def test_tracker_lock_defaults_when_never_sampled():
    tracker = CalibrationTracker()
    scale, source = tracker.lock()
    assert (scale, source) == (1.0, "default")
    assert tracker.locked is True

    tracker.sample(_pose_shoulders(Point2D(0.0, 0.3), Point2D(1.0, 0.3)), None)
    assert tracker.scale == pytest.approx(1.0)
    assert tracker.source == "default"


def test_tracker_reset_clears_locked_sample():
    tracker = CalibrationTracker()
    tracker.sample(_pose_shoulders(), None)
    tracker.lock()
    tracker.reset()
    assert tracker.scale is None
    assert tracker.source is None
    assert tracker.locked is False


def test_scaled_proximity_multiplies_and_clamps_state_scale():
    assert scaled_proximity(0.15, None) == pytest.approx(0.15)
    assert scaled_proximity(0.15, {}) == pytest.approx(0.15)
    assert scaled_proximity(0.15, {"calibration_scale": 1.0}) == pytest.approx(0.15)
    assert scaled_proximity(0.15, {"calibration_scale": 0.6}) == pytest.approx(0.09)
    assert scaled_proximity(0.15, {"calibration_scale": 1.6}) == pytest.approx(0.24)
    assert scaled_proximity(0.15, {"calibration_scale": 0.1}) == pytest.approx(0.09)
    assert scaled_proximity(0.15, {"calibration_scale": 9.0}) == pytest.approx(0.24)


def test_same_geometry_passes_or_fails_by_calibration_scale():
    """Distance 0.16 is inside ARM_STALL_PROXIMITY at 1.0 and outside at 0.6."""
    mid = Point2D(0.40, 0.55)
    offset = Point2D(mid.x + 0.16, mid.y)
    bottle = _bottle_at(offset)
    pose = _arm_pose()
    state = {"calibration_scale": 1.0}
    for _ in range(6):
        state, _ = track_bottle_stability(state, bottle)

    pass_result, _, pass_state = evaluate_movement(
        "Forearm Stall",
        bottle,
        pose,
        None,
        None,
        dict(state),
        calibration_scale=1.0,
    )
    fail_result, _, fail_state = evaluate_movement(
        "Forearm Stall",
        bottle,
        pose,
        None,
        None,
        dict(state),
        calibration_scale=0.6,
    )

    assert pass_result.posture_status == "stable"
    assert fail_result.posture_status == "unstable"
    assert pass_state["calibration_scale"] == pytest.approx(1.0)
    assert fail_state["calibration_scale"] == pytest.approx(0.6)

    far = _bottle_at(Point2D(mid.x + 0.28, mid.y))
    far_state = {"calibration_scale": 1.6}
    for _ in range(6):
        far_state, _ = track_bottle_stability(far_state, far)
    far_fail, _, _ = evaluate_movement(
        "Forearm Stall", far, pose, None, None, dict(far_state), calibration_scale=1.0
    )
    far_pass, _, _ = evaluate_movement(
        "Forearm Stall", far, pose, None, None, dict(far_state), calibration_scale=1.6
    )
    assert far_fail.posture_status == "unstable"
    assert far_pass.posture_status == "stable"


def test_hand_bottle_proximity_respects_calibration_scale():
    bottle = _bottle(cx=320, cy=240)
    target = Point2D(0.5 + 0.12, 0.5)
    near = check_hand_bottle_proximity(
        bottle, target, movement_state={"calibration_scale": 1.0}
    )
    far = check_hand_bottle_proximity(
        bottle, target, movement_state={"calibration_scale": 0.6}
    )
    assert near.posture_status == "stable"
    assert far.posture_status == "unstable"
    assert HAND_BOTTLE_PROXIMITY == pytest.approx(0.15)


def test_stall_proximity_and_stability_use_scaled_threshold():
    bottle = _bottle(cx=320, cy=240)
    target = Point2D(0.5 + 0.16, 0.5)
    close = check_stall_proximity(
        bottle,
        target,
        success_message="ok",
        threshold=ARM_STALL_PROXIMITY,
        movement_state={"calibration_scale": 1.0},
    )
    tight = check_stall_proximity(
        bottle,
        target,
        success_message="ok",
        threshold=ARM_STALL_PROXIMITY,
        movement_state={"calibration_scale": 0.6},
    )
    assert close.posture_status == "stable"
    assert tight.posture_status == "unstable"

    small = {"calibration_scale": 1.0}
    tight_state = {"calibration_scale": 0.6}
    origin = _bottle(cx=320, cy=240)
    drift = _bottle(cx=320 + int(STALL_STABILITY_THRESHOLD * 640 * 0.8), cy=240)
    for _ in range(4):
        small, small_ok = track_bottle_stability(small, origin)
        tight_state, _ = track_bottle_stability(tight_state, origin)
    small, small_ok = track_bottle_stability(small, drift)
    tight_state, tight_ok = track_bottle_stability(tight_state, drift)
    assert small_ok is True
    assert tight_ok is False


def test_hand_stall_readiness_loads_pose_without_changing_checklist(monkeypatch):
    from api import websocket as websocket_api
    from assessment.readiness import requirements_for
    from test_session_lifecycle import _patch_vision

    _patch_vision(monkeypatch)
    codes = [req.code for req in requirements_for("Hand Stall")]
    assert "upper_body_visible" not in codes

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()
    assert session.pose_detector is not None
    msg = session.process_readiness_frame()
    assert msg is not None
    assert [item.code for item in msg.readiness_items] == codes
    session.close()


def test_session_prefers_shoulders_over_later_palm_fallback(monkeypatch):
    from api import websocket as websocket_api
    from test_session_lifecycle import (
        StubHandsDetector,
        StubPoseDetector,
        _activate_after_readiness,
        _patch_vision,
    )

    _patch_vision(monkeypatch)

    class SequencedPose(StubPoseDetector):
        def __init__(self, **kwargs):
            super().__init__(**kwargs)
            self._n = 0

        def detect(self, current_frame):
            self._n += 1
            if self._n == 1:
                return _pose_shoulders()
            return None

    class SequencedHands(StubHandsDetector):
        def __init__(self, **kwargs):
            super().__init__(**kwargs)
            self._n = 0

        def detect(self, current_frame, bottle=None):
            self._n += 1
            if self._n == 1:
                return None
            return _hands_palm(Point2D(0.5, 0.90), Point2D(0.5, 0.10))

    monkeypatch.setattr(websocket_api, "PoseDetector", SequencedPose)
    monkeypatch.setattr(websocket_api, "HandsDetector", SequencedHands)

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()
    first = session.process_readiness_frame()
    second = session.process_readiness_frame()
    assert first.calibration_source == "shoulders"
    assert first.calibration_scale == pytest.approx(1.0)
    assert second.calibration_source == "shoulders"
    assert second.calibration_scale == pytest.approx(1.0)

    _activate_after_readiness(session)
    assert session._calibration.source == "shoulders"
    assert session._calibration.locked is True
    assert session.pose_detector is None
    session.close()


def test_session_palm_fallback_when_shoulders_absent(monkeypatch):
    from api import websocket as websocket_api
    from test_session_lifecycle import StubHandsDetector, StubPoseDetector, _patch_vision

    _patch_vision(monkeypatch)

    class PalmHands(StubHandsDetector):
        def detect(self, current_frame, bottle=None):
            return _hands_palm(Point2D(0.5, 0.56), Point2D(0.5, 0.50))

    class EmptyPose(StubPoseDetector):
        def detect(self, current_frame):
            return None

    monkeypatch.setattr(websocket_api, "HandsDetector", PalmHands)
    monkeypatch.setattr(websocket_api, "PoseDetector", EmptyPose)

    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()
    msg = session.process_readiness_frame()
    assert msg.calibration_source == "palm_fallback"
    assert msg.calibration_scale == pytest.approx(0.06 / 0.04)
    session.close()


def test_session_default_when_neither_visible(monkeypatch):
    from api import websocket as websocket_api
    from test_session_lifecycle import _confirm_session_readiness, _patch_vision

    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()
    msg = session.process_readiness_frame()
    assert msg.calibration_scale is None
    assert msg.calibration_source is None
    _confirm_session_readiness(session)
    assert session._calibration.resolved == (1.0, "default")
    session.close()


def test_free_practice_does_not_measure_calibration(monkeypatch):
    from api import websocket as websocket_api
    from test_session_lifecycle import _activate_prepared, _patch_vision

    _patch_vision(monkeypatch)
    session = websocket_api.VisionSession("Free Practice", prop_type="shaker")
    session.start()
    _activate_prepared(session)
    assert session.pose_detector is None
    assert session._calibration.scale is None
    assert session._calibration.resolved == (1.0, "default")
    session.close()


def test_begin_readiness_idempotent_does_not_clear_calibration(monkeypatch):
    from api import websocket as websocket_api
    from test_session_lifecycle import StubPoseDetector, _patch_vision

    _patch_vision(monkeypatch)

    class ShoulderPose(StubPoseDetector):
        def detect(self, current_frame):
            return _pose_shoulders()

    monkeypatch.setattr(websocket_api, "PoseDetector", ShoulderPose)
    session = websocket_api.VisionSession("Hand Stall")
    session.start()
    session.begin_readiness()
    session.process_readiness_frame()
    assert session._calibration.source == "shoulders"
    assert session.begin_readiness() is True
    assert session._calibration.source == "shoulders"
    session.close()
