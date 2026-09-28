"""Presentation-only motion cue tracker (airborne / flip / caught)."""

from assessment.motion_events import MOTION_EVENT_TTL_S, MotionEventTracker
from schemas.feedback import FeedbackMessage
from vision.types import HandLandmarks, HandsResult, Point2D, PropDetection

W, H = 640, 480
DT = 1 / 30


def _hands_at(x: float, y: float) -> HandsResult:
    return HandsResult(
        hands=[
            HandLandmarks(
                points={0: Point2D(x, y + 0.02), 9: Point2D(x, y)},
                handedness="Right",
            )
        ]
    )


def _box(cx: float, cy: float, *, w: int = 40, h: int = 80,
         confirmed: bool = True, conf: float = 0.9) -> PropDetection:
    return PropDetection(
        x1=int(cx - w / 2), y1=int(cy - h / 2),
        x2=int(cx + w / 2), y2=int(cy + h / 2),
        confidence=conf, track_id=1, yolo_confirmed=confirmed,
    )


HAND = _hands_at(0.5, 0.5)  # pixel (320, 240)


class _Driver:
    def __init__(self) -> None:
        self.tracker = MotionEventTracker()
        self.t = 0.0
        self.events: list[str] = []

    def step(self, prop, hands=HAND):
        self.t += DT
        event = self.tracker.update(
            timestamp=self.t, prop=prop, hands=hands, width=W, height=H
        )
        if event is not None:
            self.events.append(event.kind)
        return event

    def hold(self, frames: int = 10):
        for _ in range(frames):
            self.step(_box(320, 240))

    def toss_up(self, frames: int = 4, *, w: int = 40, h: int = 80):
        y = 240
        for _ in range(frames):
            y -= 40
            self.step(_box(320, y, w=w, h=h))
        return y


def test_airborne_after_hold_and_upward_release():
    d = _Driver()
    d.hold()
    d.toss_up()
    assert d.events == ["airborne"]
    current = d.tracker.current(d.t)
    assert current is not None and current.kind == "airborne"
    assert 0.0 < current.confidence <= 1.0


def test_no_airborne_while_holding_even_when_moving_with_hand():
    d = _Driver()
    y = 240
    for _ in range(30):
        y -= 5  # bottle and palm move up together
        d.step(_box(320, y), hands=_hands_at(0.5, y / H))
    assert d.events == []


def test_no_airborne_without_hands_landmarks():
    d = _Driver()
    d.hold()
    y = 240
    for _ in range(6):
        y -= 40
        d.step(_box(320, y), hands=None)
    assert d.events == []


def test_no_airborne_from_coasted_boxes_on_skipped_yolo_frames():
    d = _Driver()
    d.hold()
    y = 240
    for _ in range(6):
        y -= 40
        d.step(_box(320, y, confirmed=False))
    assert d.events == []


def test_downward_or_sideways_separation_is_not_airborne():
    d = _Driver()
    d.hold()
    x = 320
    for _ in range(6):
        x += 60
        d.step(_box(x, 240))
    assert d.events == []


def test_no_flip_from_translation_without_rotation():
    d = _Driver()
    d.hold()
    y = d.toss_up()
    for _ in range(8):  # jitter around in flight, box stays tall
        y += 3
        d.step(_box(330, y))
    assert "flip" not in d.events


def test_flip_requires_orientation_change_in_flight():
    d = _Driver()
    d.hold()
    y = d.toss_up()
    d.step(_box(320, y))  # still upright in flight
    d.step(_box(320, y))
    d.step(_box(320, y, w=80, h=40))  # rotated to wide
    assert d.events == ["airborne"]  # one wide frame is not enough
    d.step(_box(320, y, w=80, h=40))
    assert d.events == ["airborne", "flip"]
    d.step(_box(320, y, w=40, h=80))
    assert d.events.count("flip") == 1


def test_edge_clipped_box_is_not_a_flip():
    d = _Driver()
    d.hold()
    d.toss_up()
    for _ in range(4):  # clipped at the top edge: wide-looking, not rotated
        d.step(PropDetection(x1=280, y1=0, x2=360, y2=40, confidence=0.9,
                             track_id=1, yolo_confirmed=True))
    assert "flip" not in d.events


def test_missing_palm_while_held_is_not_airborne():
    d = _Driver()
    d.hold()
    no_palm = HandsResult(hands=[])
    y = 240
    for _ in range(6):
        y -= 40
        d.step(_box(320, y), hands=no_palm)
    assert d.events == []


def test_offcenter_grip_moving_up_is_not_airborne():
    d = _Driver()
    d.hold()
    # Palm holds the base; box center sits just outside the grip radius and
    # everything rises together.
    for i in range(10):
        hand_y = 0.5 - i * 0.05
        cy = (hand_y - 0.17) * H
        d.step(_box(320, cy), hands=_hands_at(0.5, hand_y))
    assert d.events == []


def test_caught_after_airborne_when_slow_and_near_palm():
    d = _Driver()
    d.hold()
    d.toss_up()
    for _ in range(6):
        d.step(_box(320, 150))  # hanging, away from palm
    for _ in range(8):
        d.step(_box(320, 240))  # back in hand, stationary
    assert d.events[0] == "airborne"
    assert d.events[-1] == "caught"


def test_event_expires_after_ttl():
    d = _Driver()
    d.hold()
    d.toss_up()
    emitted_at = d.tracker.current(d.t).emitted_at
    assert d.tracker.current(emitted_at + MOTION_EVENT_TTL_S - 0.01) is not None
    assert d.tracker.current(emitted_at + MOTION_EVENT_TTL_S + 0.01) is None


def test_flight_timeout_resets_without_caught():
    d = _Driver()
    d.hold()
    d.toss_up()
    for _ in range(60):  # 2s never returning to hand
        d.step(_box(320, 80))
    assert "caught" not in d.events


def test_sequence_monotonic_across_reset():
    d = _Driver()
    d.hold()
    d.toss_up()
    first = d.tracker.current(d.t).sequence
    d.tracker.reset()
    assert d.tracker.current(d.t) is None
    d.hold()
    d.toss_up()
    assert d.tracker.current(d.t).sequence > first


def test_feedback_schema_motion_fields_default_absent_and_validate():
    base = dict(
        bottle_detected=True, movement="Normal Grip", feedback="ok",
        feedback_type="positive", posture_status="stable",
    )
    msg = FeedbackMessage(**base)
    assert msg.motion_event is None and msg.motion_event_sequence is None
    msg = FeedbackMessage(**base, motion_event="flip",
                          motion_event_confidence=0.8, motion_event_sequence=3)
    assert msg.model_dump()["motion_event"] == "flip"
    import pytest
    from pydantic import ValidationError
    with pytest.raises(ValidationError):
        FeedbackMessage(**base, motion_event="spin")
    with pytest.raises(ValidationError):
        FeedbackMessage(**base, motion_event="flip", motion_event_confidence=1.5)
