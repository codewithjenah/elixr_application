from dataclasses import dataclass, field
from typing import Optional


@dataclass(frozen=True)
class Point2D:
    x: float
    y: float


@dataclass(frozen=True)
class BottleDetection:
    x1: int
    y1: int
    x2: int
    y2: int
    confidence: float

    @property
    def center(self) -> Point2D:
        return Point2D(
            x=(self.x1 + self.x2) / 2.0,
            y=(self.y1 + self.y2) / 2.0,
        )

    def center_normalized(self, width: int, height: int) -> Point2D:
        c = self.center
        return Point2D(x=c.x / width, y=c.y / height)

    @property
    def bottom_center(self) -> Point2D:
        """Bottom-center of the bbox — the support/contact point on a palm."""
        return Point2D(
            x=(self.x1 + self.x2) / 2.0,
            y=float(self.y2),
        )

    def bottom_center_normalized(self, width: int, height: int) -> Point2D:
        c = self.bottom_center
        return Point2D(x=c.x / width, y=c.y / height)


@dataclass
class PoseLandmarks:
    """Normalized landmark coords (0-1) keyed by MediaPipe Pose index."""

    points: dict[int, Point2D] = field(default_factory=dict)
    visibility: dict[int, float] = field(default_factory=dict)

    def get(self, index: int, min_visibility: float = 0.5) -> Optional[Point2D]:
        vis = self.visibility.get(index, 0.0)
        if vis < min_visibility:
            return None
        return self.points.get(index)


@dataclass
class HandLandmarks:
    """One hand: normalized landmark coords keyed by MediaPipe Hand index."""

    points: dict[int, Point2D] = field(default_factory=dict)
    handedness: str = "Unknown"

    def palm_center(self) -> Optional[Point2D]:
        wrist = self.points.get(0)
        middle_mcp = self.points.get(9)
        if wrist is None or middle_mcp is None:
            return None
        return Point2D(
            x=(wrist.x + middle_mcp.x) / 2.0,
            y=(wrist.y + middle_mcp.y) / 2.0,
        )


@dataclass
class HandsResult:
    hands: list[HandLandmarks] = field(default_factory=list)

    def nearest_palm_to(self, target: Point2D) -> Optional[Point2D]:
        best: Optional[Point2D] = None
        best_dist = float("inf")
        for hand in self.hands:
            palm = hand.palm_center()
            if palm is None:
                continue
            dist = _dist(palm, target)
            if dist < best_dist:
                best_dist = dist
                best = palm
        return best


def _dist(a: Point2D, b: Point2D) -> float:
    return ((a.x - b.x) ** 2 + (a.y - b.y) ** 2) ** 0.5


def pixel_to_normalized(x: float, y: float, width: int, height: int) -> Point2D:
    return Point2D(x=x / width, y=y / height)
