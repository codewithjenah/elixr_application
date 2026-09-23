"""Directed bottle-axis evidence from observed top and base points.

The ordinary prop detector remains responsible for class and track identity.
An orientation observation is usable only when *both* labelled ends are seen;
an axis-aligned detection box never supplies an angle.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Any, Mapping


MIN_KEYPOINT_CONFIDENCE = 0.5
MIN_AXIS_LENGTH = 0.025  # pixel-equivalent length as a fraction of image height


@dataclass(frozen=True)
class BottleKeypoint:
    x: float
    y: float
    confidence: float

    def valid(self) -> bool:
        return (
            all(math.isfinite(v) for v in (self.x, self.y, self.confidence))
            and 0 <= self.x <= 1
            and 0 <= self.y <= 1
            and MIN_KEYPOINT_CONFIDENCE <= self.confidence <= 1
        )

    def to_dict(self) -> dict[str, float]:
        return {"x": self.x, "y": self.y, "confidence": self.confidence}

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any]) -> "BottleKeypoint":
        if set(raw) != {"x", "y", "confidence"}:
            raise ValueError("invalid bottle keypoint")
        point = cls(float(raw["x"]), float(raw["y"]), float(raw["confidence"]))
        if not point.valid():
            raise ValueError("invalid bottle keypoint")
        return point


@dataclass(frozen=True)
class BottleOrientation:
    top: BottleKeypoint
    base: BottleKeypoint
    confidence: float
    image_aspect_ratio: float = 1.0

    @classmethod
    def observed(
        cls, top: BottleKeypoint, base: BottleKeypoint, detection_confidence: float,
        *, image_aspect_ratio: float = 1.0,
    ) -> "BottleOrientation | None":
        if (not top.valid() or not base.valid() or not 0 <= detection_confidence <= 1
                or not math.isfinite(image_aspect_ratio) or image_aspect_ratio <= 0):
            return None
        if math.hypot((base.x - top.x) * image_aspect_ratio, base.y - top.y) < MIN_AXIS_LENGTH:
            return None
        confidence = min(top.confidence, base.confidence, detection_confidence)
        return cls(top, base, confidence, image_aspect_ratio) if confidence >= MIN_KEYPOINT_CONFIDENCE else None

    @property
    def angle_rad(self) -> float:
        return math.atan2(
            self.base.y - self.top.y,
            (self.base.x - self.top.x) * self.image_aspect_ratio,
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "top": self.top.to_dict(),
            "base": self.base.to_dict(),
            "confidence": self.confidence,
            "image_aspect_ratio": self.image_aspect_ratio,
        }

    @classmethod
    def from_dict(cls, raw: Mapping[str, Any]) -> "BottleOrientation":
        if set(raw) != {"top", "base", "confidence", "image_aspect_ratio"}:
            raise ValueError("invalid bottle orientation")
        observation = cls.observed(
            BottleKeypoint.from_dict(raw["top"]),
            BottleKeypoint.from_dict(raw["base"]),
            float(raw["confidence"]),
            image_aspect_ratio=float(raw["image_aspect_ratio"]),
        )
        if observation is None:
            raise ValueError("invalid bottle orientation")
        return observation


def wrapped_delta(current: float, previous: float) -> float:
    """Shortest directed difference in [-pi, pi); ambiguous half-turns excluded upstream."""
    return (current - previous + math.pi) % (2 * math.pi) - math.pi
