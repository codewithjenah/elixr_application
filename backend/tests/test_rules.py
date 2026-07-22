import numpy as np
import pytest

from api import websocket as websocket_api
from vision import hands_detector as hands_detector_module

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


def _grip_hand(
    *,
    wrist: Point2D,
    middle_mcp: Point2D,
    fingertips: tuple[Point2D, Point2D, Point2D, Point2D],
    thumb_tip: Point2D | None = None,
    handedness: str = "Right",
) -> HandLandmarks:
    points = {0: wrist, 9: middle_mcp}
    points.update(
        {
            index: point
            for index, point in zip((8, 12, 16, 20), fingertips)
        }
    )
    if thumb_tip is not None:
        points[4] = thumb_tip
    return HandLandmarks(points=points, handedness=handedness)


def _evaluate_normal_grip(hand: HandLandmarks):
    result, _, _ = evaluate_movement(
        "Normal Grip",
        _bottle(),
        None,
        HandsResult(hands=[hand]),
        None,
    )
    return result


class _StubHandsDetector(hands_detector_module.HandsDetector):
    def __init__(
        self,
        *,
        rotated_fallback: bool,
        primary_result,
        fallback_result,
    ):
        self._rotated_fallback = rotated_fallback
        self._primary_result = primary_result
        self._fallback_result = fallback_result
        self.fallback_calls = 0

    def _detect_primary(self, frame):
        return self._primary_result

    def _detect_rotated(self, frame):
        self.fallback_calls += 1
        return self._fallback_result


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


@pytest.mark.parametrize(
    "hand",
    [
        _grip_hand(
            wrist=Point2D(0.43, 0.49),
            middle_mcp=Point2D(0.47, 0.43),
            fingertips=(
                Point2D(0.48, 0.44),
                Point2D(0.50, 0.45),
                Point2D(0.52, 0.47),
                Point2D(0.54, 0.48),
            ),
            handedness="Right",
        ),
        _grip_hand(
            wrist=Point2D(0.57, 0.49),
            middle_mcp=Point2D(0.53, 0.43),
            fingertips=(
                Point2D(0.52, 0.44),
                Point2D(0.50, 0.45),
                Point2D(0.48, 0.47),
                Point2D(0.46, 0.48),
            ),
            handedness="Left",
        ),
    ],
    ids=["right-side", "left-side"],
)
def test_normal_grip_accepts_reference_like_full_wrap(hand):
    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback == (
        "Bottle held securely with a full overhand neck grip."
    )


def test_normal_grip_rejects_hand_around_bottle_body():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.60),
        middle_mcp=Point2D(0.47, 0.54),
        fingertips=(
            Point2D(0.48, 0.55),
            Point2D(0.50, 0.56),
            Point2D(0.52, 0.58),
            Point2D(0.54, 0.59),
        ),
    )

    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == "Move your hand to the upper bottle neck."


def test_normal_grip_rejects_reverse_wrist_orientation():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.43),
        middle_mcp=Point2D(0.47, 0.49),
        fingertips=(
            Point2D(0.48, 0.44),
            Point2D(0.50, 0.45),
            Point2D(0.52, 0.47),
            Point2D(0.54, 0.48),
        ),
    )

    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == "Rotate your wrist into an overhand grip."


def test_normal_grip_rejects_two_finger_pinch():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.49),
        middle_mcp=Point2D(0.47, 0.43),
        thumb_tip=Point2D(0.49, 0.44),
        fingertips=(
            Point2D(0.50, 0.44),
            Point2D(0.70, 0.65),
            Point2D(0.72, 0.70),
            Point2D(0.75, 0.75),
        ),
    )

    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Wrap at least three fingers around the bottle neck."
    )


def test_normal_grip_handles_missing_palm_landmarks():
    hand = HandLandmarks(
        points={0: Point2D(0.43, 0.49)},
        handedness="Right",
    )

    result = _evaluate_normal_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"
    assert result.feedback == (
        "Keep your full hand visible around the bottle neck."
    )


def test_clockwise_point_is_restored_to_original_coordinates():
    restored = hands_detector_module._clockwise_point_to_original(
        Point2D(0.20, 0.25)
    )

    assert restored.x == pytest.approx(0.25)
    assert restored.y == pytest.approx(0.80)


def test_hand_detector_uses_rotated_fallback_after_primary_miss():
    expected = _hands_near()
    detector = _StubHandsDetector(
        rotated_fallback=True,
        primary_result=None,
        fallback_result=expected,
    )

    result = detector.detect(np.zeros((2, 3, 3), dtype=np.uint8))

    assert result is expected
    assert detector.fallback_calls == 1


def test_hand_detector_does_not_use_rotated_fallback_after_primary_hit():
    expected = _hands_near()
    detector = _StubHandsDetector(
        rotated_fallback=True,
        primary_result=expected,
        fallback_result=None,
    )

    result = detector.detect(np.zeros((2, 3, 3), dtype=np.uint8))

    assert result is expected
    assert detector.fallback_calls == 0


def test_hand_detector_skips_rotated_fallback_when_disabled():
    detector = _StubHandsDetector(
        rotated_fallback=False,
        primary_result=None,
        fallback_result=_hands_near(),
    )

    result = detector.detect(np.zeros((2, 3, 3), dtype=np.uint8))

    assert result is None
    assert detector.fallback_calls == 0


def test_only_normal_grip_session_enables_rotated_fallback(monkeypatch):
    fallback_settings = []

    class RecordingHandsDetector:
        def __init__(self, *, rotated_fallback: bool = False):
            fallback_settings.append(rotated_fallback)

    monkeypatch.setattr(
        websocket_api,
        "HandsDetector",
        RecordingHandsDetector,
    )

    websocket_api.VisionSession("Normal Grip")
    websocket_api.VisionSession("Reverse Grip")

    assert fallback_settings == [True, False]


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
