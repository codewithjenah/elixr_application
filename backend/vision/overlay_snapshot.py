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
    preview and remains useful as a lifecycle backstop. Visual alignment must
    be checked against the preview frame's capture time and sequence because a
    newly published inference result may already describe an old image.
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
    capture_generation: int = 0
    box_expires_at: tuple[float | None, ...] = ()
    hands_expires_at: float | None = None
    pose_expires_at: float | None = None

    def is_fresh(self, now: float, max_age_s: float) -> bool:
        if max_age_s < 0:
            return False
        return (now - self.published_at_monotonic) <= max_age_s

    def is_aligned_with_preview(
        self,
        *,
        preview_captured_at_monotonic: float,
        preview_capture_sequence: int,
        max_capture_age_s: float,
        preview_capture_generation: int = 0,
    ) -> bool:
        """Whether this geometry is truthful enough for one preview frame."""
        if max_capture_age_s < 0:
            return False
        capture_age_s = (
            preview_captured_at_monotonic - self.captured_at_monotonic
        )
        sequence_gap = preview_capture_sequence - self.capture_sequence
        return (
            0.0 <= capture_age_s <= max_capture_age_s
            and sequence_gap >= 0
            and preview_capture_generation == self.capture_generation
        )


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
    capture_generation: int = 0,
    box_expires_at: tuple[float | None, ...] = (),
    hands_expires_at: float | None = None,
    pose_expires_at: float | None = None,
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
        capture_generation=capture_generation,
        box_expires_at=box_expires_at,
        hands_expires_at=hands_expires_at,
        pose_expires_at=pose_expires_at,
    )
