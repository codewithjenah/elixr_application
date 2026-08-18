"""Immutable overlay snapshots for preview rendering only.

AI inference results may be drawn onto a later camera frame, but they must
never be reused as new scoring, readiness, hold, or anti-cheat samples.
"""

from __future__ import annotations

from dataclasses import dataclass

from vision.types import (
    HandLandmarks,
    HandsResult,
    PoseLandmarks,
    PropDetection,
)


def freeze_hands(hands: HandsResult | None) -> HandsResult | None:
    """Copy hand landmarks so MediaPipe/session workers cannot mutate them."""
    if hands is None:
        return None
    copied: list[HandLandmarks] = []
    for hand in hands.hands:
        copied.append(
            HandLandmarks(
                points=dict(hand.points),
                handedness=hand.handedness,
            )
        )
    return HandsResult(hands=copied)


def freeze_pose(pose: PoseLandmarks | None) -> PoseLandmarks | None:
    """Copy pose landmarks so detector results cannot be mutated in place."""
    if pose is None:
        return None
    return PoseLandmarks(
        points=dict(pose.points),
        visibility=dict(pose.visibility),
    )


@dataclass(frozen=True)
class OverlaySnapshot:
    """Rendering-only geometry tied to the analyzed camera frame.

    ``published_at_monotonic`` is when the snapshot became available for
    preview. Freshness uses this timestamp so a slow inference run does not
    make the overlay expire the instant it is published. Capture time remains
    available for latency telemetry.
    """

    published_at_monotonic: float
    captured_at_monotonic: float
    capture_sequence: int
    boxes: tuple[PropDetection, ...]
    hands: HandsResult | None
    pose: PoseLandmarks | None
    feedback: str
    feedback_type: str
    movement: str
    prop_label: str

    def is_fresh(self, now: float, max_age_s: float) -> bool:
        if max_age_s < 0:
            return False
        return (now - self.published_at_monotonic) <= max_age_s


def freeze_overlay(
    *,
    published_at_monotonic: float,
    captured_at_monotonic: float,
    capture_sequence: int,
    boxes: list[PropDetection] | tuple[PropDetection, ...] | None,
    hands: HandsResult | None,
    pose: PoseLandmarks | None,
    feedback: str,
    feedback_type: str,
    movement: str,
    prop_label: str,
) -> OverlaySnapshot:
    """Build a snapshot with copied landmark graphs and boxed detections."""
    return OverlaySnapshot(
        published_at_monotonic=published_at_monotonic,
        captured_at_monotonic=captured_at_monotonic,
        capture_sequence=capture_sequence,
        boxes=tuple(boxes or ()),
        hands=freeze_hands(hands),
        pose=freeze_pose(pose),
        feedback=feedback,
        feedback_type=feedback_type,
        movement=movement,
        prop_label=prop_label,
    )
