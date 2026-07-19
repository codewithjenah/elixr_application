import pytest

from assessment.rules.common_checks import (
    check_bottle_visible,
    check_hand_bottle_proximity,
    check_hands_visible,
    check_pinch_grip,
    check_stall_proximity,
    detect_tap_pulse,
    track_bottle_stability,
)
from assessment.rule_engine import evaluate_movement, movement_requires_hands
from assessment.scoring import SessionScorer
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D


def _bottle(cx: int = 320, cy: int = 240) -> BottleDetection:
    return BottleDetection(x1=cx - 20, y1=cy - 40, x2=cx + 20, y2=cy + 40, confidence=0.9)


def _hand_near(x: float = 0.5, y: float = 0.5, handedness: str = "Right") -> HandLandmarks:
    return HandLandmarks(
        points={
            0: Point2D(x, y + 0.02),
            4: Point2D(x, y),
            8: Point2D(x + 0.01, y),
            9: Point2D(x, y - 0.02),
            12: Point2D(x + 0.02, y + 0.02),
            16: Point2D(x + 0.04, y + 0.04),
            20: Point2D(x + 0.06, y + 0.06),
        },
        handedness=handedness,
    )


def _hands_near() -> HandsResult:
    return HandsResult(hands=[_hand_near()])


def test_bottle_not_visible():
    result = check_bottle_visible(None)
    assert result is not None
    assert result.feedback_type == "error"


def test_hands_not_visible():
    assert check_hands_visible(None) is not None
    assert check_hands_visible(HandsResult(hands=[])) is not None
    assert check_hands_visible(_hands_near()) is None


def test_hand_bottle_proximity_near():
    result = check_hand_bottle_proximity(_bottle(), Point2D(0.5, 0.5))
    assert result.feedback_type == "positive"


def test_hand_bottle_proximity_far():
    result = check_hand_bottle_proximity(_bottle(), Point2D(0.1, 0.1))
    assert result.feedback_type == "warning"


def test_stall_proximity_near():
    result = check_stall_proximity(_bottle(), Point2D(0.5, 0.5), success_message="stall ok")
    assert result.feedback_type == "positive"


def test_stall_proximity_far():
    result = check_stall_proximity(_bottle(cx=100, cy=100), Point2D(0.5, 0.5), success_message="ok")
    assert result.feedback_type == "warning"


def test_bottle_stability():
    state = None
    stable = True
    for _ in range(6):
        state, stable = track_bottle_stability(state, _bottle())
    assert stable is True


def test_bottle_instability():
    state = None
    stable = True
    for i in range(6):
        state, stable = track_bottle_stability(state, _bottle(cx=100 + i * 60, cy=240))
    assert stable is False


def test_pinch_grip_success():
    hand = HandLandmarks(
        points={0: Point2D(0.5, 0.55), 4: Point2D(0.5, 0.5), 8: Point2D(0.51, 0.5), 9: Point2D(0.5, 0.52)},
        handedness="Right",
    )
    result = check_pinch_grip(hand, _bottle(), success_message="Good bartender's grip on the neck.")
    assert result.feedback_type == "positive"


def test_tap_pulse_detection():
    state, tapped = detect_tap_pulse(None, 0.2, threshold=0.1)
    assert tapped is False
    state, _ = detect_tap_pulse(state, 0.05, threshold=0.1)
    state, tapped = detect_tap_pulse(state, 0.2, threshold=0.1)
    assert tapped is True
    assert state["tap_count"] == 1


def test_scorer_clamps():
    scorer = SessionScorer(window=10, base=70)
    for _ in range(15):
        scorer.record("error")
    assert scorer.score == 0


def test_movement_requires_hands():
    assert movement_requires_hands("Hand Stall") is True
    assert movement_requires_hands("Arm Stall") is True
    assert movement_requires_hands("Elbow Stall") is True
    assert movement_requires_hands("Normal Grip") is True


@pytest.mark.parametrize(
    "movement",
    [
        "Normal Grip",
        "Bartender's Grip",
        "Reverse Grip",
        "Hand Stall",
        "Arm Stall",
        "Elbow Stall",
        "Tap",
        "Basket",
    ],
)
def test_evaluate_movement_runs(movement):
    result, _, _ = evaluate_movement(movement, _bottle(), None, _hands_near(), None)
    assert "coming soon" not in result.feedback.lower()
    assert result.feedback_type in ("positive", "warning", "error")


def test_evaluate_movement_no_bottle():
    result, _, _ = evaluate_movement("Hand Stall", None, None, _hands_near(), None)
    assert result.feedback_type == "error"


def test_posture_only_requires_hands():
    result, _, _ = evaluate_movement(
        "Hand Stall",
        None,
        None,
        None,
        None,
        bottle_detection_enabled=False,
    )
    assert result.feedback_type == "warning"
    assert "hand" in result.feedback.lower()


def test_posture_only_positive():
    result, _, _ = evaluate_movement(
        "Tap",
        None,
        None,
        _hands_near(),
        None,
        bottle_detection_enabled=False,
    )
    assert result.feedback_type == "positive"
