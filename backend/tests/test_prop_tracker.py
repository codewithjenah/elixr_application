"""IoU identity tracker for per-class prop detections."""

from __future__ import annotations

from config import PROP_TRACK_MAX_MISSED_FRAMES
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
