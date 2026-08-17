"""Dual-prop detector for movements that need bottle + shaker simultaneously.

Uses one combined YOLO inference per eligible frame. Callers should invoke
``detect`` only on frames eligible for a YOLO update (i.e. respecting
``YOLO_FRAME_SKIP`` upstream).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from vision.prop_detector import CombinedPropDetector, ModelLoadError
from vision.types import PropDetection

__all__ = ["DualPropDetector", "DualPropResult", "ModelLoadError"]


@dataclass
class DualPropResult:
    bottles: list[PropDetection] = field(default_factory=list)
    shakers: list[PropDetection] = field(default_factory=list)


class DualPropDetector:
    """Detects bottles and shakers from one combined model inference per call."""

    def __init__(
        self,
        *,
        enabled: bool = True,
        combined_detector: Optional[CombinedPropDetector] = None,
        # Backward-compatible kwargs for older injection sites/tests.
        bottle_detector: Optional[object] = None,
        shaker_detector: Optional[object] = None,
    ) -> None:
        if combined_detector is not None:
            self._combined = combined_detector
        elif bottle_detector is not None or shaker_detector is not None:
            # Legacy injection supplied separate single-prop detectors. Prefer
            # the bottle detector when it exposes detect_all; otherwise wrap a
            # new combined detector for compatibility with old test doubles.
            legacy = bottle_detector or shaker_detector
            if hasattr(legacy, "detect_all"):
                self._combined = legacy  # type: ignore[assignment]
            else:
                self._combined = CombinedPropDetector(enabled=enabled)
        else:
            self._combined = CombinedPropDetector(enabled=enabled)

        self._enabled = enabled

    @property
    def enabled(self) -> bool:
        return self._enabled

    def set_enabled(self, enabled: bool) -> None:
        self._enabled = enabled

    @property
    def combined_detector(self) -> CombinedPropDetector:
        return self._combined

    def ensure_ready(self) -> None:
        """Validate the combined model now. Raises ModelLoadError on failure."""
        self._combined.ensure_ready()

    def reset_cache(self) -> None:
        """Clear per-session prop identities before a new activation."""
        reset = getattr(self._combined, "reset_tracks", None)
        if callable(reset):
            reset()

    def extrapolate_detections(
        self,
        *,
        bottles: list[PropDetection],
        shakers: list[PropDetection],
        now: float,
    ) -> tuple[list[PropDetection], list[PropDetection]]:
        """Coast last YOLO boxes by per-track velocity for skipped frames."""
        extrapolate = getattr(self._combined, "extrapolate_detections", None)
        if callable(extrapolate):
            return extrapolate(bottles=bottles, shakers=shakers, now=now)
        return list(bottles), list(shakers)

    def detect(self, frame) -> DualPropResult:
        """Run one combined inference and return current-frame detections."""
        if not self._enabled:
            return DualPropResult(bottles=[], shakers=[])

        result = self._combined.detect_all(frame)
        return DualPropResult(
            bottles=list(result.bottles),
            shakers=list(result.shakers),
        )
