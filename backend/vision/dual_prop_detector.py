"""Dual-prop detector for movements that need bottle + shaker simultaneously.

Owns one bottle detector and one shaker detector. To avoid running two YOLO
inferences on every processed frame, callers should invoke ``detect`` only on
frames eligible for a YOLO update (i.e. respecting ``YOLO_FRAME_SKIP``
upstream); each eligible call alternates between refreshing the bottle cache
and the shaker cache, so the first two eligible updates initialize both.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from vision.prop_detector import ModelLoadError, PropDetector
from vision.types import PropDetection

__all__ = ["DualPropDetector", "DualPropResult", "ModelLoadError"]


@dataclass
class DualPropResult:
    bottles: list[PropDetection] = field(default_factory=list)
    shakers: list[PropDetection] = field(default_factory=list)


class DualPropDetector:
    """Alternates YOLO inference between a bottle detector and shaker detector."""

    def __init__(
        self,
        *,
        enabled: bool = True,
        bottle_detector: Optional[object] = None,
        shaker_detector: Optional[object] = None,
    ) -> None:
        self._enabled = enabled
        self._bottle_detector = bottle_detector or PropDetector(
            prop_type="bottle", enabled=enabled
        )
        self._shaker_detector = shaker_detector or PropDetector(
            prop_type="shaker", enabled=enabled
        )
        self._last_bottles: list[PropDetection] = []
        self._last_shakers: list[PropDetection] = []
        self._next_target: str = "bottle"

    @property
    def enabled(self) -> bool:
        return self._enabled

    def set_enabled(self, enabled: bool) -> None:
        self._enabled = enabled

    @property
    def bottle_detector(self):
        return self._bottle_detector

    @property
    def shaker_detector(self):
        return self._shaker_detector

    def ensure_ready(self) -> None:
        """Validate both models now. Raises ModelLoadError if either fails."""
        self._bottle_detector.ensure_ready()
        self._shaker_detector.ensure_ready()

    def reset_cache(self) -> None:
        """Clear cached detections and restart the alternating sequence.

        Called on session activation so a newly activated session does not
        inherit stale detections or alternation phase from a prior attempt.
        """
        self._last_bottles = []
        self._last_shakers = []
        self._next_target = "bottle"

    def detect(self, frame) -> DualPropResult:
        """Refresh exactly one of the bottle/shaker caches and return both.

        Call only on frames eligible for a YOLO update; do not call this on
        every processed frame, since each call still performs one full YOLO
        inference for whichever prop is due next in the alternation.
        """
        if not self._enabled:
            return DualPropResult(bottles=[], shakers=[])

        if self._next_target == "bottle":
            self._last_bottles = list(self._bottle_detector.detect(frame))
            self._next_target = "shaker"
        else:
            self._last_shakers = list(self._shaker_detector.detect(frame))
            self._next_target = "bottle"

        return DualPropResult(
            bottles=list(self._last_bottles),
            shakers=list(self._last_shakers),
        )
