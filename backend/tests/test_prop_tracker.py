"""IoU identity tracker for per-class prop detections."""

from __future__ import annotations

import pytest

from config import PROP_TRACK_MAX_MISSED_FRAMES, TARGET_FPS, YOLO_FRAME_SKIP
from vision.prop_tracker import PropTracker
from vision.types import PropDetection


def _det(
    x1: int,
    y1: int,
    x2: int,
    y2: int,
    *,
    confidence: float = 0.9,
) -> PropDetection:
    return PropDetection(x1=x1, y1=y1, x2=x2, y2=y2, confidence=confidence)


def test_two_bottles_crossing_paths_keep_track_id():
    """Horizontal order can swap; each box still matches its own previous IoU."""
    tracker = PropTracker()

    # Vertically offset so boxes never compete for the same previous track.
    # Each frame shifts ±20 px (IoU ~0.6 against the previous same-object box).
    upper_y1, upper_y2 = 10, 90
    lower_y1, lower_y2 = 100, 180
    a_x1, b_x1 = 20, 220

    first = tracker.update(
        [
            _det(a_x1, upper_y1, a_x1 + 80, upper_y2),
            _det(b_x1, lower_y1, b_x1 + 80, lower_y2),
        ]
    )
    a_id = next(det.track_id for det in first if det.y1 == upper_y1)
    b_id = next(det.track_id for det in first if det.y1 == lower_y1)
    assert a_id is not None and b_id is not None
    assert a_id != b_id

    crossed = False
    for _ in range(8):
        a_x1 += 20
        b_x1 -= 20
        tracked = tracker.update(
            [
                _det(a_x1, upper_y1, a_x1 + 80, upper_y2),
                _det(b_x1, lower_y1, b_x1 + 80, lower_y2),
            ]
        )
        assert {det.track_id for det in tracked} == {a_id, b_id}
        upper = next(det for det in tracked if det.y1 == upper_y1)
        lower = next(det for det in tracked if det.y1 == lower_y1)
        assert upper.track_id == a_id
        assert lower.track_id == b_id
        if upper.center.x > lower.center.x:
            crossed = True

    assert crossed


def test_bottle_gone_three_frames_keeps_track_id():
    tracker = PropTracker()
    first = tracker.update([_det(10, 10, 50, 90)])
    assert first[0].track_id == 1

    for _ in range(3):
        assert tracker.update([]) == []

    reappeared = tracker.update([_det(12, 12, 52, 92)])
    assert len(reappeared) == 1
    assert reappeared[0].track_id == 1


def test_bottle_gone_longer_than_max_missed_gets_new_id():
    tracker = PropTracker()
    first = tracker.update([_det(10, 10, 50, 90)])
    assert first[0].track_id == 1

    for _ in range(PROP_TRACK_MAX_MISSED_FRAMES + 1):
        assert tracker.update([]) == []

    reappeared = tracker.update([_det(12, 12, 52, 92)])
    assert len(reappeared) == 1
    assert reappeared[0].track_id != 1
    assert reappeared[0].track_id == 2


def _box(x1: int, y1: int = 10, width: int = 40, height: int = 80) -> PropDetection:
    return _det(x1, y1, x1 + width, y1 + height)


def test_extrapolate_follows_constant_velocity_across_skipped_frames():
    """Skipped-frame boxes should coast at the last YOLO-confirmed velocity."""
    tracker = PropTracker()
    velocity_px_s = 200.0
    yolo_dt = YOLO_FRAME_SKIP / TARGET_FPS
    frame_dt = 1.0 / TARGET_FPS
    start_x = 40

    first = tracker.update([_box(start_x)], timestamp=0.0)
    second_x = start_x + int(round(velocity_px_s * yolo_dt))
    confirmed = tracker.update([_box(second_x)], timestamp=yolo_dt)
    assert first[0].track_id == confirmed[0].track_id

    # Several skipped frames after the second YOLO confirmation.
    skipped_times = [yolo_dt + frame_dt, yolo_dt + 2 * frame_dt, yolo_dt + 3 * frame_dt]
    for now in skipped_times:
        predicted = tracker.extrapolate(confirmed, now=now)
        assert len(predicted) == 1
        expected_x = start_x + velocity_px_s * now
        assert predicted[0].x1 == pytest.approx(expected_x, abs=1.5)
        assert predicted[0].x2 == pytest.approx(expected_x + 40, abs=1.5)
        assert predicted[0].y1 == 10
        assert predicted[0].y2 == 90
        assert predicted[0].track_id == confirmed[0].track_id


def test_extrapolate_falls_back_to_cached_without_velocity_history():
    tracker = PropTracker()
    first = tracker.update([_box(40)], timestamp=0.0)

    predicted = tracker.extrapolate(first, now=1.0 / TARGET_FPS)

    assert len(predicted) == 1
    assert predicted[0].x1 == 40
    assert predicted[0].y1 == 10
    assert predicted[0].x2 == 80
    assert predicted[0].y2 == 90
    assert predicted[0].track_id == first[0].track_id


def test_extrapolate_clamps_lead_time_when_yolo_stalls():
    tracker = PropTracker()
    yolo_dt = YOLO_FRAME_SKIP / TARGET_FPS
    max_lead_s = 2 * YOLO_FRAME_SKIP / TARGET_FPS
    tracker.update([_box(40)], timestamp=0.0)
    confirmed = tracker.update([_box(60)], timestamp=yolo_dt)

    stalled = tracker.extrapolate(confirmed, now=yolo_dt + 5.0)
    capped = tracker.extrapolate(confirmed, now=yolo_dt + max_lead_s)

    assert stalled[0].x1 == capped[0].x1
    assert stalled[0].x2 == capped[0].x2
    # Unclamped 5s of 200 px/s would move 1000px; clamp keeps it near 40px.
    assert stalled[0].x1 == pytest.approx(60 + 200.0 * max_lead_s, abs=1.5)
