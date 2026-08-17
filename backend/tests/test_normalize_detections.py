"""YOLO-confirmed props are the only detections exposed to rules and UI."""

from __future__ import annotations

from api.websocket import VisionSession
from vision.types import PropDetection


def _box(*, x1: int = 10, yolo_confirmed: bool = True) -> PropDetection:
    return PropDetection(
        x1=x1,
        y1=10,
        x2=x1 + 20,
        y2=80,
        confidence=0.9,
        yolo_confirmed=yolo_confirmed,
    )


def test_unconfirmed_bottle_is_not_annotated():
    session = VisionSession("Normal Grip")
    confirmed = _box(x1=10, yolo_confirmed=True)
    stale = _box(x1=200, yolo_confirmed=False)

    result = session._normalize_detections(
        bottles=[confirmed, stale],
        shakers=[],
    )

    assert result.annotation == (confirmed,)
    assert result.primary == (confirmed,)
    assert result.bottles == (confirmed,)


def test_unconfirmed_bottle_does_not_count_as_detected():
    session = VisionSession("Normal Grip")
    stale = _box(yolo_confirmed=False)

    result = session._normalize_detections(bottles=[stale], shakers=[])

    assert result.selected_detected is False
    assert result.selected_count == 0
    assert result.primary == ()


def test_unconfirmed_shaker_is_not_annotated_or_detected():
    session = VisionSession("Hand Stall", prop_type="shaker")
    stale = _box(yolo_confirmed=False)

    result = session._normalize_detections(bottles=[], shakers=[stale])

    assert result.annotation == ()
    assert result.primary == ()
    assert result.shakers == ()
    assert result.selected_detected is False
    assert result.selected_count == 0


def test_bottle_in_a_tin_requires_both_props_yolo_confirmed():
    session = VisionSession("Bottle in a tin", prop_type="bottle_and_shaker")
    bottle = _box(x1=10, yolo_confirmed=True)
    stale_shaker = _box(x1=200, yolo_confirmed=False)

    result = session._normalize_detections(
        bottles=[bottle],
        shakers=[stale_shaker],
    )

    assert result.selected_detected is False
    assert result.annotation == (bottle,)
    assert result.shakers == ()
    assert result.selected_count == 1

    stale_bottle = _box(x1=10, yolo_confirmed=False)
    shaker = _box(x1=200, yolo_confirmed=True)
    reverse = session._normalize_detections(
        bottles=[stale_bottle],
        shakers=[shaker],
    )
    assert reverse.selected_detected is False
    assert reverse.annotation == (shaker,)
    assert reverse.bottles == ()
    assert reverse.selected_count == 1
