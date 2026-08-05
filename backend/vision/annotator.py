import math

import cv2
import numpy as np

from vision.types import (
    HandLandmarks,
    HandsResult,
    Point2D,
    PoseLandmarks,
    PropDetection,
)

GREEN = (183, 231, 110)
YELLOW = (107, 183, 255)
CYAN = (255, 200, 90)

_HAND_LEFT_COLOR = (80, 220, 80)
_HAND_RIGHT_COLOR = (60, 90, 255)
_OUTLINE_COLOR = (20, 20, 20)

_POSE_LINE_THICKNESS = 2
_POSE_JOINT_RADIUS = 4
_HAND_LINE_THICKNESS = 2
_HAND_JOINT_RADIUS = 3

# Upper-body pose joints (explicitly excludes face 0–10 and legs).
_POSE_LANDMARK_INDICES = (11, 12, 13, 14, 15, 16, 23, 24)

# Upper-body pose connections (MediaPipe Pose indices) relevant to stalls.
_POSE_CONNECTIONS = (
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
    (11, 23),
    (12, 24),
    (23, 24),
)

# Explicit MediaPipe 21-point hand graph (do not rely on internal drawing APIs).
_HAND_CONNECTIONS = (
    # Thumb
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 4),
    # Index
    (0, 5),
    (5, 6),
    (6, 7),
    (7, 8),
    # Middle
    (5, 9),
    (9, 10),
    (10, 11),
    (11, 12),
    # Ring
    (9, 13),
    (13, 14),
    (14, 15),
    (15, 16),
    # Pinky
    (13, 17),
    (17, 18),
    (18, 19),
    (19, 20),
    # Palm closure
    (0, 17),
)


def _normalized_to_pixel(
    point: Point2D,
    width: int,
    height: int,
) -> tuple[int, int]:
    """Map normalized coords to pixels. Call only after validation."""
    return (
        round(point.x * max(width - 1, 0)),
        round(point.y * max(height - 1, 0)),
    )


def _is_normalized_point_visible(point: Point2D | None) -> bool:
    if point is None:
        return False
    if not math.isfinite(point.x) or not math.isfinite(point.y):
        return False
    if point.x < 0.0 or point.x > 1.0:
        return False
    if point.y < 0.0 or point.y > 1.0:
        return False
    return True


def _hand_color(handedness: str | None) -> tuple[int, int, int]:
    if not handedness:
        return YELLOW
    key = handedness.casefold()
    if key == "left":
        return _HAND_LEFT_COLOR
    if key == "right":
        return _HAND_RIGHT_COLOR
    return YELLOW


def _draw_segment(
    img: np.ndarray,
    p1: tuple[int, int],
    p2: tuple[int, int],
    color: tuple[int, int, int],
    thickness: int,
) -> None:
    cv2.line(
        img,
        p1,
        p2,
        _OUTLINE_COLOR,
        thickness + 1,
        lineType=cv2.LINE_AA,
    )
    cv2.line(
        img,
        p1,
        p2,
        color,
        thickness,
        lineType=cv2.LINE_AA,
    )


def _draw_joint(
    img: np.ndarray,
    center: tuple[int, int],
    radius: int,
    color: tuple[int, int, int],
) -> None:
    cv2.circle(
        img,
        center,
        radius + 1,
        _OUTLINE_COLOR,
        -1,
        lineType=cv2.LINE_AA,
    )
    cv2.circle(
        img,
        center,
        radius,
        color,
        -1,
        lineType=cv2.LINE_AA,
    )


def _draw_pose_skeleton(img: np.ndarray, pose: PoseLandmarks) -> None:
    height, width = img.shape[:2]

    for a, b in _POSE_CONNECTIONS:
        pa = pose.get(a)
        pb = pose.get(b)
        if not _is_normalized_point_visible(pa):
            continue
        if not _is_normalized_point_visible(pb):
            continue
        assert pa is not None and pb is not None
        _draw_segment(
            img,
            _normalized_to_pixel(pa, width, height),
            _normalized_to_pixel(pb, width, height),
            CYAN,
            _POSE_LINE_THICKNESS,
        )

    for idx in _POSE_LANDMARK_INDICES:
        pt = pose.get(idx)
        if not _is_normalized_point_visible(pt):
            continue
        assert pt is not None
        _draw_joint(
            img,
            _normalized_to_pixel(pt, width, height),
            _POSE_JOINT_RADIUS,
            CYAN,
        )


def _draw_hand_skeleton(img: np.ndarray, hand: HandLandmarks) -> None:
    height, width = img.shape[:2]
    color = _hand_color(hand.handedness)

    for a, b in _HAND_CONNECTIONS:
        pa = hand.points.get(a)
        pb = hand.points.get(b)
        if not _is_normalized_point_visible(pa):
            continue
        if not _is_normalized_point_visible(pb):
            continue
        assert pa is not None and pb is not None
        _draw_segment(
            img,
            _normalized_to_pixel(pa, width, height),
            _normalized_to_pixel(pb, width, height),
            color,
            _HAND_LINE_THICKNESS,
        )

    for pt in hand.points.values():
        if not _is_normalized_point_visible(pt):
            continue
        _draw_joint(
            img,
            _normalized_to_pixel(pt, width, height),
            _HAND_JOINT_RADIUS,
            color,
        )


def annotate_frame(
    frame: np.ndarray,
    bottles: list[PropDetection] | None,
    hands: HandsResult | None,
    feedback: str,
    feedback_type: str,
    movement: str,
    score: int,
    pose: PoseLandmarks | None = None,
    prop_label: str = "Bottle",
) -> np.ndarray:
    """Draw CV geometry while leaving the readable prop label to Flutter.

    ``prop_label`` remains part of the signature for compatibility with
    existing callers, but Flutter renders it outside the mirrored image.
    """
    out = frame.copy()

    for prop in bottles or []:
        cv2.rectangle(out, (prop.x1, prop.y1), (prop.x2, prop.y2), GREEN, 2)
        cx, cy = int(prop.center.x), int(prop.center.y)
        cv2.circle(out, (cx, cy), 4, GREEN, -1)

    if pose is not None:
        _draw_pose_skeleton(out, pose)

    if hands is not None:
        for hand in hands.hands:
            _draw_hand_skeleton(out, hand)

    return out
