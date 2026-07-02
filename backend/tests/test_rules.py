import math

import pytest

from assessment.rules.common_checks import (
    check_bottle_visible,
    check_grip_angle,
    check_pinch_grip,
    check_shoulder_alignment,
    check_stall_proximity,
    detect_lateral_flip,
    detect_tap_pulse,
    detect_vertical_flip,
    update_bottle_history,
)
from assessment.rule_engine import evaluate_movement, movement_requires_hands
from assessment.scoring import SessionScorer
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D, PoseLandmarks


def _pose(
    left_shoulder_y: float = 0.3,
    right_shoulder_y: float = 0.3,
) -> PoseLandmarks:
    return PoseLandmarks(
        points={
            11: Point2D(0.4, left_shoulder_y),
            12: Point2D(0.6, right_shoulder_y),
            13: Point2D(0.35, 0.45),
            14: Point2D(0.65, 0.45),
            15: Point2D(0.35, 0.55),
            16: Point2D(0.65, 0.55),
            23: Point2D(0.42, 0.65),
            24: Point2D(0.58, 0.65),
            25: Point2D(0.4, 0.8),
            26: Point2D(0.6, 0.8),
            27: Point2D(0.38, 0.95),
            28: Point2D(0.62, 0.95),
        },
        visibility={i: 1.0 for i in range(11, 29)},
    )


def _bottle(cx: int = 320, cy: int = 240) -> BottleDetection:
    return BottleDetection(x1=cx - 20, y1=cy - 40, x2=cx + 20, y2=cy + 40, confidence=0.9)


def _hand_for_pinch() -> HandLandmarks:
    return HandLandmarks(
        points={
            0: Point2D(0.5, 0.55),
            4: Point2D(0.5, 0.5),
            8: Point2D(0.51, 0.5),
            9: Point2D(0.5, 0.52),
            12: Point2D(0.52, 0.54),
            16: Point2D(0.54, 0.56),
            20: Point2D(0.56, 0.58),
        },
        handedness="Right",
    )


def _hands(*handedness: str) -> HandsResult:
    hands = []
    for i, label in enumerate(handedness):
        offset = i * 0.2
        hands.append(
            HandLandmarks(
                points={
                    0: Point2D(0.4 + offset, 0.55),
                    4: Point2D(0.4 + offset, 0.5),
                    8: Point2D(0.41 + offset, 0.5),
                    9: Point2D(0.4 + offset, 0.52),
                    12: Point2D(0.42 + offset, 0.54),
                    16: Point2D(0.44 + offset, 0.56),
                    20: Point2D(0.46 + offset, 0.58),
                },
                handedness=label,
            )
        )
    return HandsResult(hands=hands)


def test_bottle_not_visible():
    result = check_bottle_visible(None)
    assert result is not None
    assert result.feedback_type == "error"


def test_shoulder_misalignment():
    pose = _pose(left_shoulder_y=0.3, right_shoulder_y=0.5)
    result = check_shoulder_alignment(pose)
    assert result is not None
    assert result.feedback_type == "warning"
    assert "shoulders" in result.feedback.lower()


def test_grip_angle_in_range():
    pose = _pose()
    result = check_grip_angle(
        pose,
        min_angle=140.0,
        max_angle=180.0,
        success_message="ok",
        fail_message="bad",
    )
    assert result.feedback_type == "positive"


def test_hand_stall_near_palm():
    bottle = _bottle()
    pose = _pose()
    pose.points[15] = Point2D(0.5, 0.5)
    wrist = pose.get(15)
    result = check_stall_proximity(bottle, wrist, success_message="stall ok")
    assert result.feedback_type == "positive"


def test_hand_stall_far_from_palm():
    bottle = _bottle(cx=100, cy=100)
    pose = _pose()
    wrist = pose.get(15)
    result = check_stall_proximity(bottle, wrist, success_message="stall ok")
    assert result.feedback_type == "warning"


def test_evaluate_hand_stall_movement():
    bottle = _bottle()
    pose = _pose()
    result, _, _ = evaluate_movement("Hand Stall", bottle, pose, None, None)
    assert result.feedback_type in ("positive", "warning")


def test_scorer_clamps():
    scorer = SessionScorer(window=10, base=70)
    for _ in range(15):
        scorer.record("error")
    assert scorer.score == 0


def test_movement_requires_hands():
    assert movement_requires_hands("Hand Stall") is True
    assert movement_requires_hands("Arm Stall") is False
    assert movement_requires_hands("Clip") is True
    assert movement_requires_hands("Switching") is True


def test_angle_helper():
    from assessment.rules.common_checks import _angle

    a = Point2D(0, 0)
    b = Point2D(1, 0)
    c = Point2D(1, 1)
    angle = _angle(a, b, c)
    assert math.isclose(angle, 90.0, abs_tol=1.0)


def test_pinch_grip_success():
    hand = _hand_for_pinch()
    bottle = _bottle()
    result = check_pinch_grip(hand, bottle)
    assert result.feedback_type == "positive"
    assert "clip" in result.feedback.lower()


def test_tap_pulse_detection():
    state, tapped = detect_tap_pulse(None, 0.2, threshold=0.1)
    assert tapped is False
    state, _ = detect_tap_pulse(state, 0.05, threshold=0.1)
    state, tapped = detect_tap_pulse(state, 0.2, threshold=0.1)
    assert tapped is True
    assert state["tap_count"] == 1


def test_vertical_flip_detection():
    state: dict = {"bottle_history": []}
    for y in [0.6, 0.55, 0.5, 0.55, 0.6]:
        bottle = BottleDetection(
            x1=300, y1=int(y * 480) - 20, x2=340, y2=int(y * 480) + 20, confidence=0.9
        )
        state = update_bottle_history(state, bottle, max_frames=12)
    assert detect_vertical_flip(state, threshold=0.03) is True


def test_lateral_flip_detection():
    state: dict = {"bottle_history": []}
    for x in [0.4, 0.45, 0.5, 0.45, 0.4]:
        bottle = BottleDetection(
            x1=int(x * 640) - 20, y1=220, x2=int(x * 640) + 20, y2=260, confidence=0.9
        )
        state = update_bottle_history(state, bottle, max_frames=12)
    assert detect_lateral_flip(state, threshold=0.03) is True


def _basket_hand() -> HandsResult:
    return HandsResult(
        hands=[
            HandLandmarks(
                points={
                    0: Point2D(0.5, 0.46),
                    4: Point2D(0.48, 0.48),
                    8: Point2D(0.52, 0.48),
                    9: Point2D(0.5, 0.48),
                    12: Point2D(0.52, 0.52),
                    16: Point2D(0.54, 0.54),
                    20: Point2D(0.56, 0.56),
                },
                handedness="Right",
            )
        ]
    )


@pytest.mark.parametrize(
    "movement,expected_fragment,hands_factory",
    [
        ("Clip", "clip", lambda: _hands("Right")),
        ("Tap", "tap", lambda: _hands("Right")),
        ("Basket", "basket", _basket_hand),
        ("Switching", "hand", lambda: _hands("Left", "Right")),
        ("Front Flip", "flip", lambda: _hands("Right")),
        ("Side Flip", "flip", lambda: _hands("Right")),
        ("Quick Chest Pass", "chest", lambda: _hands("Left", "Right")),
        ("Staggered Switch", "center", lambda: _hands("Left", "Right")),
        ("Elbow Tap", "elbow", lambda: None),
    ],
)
def test_movements_not_coming_soon(movement, expected_fragment, hands_factory):
    bottle = _bottle()
    pose = _pose()
    hands = hands_factory()
    result, _, _ = evaluate_movement(movement, bottle, pose, hands, None)
    assert "coming soon" not in result.feedback.lower()
    assert expected_fragment in result.feedback.lower()


def test_posture_only_shoulder_warning():
    pose = _pose(left_shoulder_y=0.3, right_shoulder_y=0.5)
    result, _, _ = evaluate_movement(
        "Hand Stall",
        None,
        pose,
        _hands("Right"),
        None,
        bottle_detection_enabled=False,
    )
    assert result.feedback_type == "warning"
    assert "shoulder" in result.feedback.lower()


def test_posture_only_stable_feedback():
    pose = _pose()
    result, _, _ = evaluate_movement(
        "Tap",
        None,
        pose,
        _hands("Right"),
        None,
        bottle_detection_enabled=False,
    )
    assert result.feedback_type == "positive"
    assert "posture" in result.feedback.lower()


def test_posture_only_requires_hands():
    pose = _pose()
    result, _, _ = evaluate_movement(
        "Hand Stall",
        None,
        pose,
        None,
        None,
        bottle_detection_enabled=False,
    )
    assert result.feedback_type == "warning"
    assert "hand" in result.feedback.lower()
