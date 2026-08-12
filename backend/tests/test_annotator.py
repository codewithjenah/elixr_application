import math

import cv2
import numpy as np
import pytest

from vision.annotator import (
    CYAN,
    GREEN,
    YELLOW,
    _HAND_CONNECTIONS,
    _HAND_JOINT_RADIUS,
    _HAND_LEFT_COLOR,
    _HAND_LINE_THICKNESS,
    _HAND_RIGHT_COLOR,
    _OUTLINE_COLOR,
    _POSE_CONNECTIONS,
    _POSE_JOINT_RADIUS,
    _POSE_LANDMARK_INDICES,
    _POSE_LINE_THICKNESS,
    _normalized_to_pixel,
    annotate_frame,
)
from vision.types import HandLandmarks, HandsResult, Point2D, PoseLandmarks, PropDetection

_FRAME_W = 100
_FRAME_H = 100


def _full_pose(
    *,
    visibility: float = 1.0,
    extra_points: dict[int, Point2D] | None = None,
    extra_visibility: dict[int, float] | None = None,
) -> PoseLandmarks:
    """Upper-body pose with non-overlapping landmark positions."""
    coords = {
        11: Point2D(0.30, 0.20),
        12: Point2D(0.70, 0.20),
        13: Point2D(0.25, 0.40),
        14: Point2D(0.75, 0.40),
        15: Point2D(0.20, 0.60),
        16: Point2D(0.80, 0.60),
        23: Point2D(0.35, 0.80),
        24: Point2D(0.65, 0.80),
    }
    points = dict(coords)
    vis = {idx: visibility for idx in coords}
    if extra_points:
        points.update(extra_points)
    if extra_visibility:
        vis.update(extra_visibility)
    return PoseLandmarks(points=points, visibility=vis)


def _full_hand(
    *,
    handedness: str = "Right",
    origin_x: float = 0.10,
    origin_y: float = 0.10,
    step: float = 0.02,
) -> HandLandmarks:
    """21-point hand with all landmarks in-bounds and distinct."""
    points: dict[int, Point2D] = {}
    for idx in range(21):
        points[idx] = Point2D(
            x=origin_x + (idx % 5) * step,
            y=origin_y + (idx // 5) * step,
        )
    return HandLandmarks(points=points, handedness=handedness)


def _call_annotate(
    frame: np.ndarray,
    *,
    bottles=None,
    hands=None,
    pose=None,
    prop_label: str = "Bottle",
):
    return annotate_frame(
        frame,
        bottles,
        hands,
        "Good",
        "positive",
        "Hand Stall",
        pose=pose,
        prop_label=prop_label,
    )


def _install_draw_capture(monkeypatch):
    line_calls: list[dict] = []
    circle_calls: list[dict] = []

    def capture_line(img, pt1, pt2, color, thickness=1, lineType=8, **kwargs):
        line_calls.append(
            {
                "pt1": (int(pt1[0]), int(pt1[1])),
                "pt2": (int(pt2[0]), int(pt2[1])),
                "color": tuple(color),
                "thickness": thickness,
                "lineType": lineType,
            }
        )

    def capture_circle(
        img,
        center,
        radius,
        color,
        thickness=1,
        lineType=8,
        **kwargs,
    ):
        circle_calls.append(
            {
                "center": (int(center[0]), int(center[1])),
                "radius": radius,
                "color": tuple(color),
                "thickness": thickness,
                "lineType": lineType,
            }
        )

    monkeypatch.setattr(cv2, "line", capture_line)
    monkeypatch.setattr(cv2, "circle", capture_circle)
    return line_calls, circle_calls


def _foreground_lines(line_calls, color, thickness):
    return [
        call
        for call in line_calls
        if call["color"] == color
        and call["thickness"] == thickness
        and call["lineType"] == cv2.LINE_AA
    ]


def _foreground_joints(circle_calls, color, radius):
    return [
        call
        for call in circle_calls
        if call["color"] == color
        and call["radius"] == radius
        and call["thickness"] == -1
        and call["lineType"] == cv2.LINE_AA
    ]


def _endpoint_pair_set(line_calls):
    pairs = set()
    for call in line_calls:
        a = call["pt1"]
        b = call["pt2"]
        pairs.add(tuple(sorted((a, b))))
    return pairs


def test_full_pose_draws_eight_foreground_connections_and_joints(monkeypatch):
    line_calls, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    pose = _full_pose()

    _call_annotate(frame, pose=pose)

    fg_lines = _foreground_lines(line_calls, CYAN, _POSE_LINE_THICKNESS)
    assert len(fg_lines) == 8

    expected_pairs = set()
    for a, b in _POSE_CONNECTIONS:
        pa = pose.points[a]
        pb = pose.points[b]
        expected_pairs.add(
            tuple(
                sorted(
                    (
                        _normalized_to_pixel(pa, _FRAME_W, _FRAME_H),
                        _normalized_to_pixel(pb, _FRAME_W, _FRAME_H),
                    )
                )
            )
        )
    assert _endpoint_pair_set(fg_lines) == expected_pairs

    fg_joints = _foreground_joints(circle_calls, CYAN, _POSE_JOINT_RADIUS)
    assert len(fg_joints) == 8
    centers = {call["center"] for call in fg_joints}
    expected_centers = {
        _normalized_to_pixel(pose.points[idx], _FRAME_W, _FRAME_H)
        for idx in _POSE_LANDMARK_INDICES
    }
    assert centers == expected_centers


def test_face_landmarks_are_never_rendered(monkeypatch):
    line_calls, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)

    # Unique face coords that do not overlap upper-body landmarks.
    face_points = {
        idx: Point2D(x=0.05 + idx * 0.01, y=0.02)
        for idx in range(11)
    }
    pose = _full_pose(
        extra_points=face_points,
        extra_visibility={idx: 1.0 for idx in range(11)},
    )

    _call_annotate(frame, pose=pose)

    face_pixels = {
        _normalized_to_pixel(pt, _FRAME_W, _FRAME_H)
        for pt in face_points.values()
    }

    fg_lines = _foreground_lines(line_calls, CYAN, _POSE_LINE_THICKNESS)
    for call in fg_lines:
        assert call["pt1"] not in face_pixels
        assert call["pt2"] not in face_pixels

    fg_joints = _foreground_joints(circle_calls, CYAN, _POSE_JOINT_RADIUS)
    for call in fg_joints:
        assert call["center"] not in face_pixels


def test_low_visibility_pose_point_skips_joint_and_segments(monkeypatch):
    line_calls, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    pose = _full_pose()
    pose.visibility[15] = 0.1  # left wrist below default min_visibility

    _call_annotate(frame, pose=pose)

    wrist_px = _normalized_to_pixel(pose.points[15], _FRAME_W, _FRAME_H)
    fg_lines = _foreground_lines(line_calls, CYAN, _POSE_LINE_THICKNESS)
    for call in fg_lines:
        assert call["pt1"] != wrist_px
        assert call["pt2"] != wrist_px
    assert len(fg_lines) == 7  # only 13–15 dropped among the eight

    fg_joints = _foreground_joints(circle_calls, CYAN, _POSE_JOINT_RADIUS)
    centers = {call["center"] for call in fg_joints}
    assert wrist_px not in centers
    assert len(fg_joints) == 7


def test_full_hand_draws_twenty_one_foreground_connections(monkeypatch):
    line_calls, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    hand = _full_hand(handedness="Right")

    _call_annotate(frame, hands=HandsResult(hands=[hand]))

    fg_lines = _foreground_lines(
        line_calls, _HAND_RIGHT_COLOR, _HAND_LINE_THICKNESS
    )
    assert len(fg_lines) == 21

    expected_pairs = set()
    for a, b in _HAND_CONNECTIONS:
        expected_pairs.add(
            tuple(
                sorted(
                    (
                        _normalized_to_pixel(hand.points[a], _FRAME_W, _FRAME_H),
                        _normalized_to_pixel(hand.points[b], _FRAME_W, _FRAME_H),
                    )
                )
            )
        )
    assert _endpoint_pair_set(fg_lines) == expected_pairs

    fg_joints = _foreground_joints(
        circle_calls, _HAND_RIGHT_COLOR, _HAND_JOINT_RADIUS
    )
    assert len(fg_joints) == 21


def test_missing_hand_endpoint_skips_dependent_connections(monkeypatch):
    line_calls, _ = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    hand = _full_hand(handedness="Left")
    del hand.points[8]  # index fingertip

    _call_annotate(frame, hands=HandsResult(hands=[hand]))

    fg_lines = _foreground_lines(
        line_calls, _HAND_LEFT_COLOR, _HAND_LINE_THICKNESS
    )
    # Connections involving landmark 8: only (7, 8)
    assert len(fg_lines) == 20
    tip_would_be = _normalized_to_pixel(
        Point2D(x=0.10 + (8 % 5) * 0.02, y=0.10 + (8 // 5) * 0.02),
        _FRAME_W,
        _FRAME_H,
    )
    for call in fg_lines:
        assert call["pt1"] != tip_would_be
        assert call["pt2"] != tip_would_be


def test_out_of_bounds_normalized_points_are_skipped(monkeypatch):
    line_calls, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    hand = HandLandmarks(
        points={
            0: Point2D(0.5, 0.5),
            1: Point2D(1.5, 0.5),  # above 1
            2: Point2D(0.5, -0.1),  # below 0
            5: Point2D(0.6, 0.6),
        },
        handedness="Left",
    )

    _call_annotate(frame, hands=HandsResult(hands=[hand]))

    fg_lines = _foreground_lines(
        line_calls, _HAND_LEFT_COLOR, _HAND_LINE_THICKNESS
    )
    # Only 0–5 is fully valid among listed connections that use these points.
    assert len(fg_lines) == 1
    fg_joints = _foreground_joints(
        circle_calls, _HAND_LEFT_COLOR, _HAND_JOINT_RADIUS
    )
    centers = {call["center"] for call in fg_joints}
    assert centers == {
        _normalized_to_pixel(Point2D(0.5, 0.5), _FRAME_W, _FRAME_H),
        _normalized_to_pixel(Point2D(0.6, 0.6), _FRAME_W, _FRAME_H),
    }


def test_nan_and_infinity_points_are_skipped(monkeypatch):
    line_calls, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    hand = HandLandmarks(
        points={
            0: Point2D(0.4, 0.4),
            1: Point2D(float("nan"), 0.4),
            2: Point2D(0.4, float("inf")),
            3: Point2D(float("-inf"), 0.4),
            5: Point2D(0.5, 0.5),
        },
        handedness="Right",
    )

    _call_annotate(frame, hands=HandsResult(hands=[hand]))

    fg_lines = _foreground_lines(
        line_calls, _HAND_RIGHT_COLOR, _HAND_LINE_THICKNESS
    )
    assert len(fg_lines) == 1  # 0–5 only
    fg_joints = _foreground_joints(
        circle_calls, _HAND_RIGHT_COLOR, _HAND_JOINT_RADIUS
    )
    assert len(fg_joints) == 2


def test_boundary_coordinates_map_to_valid_edge_pixels(monkeypatch):
    _, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    hand = HandLandmarks(
        points={
            0: Point2D(0.0, 0.0),
            1: Point2D(1.0, 1.0),
        },
        handedness="Unknown",
    )

    _call_annotate(frame, hands=HandsResult(hands=[hand]))

    fg_joints = _foreground_joints(circle_calls, YELLOW, _HAND_JOINT_RADIUS)
    centers = {call["center"] for call in fg_joints}
    assert centers == {(0, 0), (_FRAME_W - 1, _FRAME_H - 1)}


@pytest.mark.parametrize(
    ("handedness", "expected_color"),
    [
        ("Left", _HAND_LEFT_COLOR),
        ("left", _HAND_LEFT_COLOR),
        ("Right", _HAND_RIGHT_COLOR),
        ("RIGHT", _HAND_RIGHT_COLOR),
        ("Unknown", YELLOW),
        ("", YELLOW),
        ("SomethingElse", YELLOW),
    ],
)
def test_handedness_colors_are_deterministic(monkeypatch, handedness, expected_color):
    line_calls, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    hand = _full_hand(handedness=handedness)

    _call_annotate(frame, hands=HandsResult(hands=[hand]))

    fg_lines = _foreground_lines(line_calls, expected_color, _HAND_LINE_THICKNESS)
    fg_joints = _foreground_joints(circle_calls, expected_color, _HAND_JOINT_RADIUS)
    assert len(fg_lines) == 21
    assert len(fg_joints) == 21


def test_two_hands_render_independently(monkeypatch):
    line_calls, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    left = _full_hand(handedness="Left", origin_x=0.05, origin_y=0.05)
    right = _full_hand(handedness="Right", origin_x=0.55, origin_y=0.55)

    _call_annotate(frame, hands=HandsResult(hands=[left, right]))

    left_lines = _foreground_lines(
        line_calls, _HAND_LEFT_COLOR, _HAND_LINE_THICKNESS
    )
    right_lines = _foreground_lines(
        line_calls, _HAND_RIGHT_COLOR, _HAND_LINE_THICKNESS
    )
    left_joints = _foreground_joints(
        circle_calls, _HAND_LEFT_COLOR, _HAND_JOINT_RADIUS
    )
    right_joints = _foreground_joints(
        circle_calls, _HAND_RIGHT_COLOR, _HAND_JOINT_RADIUS
    )
    assert len(left_lines) == 21
    assert len(right_lines) == 21
    assert len(left_joints) == 21
    assert len(right_joints) == 21
    assert _endpoint_pair_set(left_lines).isdisjoint(_endpoint_pair_set(right_lines))


def test_prop_geometry_no_text_and_input_unchanged(monkeypatch):
    def fail_put_text(*args, **kwargs):
        pytest.fail("prop labels must not be rasterized into camera frames")

    monkeypatch.setattr(cv2, "putText", fail_put_text)

    rect_calls: list[dict] = []
    real_rectangle = cv2.rectangle
    real_circle = cv2.circle

    def capture_rectangle(img, pt1, pt2, color, thickness=1, *args, **kwargs):
        rect_calls.append(
            {
                "pt1": (int(pt1[0]), int(pt1[1])),
                "pt2": (int(pt2[0]), int(pt2[1])),
                "color": tuple(color),
                "thickness": thickness,
            }
        )
        return real_rectangle(img, pt1, pt2, color, thickness, *args, **kwargs)

    prop_center_calls: list[dict] = []

    def capture_circle(img, center, radius, color, thickness=1, *args, **kwargs):
        if tuple(color) == GREEN and radius == 4 and thickness == -1:
            prop_center_calls.append(
                {
                    "center": (int(center[0]), int(center[1])),
                    "radius": radius,
                    "color": tuple(color),
                }
            )
        return real_circle(img, center, radius, color, thickness, *args, **kwargs)

    monkeypatch.setattr(cv2, "rectangle", capture_rectangle)
    monkeypatch.setattr(cv2, "circle", capture_circle)

    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    original = frame.copy()
    prop = PropDetection(x1=20, y1=30, x2=40, y2=70, confidence=0.95)
    pose = _full_pose()
    hands = HandsResult(hands=[_full_hand(handedness="Unknown")])

    annotated = _call_annotate(
        frame,
        bottles=[prop],
        hands=hands,
        pose=pose,
        prop_label="Cocktail Shaker",
    )

    assert np.array_equal(frame, original)
    assert annotated is not frame
    assert rect_calls == [
        {
            "pt1": (20, 30),
            "pt2": (40, 70),
            "color": GREEN,
            "thickness": 2,
        }
    ]
    assert prop_center_calls == [
        {
            "center": (30, 50),
            "radius": 4,
            "color": GREEN,
        }
    ]

    # Prop-only pixel check avoids skeleton overlap at the bbox corner/center.
    prop_only = _call_annotate(
        np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8),
        bottles=[prop],
    )
    assert np.array_equal(prop_only[30, 20], np.array(GREEN, dtype=np.uint8))
    assert np.array_equal(prop_only[50, 30], np.array(GREEN, dtype=np.uint8))


def test_absent_pose_and_hands_do_not_crash(monkeypatch):
    def fail_put_text(*args, **kwargs):
        pytest.fail("text must not be rasterized into camera frames")

    monkeypatch.setattr(cv2, "putText", fail_put_text)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)

    out_none = _call_annotate(frame, bottles=None, hands=None, pose=None)
    assert out_none.shape == frame.shape

    out_empty_hands = _call_annotate(
        frame,
        bottles=[],
        hands=HandsResult(hands=[]),
        pose=PoseLandmarks(),
    )
    assert out_empty_hands.shape == frame.shape


def test_outline_calls_accompany_foreground_segments(monkeypatch):
    line_calls, circle_calls = _install_draw_capture(monkeypatch)
    frame = np.zeros((_FRAME_H, _FRAME_W, 3), dtype=np.uint8)
    pose = _full_pose()

    _call_annotate(frame, pose=pose)

    outline_lines = [
        call
        for call in line_calls
        if call["color"] == _OUTLINE_COLOR
        and call["thickness"] == _POSE_LINE_THICKNESS + 1
    ]
    fg_lines = _foreground_lines(line_calls, CYAN, _POSE_LINE_THICKNESS)
    assert len(outline_lines) == len(fg_lines) == 8

    outline_joints = [
        call
        for call in circle_calls
        if call["color"] == _OUTLINE_COLOR
        and call["radius"] == _POSE_JOINT_RADIUS + 1
    ]
    fg_joints = _foreground_joints(circle_calls, CYAN, _POSE_JOINT_RADIUS)
    assert len(outline_joints) == len(fg_joints) == 8


def test_normalized_to_pixel_boundary_mapping():
    assert _normalized_to_pixel(Point2D(0.0, 0.0), 100, 50) == (0, 0)
    assert _normalized_to_pixel(Point2D(1.0, 1.0), 100, 50) == (99, 49)
    assert math.isfinite(1.0)
