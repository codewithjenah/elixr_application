"""Tests for the 'Bottle in a tin' movement rule and its registration."""

from __future__ import annotations

from config import MOVEMENT_CONFIG
from assessment.rule_engine import (
    evaluate_movement,
    movement_requires_hands,
    movement_requires_pose,
)
from assessment.rules import bottle_in_a_tin
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D

_FRAME_W = 640
_FRAME_H = 480

# Shaker spans x=[220,420] (width 200, aspect ratio 200/50=4 >= 1.5 horizontal),
# y=[300,350] (height 50). Center: x=320 (0.5 normalized), top y=300 (0.625).
_SHAKER_X1, _SHAKER_Y1, _SHAKER_X2, _SHAKER_Y2 = 220, 300, 420, 350


def _shaker(x1: int = _SHAKER_X1, x2: int = _SHAKER_X2) -> BottleDetection:
    return BottleDetection(x1=x1, y1=_SHAKER_Y1, x2=x2, y2=_SHAKER_Y2, confidence=0.9)


def _bottle(
    center_x: int = 320,
    *,
    width: int = 40,
    height: int = 100,
    base_y: int = 302,
) -> BottleDetection:
    """Upright bottle (height/width=2.5 by default) resting on the shaker top."""
    half = width // 2
    return BottleDetection(
        x1=center_x - half,
        y1=base_y - height,
        x2=center_x + half,
        y2=base_y,
        confidence=0.9,
    )


def _grip_hand(x: float = 0.5, y: float = 0.703) -> HandLandmarks:
    # palm_center() averages points 0 (wrist) and 9 (middle MCP); placing both
    # at the target puts the palm exactly there.
    return HandLandmarks(points={0: Point2D(x, y), 9: Point2D(x, y)})


def _hands_at(x: float = 0.5, y: float = 0.703) -> HandsResult:
    return HandsResult(hands=[_grip_hand(x, y)])


def _evaluate(bottle, shaker, hands, movement_state=None):
    return bottle_in_a_tin.evaluate(bottle, shaker, None, hands, None, movement_state)


# --- A. Visibility -----------------------------------------------------


def test_no_props_reports_both_missing():
    result, _, _ = _evaluate(None, None, _hands_at())
    assert result.feedback_type == "error"
    assert "bottle and cocktail shaker" in result.feedback.lower()
    assert result.feedback_code == "both_props_not_detected"


def test_missing_bottle_reports_bottle():
    result, _, _ = _evaluate(None, _shaker(), _hands_at())
    assert result.feedback_type == "error"
    assert "bottle" in result.feedback.lower()
    assert "above the shaker" in result.feedback.lower()
    assert result.feedback_code == "bottle_not_detected"


def test_missing_shaker_reports_shaker():
    result, _, _ = _evaluate(_bottle(), None, _hands_at())
    assert result.feedback_type == "error"
    assert "shaker" in result.feedback.lower()
    assert "under the bottle" in result.feedback.lower()
    assert result.feedback_code == "shaker_not_detected"


# --- B. Orientation ------------------------------------------------------


def test_bottle_not_upright_warns():
    tilted_bottle = _bottle(width=60, height=50)
    result, _, _ = _evaluate(tilted_bottle, _shaker(), _hands_at())
    assert result.feedback_type == "warning"
    assert "upright" in result.feedback.lower()
    assert result.feedback_code == "prop_not_upright"


def test_shaker_not_horizontal_warns():
    upright_shaker = BottleDetection(x1=280, y1=250, x2=340, y2=400, confidence=0.9)
    result, _, _ = _evaluate(_bottle(), upright_shaker, _hands_at())
    assert result.feedback_type == "warning"
    assert "horizontally" in result.feedback.lower()
    assert result.feedback_code == "shaker_not_horizontal"


# --- C. Contact geometry ---------------------------------------------------


def test_bottle_outside_shaker_span_warns():
    off_center_bottle = _bottle(center_x=30)  # far left of shaker span
    result, _, _ = _evaluate(off_center_bottle, _shaker(), _hands_at())
    assert result.feedback_type == "warning"
    assert "center the bottle" in result.feedback.lower()


def test_bottle_floating_above_shaker_warns():
    floating_bottle = _bottle(base_y=250)  # 50px above shaker top (300)
    result, _, _ = _evaluate(floating_bottle, _shaker(), _hands_at())
    assert result.feedback_type == "warning"
    assert "place the bottle" in result.feedback.lower()


def test_bottle_overlapping_below_shaker_top_warns():
    sunken_bottle = _bottle(base_y=345)  # deep inside/below the shaker top
    result, _, _ = _evaluate(sunken_bottle, _shaker(), _hands_at())
    assert result.feedback_type == "warning"
    assert "place the bottle" in result.feedback.lower()


# --- D. Hand support -------------------------------------------------------


def test_missing_hand_is_uncertain_visibility():
    result, _, _ = _evaluate(_bottle(), _shaker(), None)
    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"
    assert result.feedback_code == "hand_not_visible"
    assert result.criterion_results is None
    assert result.feedback == "Keep your supporting hand visible."


def test_hand_too_far_from_shaker_is_wrong_support():
    far_hands = _hands_at(x=0.05, y=0.05)
    result, _, _ = _evaluate(_bottle(), _shaker(), far_hands)
    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback_code == "hand_not_supporting_shaker"
    assert result.criterion_results is not None
    assert result.feedback == "Support the shaker with your hand."


# --- E. Stability -----------------------------------------------------------


def test_correct_geometry_wobbling_bottle_eventually_reports_unstable():
    state = None
    result = None
    positions = [290, 350, 290, 350, 290]
    for center_x in positions:
        result, _, state = _evaluate(_bottle(center_x=center_x), _shaker(), _hands_at(), state)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert "steady" in result.feedback.lower()


def test_stable_correct_geometry_returns_positive():
    state = None
    result = None
    for _ in range(5):
        result, _, state = _evaluate(_bottle(), _shaker(), _hands_at(), state)

    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback == "Bottle in a tin locked in."


# --- Registration and routing ------------------------------------------------


def test_movement_is_registered_as_hard():
    assert MOVEMENT_CONFIG["Bottle in a tin"]["difficulty"] == "Hard"


def test_movement_requires_hands_but_not_pose():
    assert movement_requires_hands("Bottle in a tin") is True
    assert movement_requires_pose("Bottle in a tin") is False


def test_movement_requires_bottle_and_shaker_prop_type():
    assert MOVEMENT_CONFIG["Bottle in a tin"]["required_prop_type"] == "bottle_and_shaker"


def test_rule_engine_routes_bottle_in_a_tin_with_separate_bottle_and_shaker():
    result, _, _ = evaluate_movement(
        "Bottle in a tin",
        None,
        None,
        _hands_at(),
        None,
        None,
        bottle_detection_enabled=True,
        bottles=[_bottle()],
        shakers=[_shaker()],
        prop_type="bottle_and_shaker",
        prop_label="Bottle + Cocktail Shaker",
    )
    # First call: stability history has only 1 sample so both report stable.
    assert result.feedback_type == "positive"


def test_rule_engine_reports_missing_shaker_when_shakers_list_empty():
    result, _, _ = evaluate_movement(
        "Bottle in a tin",
        None,
        None,
        _hands_at(),
        None,
        None,
        bottle_detection_enabled=True,
        bottles=[_bottle()],
        shakers=[],
        prop_type="bottle_and_shaker",
        prop_label="Bottle + Cocktail Shaker",
    )
    assert result.feedback_type == "error"
    assert "shaker" in result.feedback.lower()
