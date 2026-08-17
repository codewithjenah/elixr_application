"""Per-session distance calibration from already-running landmark detectors.

Proximity and stall-stability thresholds in config.py are normalized image
space. This module derives a scale factor from the landmarks the current
movement already requires: shoulder width when Pose is running, or palm
length when Hands is running. Callers must not start an extra detector
solely to obtain a scale. Default ``1.0`` if neither sample is available.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

from config import (
    CALIBRATION_REFERENCE_PALM_LENGTH,
    CALIBRATION_REFERENCE_SHOULDER_WIDTH,
    CALIBRATION_SCALE_MAX,
    CALIBRATION_SCALE_MIN,
)
from vision.types import HandsResult, Point2D, PoseLandmarks

CalibrationSource = str


def _dist(a: Point2D, b: Point2D) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def clamp_calibration_scale(scale: float) -> float:
    if scale < CALIBRATION_SCALE_MIN:
        return CALIBRATION_SCALE_MIN
    if scale > CALIBRATION_SCALE_MAX:
        return CALIBRATION_SCALE_MAX
    return scale


def compute_calibration_scale(
    pose: Optional[PoseLandmarks],
    hands: Optional[HandsResult],
    *,
    min_visibility: float = 0.5,
) -> tuple[float, str]:
    """Return ``(scale, source)`` from landmarks the caller already produced.

    Pass only the in-use modality (Pose for pose-required movements, Hands
    for hand-required movements). Source is ``"shoulders"``,
    ``"palm_fallback"``, or ``"default"``. When both are supplied, shoulder
    width still wins so a dual-modality caller cannot be overwritten by palm.
    """
    if pose is not None:
        left = pose.get(11, min_visibility=min_visibility)
        right = pose.get(12, min_visibility=min_visibility)
        if left is not None and right is not None:
            width = _dist(left, right)
            if width > 1e-6:
                scale = width / CALIBRATION_REFERENCE_SHOULDER_WIDTH
                return clamp_calibration_scale(scale), "shoulders"

    if hands is not None:
        for hand in hands.hands:
            wrist = hand.points.get(0)
            middle_mcp = hand.points.get(9)
            if wrist is None or middle_mcp is None:
                continue
            length = _dist(wrist, middle_mcp)
            if length <= 1e-6:
                continue
            scale = length / CALIBRATION_REFERENCE_PALM_LENGTH
            return clamp_calibration_scale(scale), "palm_fallback"

    return 1.0, "default"


def scaled_proximity(
    value: float, movement_state: Optional[dict] = None
) -> float:
    """Multiply a normalized proximity/stability threshold by session scale."""
    scale = 1.0
    if movement_state is not None:
        raw = movement_state.get("calibration_scale")
        if isinstance(raw, (int, float)):
            scale = clamp_calibration_scale(float(raw))
    return value * scale


@dataclass
class CalibrationTracker:
    """Live-then-lock sampler for one guided-practice readiness cycle."""

    scale: float | None = None
    source: str | None = None
    locked: bool = False

    def sample(
        self,
        pose: Optional[PoseLandmarks],
        hands: Optional[HandsResult],
    ) -> None:
        if self.locked:
            return
        scale, source = compute_calibration_scale(pose, hands)
        if source == "default":
            return
        if self.source == "shoulders" and source != "shoulders":
            return
        self.scale = scale
        self.source = source

    def lock(self) -> tuple[float, str]:
        self.locked = True
        if self.scale is None or self.source is None:
            self.scale = 1.0
            self.source = "default"
        return self.scale, self.source

    def reset(self) -> None:
        self.scale = None
        self.source = None
        self.locked = False

    @property
    def resolved(self) -> tuple[float, str]:
        if self.scale is None or self.source is None:
            return 1.0, "default"
        return self.scale, self.source
