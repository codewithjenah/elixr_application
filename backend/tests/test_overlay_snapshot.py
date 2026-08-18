"""Deterministic overlay snapshot freshness and copy isolation tests."""

from __future__ import annotations

from vision.overlay_snapshot import (
    OverlaySnapshot,
    freeze_hands,
    freeze_overlay,
    freeze_pose,
)
from vision.types import HandLandmarks, HandsResult, Point2D, PoseLandmarks, PropDetection


def _hand() -> HandsResult:
    return HandsResult(
        hands=[
            HandLandmarks(
                points={0: Point2D(0.1, 0.2), 9: Point2D(0.1, 0.15)},
                handedness="Right",
            )
        ]
    )


def test_freeze_hands_copies_landmarks_so_source_mutation_is_ignored():
    original = _hand()
    frozen = freeze_hands(original)
    assert frozen is not None
    original.hands[0].points[0] = Point2D(0.9, 0.9)
    original.hands[0].handedness = "Left"
    assert frozen.hands[0].points[0] == Point2D(0.1, 0.2)
    assert frozen.hands[0].handedness == "Right"


def test_freeze_pose_copies_points_and_visibility():
    original = PoseLandmarks(
        points={11: Point2D(0.3, 0.2)},
        visibility={11: 0.9},
    )
    frozen = freeze_pose(original)
    assert frozen is not None
    original.points[11] = Point2D(0.0, 0.0)
    original.visibility[11] = 0.1
    assert frozen.points[11] == Point2D(0.3, 0.2)
    assert frozen.visibility[11] == 0.9


def test_overlay_expires_after_max_age_and_not_before():
    snapshot = OverlaySnapshot(
        published_at_monotonic=10.0,
        captured_at_monotonic=9.8,
        capture_sequence=7,
        boxes=(),
        hands=None,
        pose=None,
        feedback="",
        feedback_type="positive",
        movement="Hand Stall",
        prop_label="Bottle",
    )
    assert snapshot.is_fresh(10.25, 0.25) is True
    assert snapshot.is_fresh(10.2500001, 0.25) is False
    assert snapshot.is_fresh(12.0, 0.25) is False


def test_freeze_overlay_stores_copied_geometry():
    box = PropDetection(1, 2, 3, 4, 0.9)
    snapshot = freeze_overlay(
        published_at_monotonic=1.0,
        captured_at_monotonic=0.9,
        capture_sequence=3,
        boxes=[box],
        hands=_hand(),
        pose=PoseLandmarks(points={11: Point2D(0.4, 0.3)}, visibility={11: 1.0}),
        feedback="ok",
        feedback_type="positive",
        movement="Hand Stall",
        prop_label="Bottle",
    )
    assert snapshot.boxes == (box,)
    assert snapshot.hands is not None
    assert snapshot.pose is not None
    assert snapshot.capture_sequence == 3
