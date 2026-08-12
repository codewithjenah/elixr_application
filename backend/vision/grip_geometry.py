from typing import Optional

from vision.types import (
    BottleDetection,
    HandLandmarks,
    Point2D,
)

BARTENDER_CONTROL_ANCHOR_FRACTION = 0.42
BARTENDER_CONTACT_BOTTOM_FRACTION = 0.70
BARTENDER_WRAP_BOTTOM_FRACTION = 0.88
_HORIZONTAL_MARGIN_FRACTION = 0.25
_TOP_MARGIN_FRACTION = 0.05
_MIN_HORIZONTAL_MARGIN = 0.03
_MIN_TOP_MARGIN = 0.02

ContactZone = tuple[float, float, float, float]


def bartender_control_point(
    hand: HandLandmarks,
) -> Optional[Point2D]:
    thumb = hand.points.get(4)
    index = hand.points.get(8)
    if thumb is None or index is None:
        return None
    return Point2D(
        x=(thumb.x + index.x) / 2.0,
        y=(thumb.y + index.y) / 2.0,
    )


def bartender_control_anchor(
    bottle: BottleDetection,
    *,
    frame_width: int,
    frame_height: int,
) -> Point2D:
    bottle_height = bottle.y2 - bottle.y1
    return Point2D(
        x=((bottle.x1 + bottle.x2) / 2.0) / frame_width,
        y=(
            bottle.y1
            + bottle_height * BARTENDER_CONTROL_ANCHOR_FRACTION
        ) / frame_height,
    )


def bartender_contact_zone(
    bottle: BottleDetection,
    *,
    frame_width: int,
    frame_height: int,
    bottom_fraction: float = BARTENDER_CONTACT_BOTTOM_FRACTION,
) -> ContactZone:
    left = bottle.x1 / frame_width
    top = bottle.y1 / frame_height
    right = bottle.x2 / frame_width
    bottle_width = (bottle.x2 - bottle.x1) / frame_width
    bottle_height = (bottle.y2 - bottle.y1) / frame_height

    horizontal_margin = max(
        _MIN_HORIZONTAL_MARGIN,
        bottle_width * _HORIZONTAL_MARGIN_FRACTION,
    )
    top_margin = max(
        _MIN_TOP_MARGIN,
        bottle_height * _TOP_MARGIN_FRACTION,
    )
    bottom = top + bottle_height * bottom_fraction

    return (
        left - horizontal_margin,
        top - top_margin,
        right + horizontal_margin,
        bottom,
    )


def point_in_zone(
    point: Optional[Point2D],
    zone: ContactZone,
) -> bool:
    if point is None:
        return False
    left, top, right, bottom = zone
    return left <= point.x <= right and top <= point.y <= bottom
