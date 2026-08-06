"""Integration tests: VisionSession readiness normalizes bottle vs shaker props."""

from __future__ import annotations

from vision.types import HandLandmarks, HandsResult, Point2D, PropDetection

from api import websocket as websocket_api
from test_session_lifecycle import (
    StubCamera,
    StubHandsDetector,
    StubPoseDetector,
    _patch_vision,
)


def _palm_hand() -> HandLandmarks:
    return HandLandmarks(
        points={0: Point2D(0.5, 0.54), 9: Point2D(0.5, 0.5)},
        handedness="Right",
    )


class _ShakerReturningPropDetector:
    """Mirrors PropDetector(prop_type='shaker'): detect() returns shaker boxes."""

    instances: list["_ShakerReturningPropDetector"] = []

    def __init__(self, *, prop_type: str, enabled: bool):
        self.prop_type = prop_type
        self.enabled = enabled
        self.detect_calls = 0
        _ShakerReturningPropDetector.instances.append(self)

    def ensure_ready(self):
        pass

    def detect(self, current_frame):
        self.detect_calls += 1
        return [
            PropDetection(x1=100, y1=100, x2=140, y2=180, confidence=0.91),
        ]


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


class _DualReturningDetector:
    def __init__(self, *, enabled: bool, **kwargs):
        self.enabled = enabled
        self.detect_calls = 0

    def ensure_ready(self):
        pass

    def reset_cache(self):
        pass

    def detect(self, current_frame):
        self.detect_calls += 1
        from vision.dual_prop_detector import DualPropResult

        return DualPropResult(
            bottles=[
                PropDetection(x1=10, y1=10, x2=40, y2=80, confidence=0.9),
            ],
            shakers=[
                PropDetection(x1=120, y1=120, x2=160, y2=200, confidence=0.88),
            ],
        )


class _PalmHandsDetector(StubHandsDetector):
    def detect(self, current_frame, bottle=None):
        self.detect_calls += 1
        return HandsResult(hands=[_palm_hand()])


def _drive_stable(session: websocket_api.VisionSession, *, annotate_boxes: list):
    """Advance readiness past hysteresis + stable duration with a fake clock."""
    clock = [1000.0]
    assert session._readiness_tracker is not None
    session._readiness_tracker._monotonic = lambda: clock[0]
    session._readiness_tracker.pass_frames = 1
    session._readiness_tracker.fail_frames = 1
    session._readiness_tracker.stable_duration_s = 0.2

    msg = None
    for _ in range(3):
        msg = session.process_readiness_frame()
        assert msg is not None
        clock[0] += 0.25
    assert msg is not None
    return msg


def test_shaker_hand_stall_readiness_reaches_stable(monkeypatch):
    """Real VisionSession path: shaker detector output must fill obs.shakers."""
    _patch_vision(monkeypatch)
    _ShakerReturningPropDetector.instances = []
    monkeypatch.setattr(
        websocket_api, "PropDetector", _ShakerReturningPropDetector
    )
    monkeypatch.setattr(websocket_api, "HandsDetector", _PalmHandsDetector)

    drawn: list = []

    def capture_annotate(frame, bottles, *args, **kwargs):
        drawn.append(list(bottles))
        return frame

    monkeypatch.setattr(websocket_api, "annotate_frame", capture_annotate)

    session = websocket_api.VisionSession("Hand Stall", prop_type="shaker")
    session.start()
    assert session.begin_readiness() is True

    msg = _drive_stable(session, annotate_boxes=drawn)
    assert msg.prop_type == "shaker"
    assert msg.bottle_detected is True
    assert msg.bottle_count == 1
    assert msg.readiness_complete is True
    assert msg.readiness_stable is True

    prop_item = next(i for i in msg.readiness_items if i.code == "prop_detected")
    assert prop_item.status == "ready"

    assert drawn, "annotate_frame should receive shaker boxes"
    assert len(drawn[-1]) == 1
    assert drawn[-1][0].x1 == 100

    assert session.confirm_readiness() == (True, None)
    session.close()


def test_bottle_hand_stall_readiness_reaches_stable(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "BottleDetector", _BottleReturningDetector)
    monkeypatch.setattr(websocket_api, "HandsDetector", _PalmHandsDetector)

    drawn: list = []

    def capture_annotate(frame, bottles, *args, **kwargs):
        drawn.append(list(bottles))
        return frame

    monkeypatch.setattr(websocket_api, "annotate_frame", capture_annotate)

    session = websocket_api.VisionSession("Hand Stall", prop_type="bottle")
    session.start()
    assert session.begin_readiness() is True

    msg = _drive_stable(session, annotate_boxes=drawn)
    assert msg.prop_type == "bottle"
    assert msg.bottle_detected is True
    assert msg.bottle_count == 1
    assert msg.readiness_stable is True
    assert drawn[-1][0].x1 == 20
    session.close()


def test_bottle_and_shaker_readiness_keeps_lists_separated(monkeypatch):
    _patch_vision(monkeypatch)
    monkeypatch.setattr(websocket_api, "DualPropDetector", _DualReturningDetector)
    monkeypatch.setattr(websocket_api, "HandsDetector", _PalmHandsDetector)

    drawn: list = []

    def capture_annotate(frame, bottles, *args, **kwargs):
        drawn.append(list(bottles))
        return frame

    monkeypatch.setattr(websocket_api, "annotate_frame", capture_annotate)

    session = websocket_api.VisionSession(
        "Bottle in a tin", prop_type="bottle_and_shaker"
    )
    session.start()
    assert session.begin_readiness() is True

    msg = _drive_stable(session, annotate_boxes=drawn)
    assert msg.prop_type == "bottle_and_shaker"
    assert msg.bottle_detected is True
    assert msg.bottle_count == 2
    assert msg.readiness_stable is True

    codes = {i.code: i.status for i in msg.readiness_items}
    assert codes["bottle_detected"] == "ready"
    assert codes["shaker_detected"] == "ready"
    assert len(drawn[-1]) == 2
    xs = sorted(b.x1 for b in drawn[-1])
    assert xs == [10, 120]
    session.close()


def test_active_shaker_still_passes_primary_prop_to_rules(monkeypatch):
    """Normalization must not empty the primary prop for shaker movement rules."""
    _patch_vision(monkeypatch)
    _ShakerReturningPropDetector.instances = []
    monkeypatch.setattr(
        websocket_api, "PropDetector", _ShakerReturningPropDetector
    )
    monkeypatch.setattr(websocket_api, "HandsDetector", _PalmHandsDetector)

    captured: dict = {}

    def tracking_evaluate(movement, bottle, *args, **kwargs):
        captured["bottle"] = bottle
        captured["bottles"] = kwargs.get("bottles")
        captured["shakers"] = kwargs.get("shakers")
        captured["prop_type"] = kwargs.get("prop_type")
        from assessment.rules.base import RuleResult

        return (
            RuleResult(
                feedback="ok",
                feedback_type="positive",
                posture_status="stable",
            ),
            None,
            None,
        )

    monkeypatch.setattr(websocket_api, "evaluate_movement", tracking_evaluate)

    from test_session_lifecycle import _confirm_session_readiness

    session = websocket_api.VisionSession("Hand Stall", prop_type="shaker")
    session.start()
    session.begin_readiness()
    _confirm_session_readiness(session)
    assert session.activate() == (True, None)

    msg = session.process_frame()
    assert msg is not None
    assert captured["prop_type"] == "shaker"
    assert captured["bottle"] is not None
    assert captured["bottle"].x1 == 100
    assert captured["bottles"] is not None
    assert len(captured["bottles"]) == 1
    assert captured["shakers"] is None
    session.close()
