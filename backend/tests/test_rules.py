import numpy as np
import pytest

from api import websocket as websocket_api
from vision import hands_detector as hands_detector_module

from config import (
    DOUBLE_HAND_MAX_HEIGHT_DIFFERENCE,
    DOUBLE_HAND_MAX_SEPARATION,
    DOUBLE_HAND_MIN_SEPARATION,
    DOUBLE_HAND_STALL_PROXIMITY,
    DOUBLE_HAND_TARGET_ABOVE_OFFSET,
    SHOULDER_ABOVE_OFFSET,
    SHOULDER_STALL_PROXIMITY,
    STALL_STABILITY_THRESHOLD,
    UPPER_FOREARM_RATIO,
    UPPER_FOREARM_STALL_PROXIMITY,
)
from assessment.rules.common_checks import (
    check_bottle_visible,
    check_hand_bottle_proximity,
    check_hands_visible,
    check_pinch_grip,
    check_stall_proximity,
    pose_shoulder_point,
    pose_upper_forearm_point,
    track_bottle_stability,
)
from assessment.rule_engine import evaluate_movement, movement_requires_hands
from assessment.scoring import SessionScorer
from vision.types import BottleDetection, HandLandmarks, HandsResult, Point2D, PoseLandmarks


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

def _evaluate_reverse_grip(hand: HandLandmarks):
    result, _, _ = evaluate_movement(
        "Reverse Grip",
        _bottle(),
        None,
        HandsResult(hands=[hand]),
        None,
    )
    return result


def _bartender_hand(
    *,
    mirrored: bool = False,
    x_offset: float = 0.0,
    y_offset: float = 0.0,
    overrides: dict[int, Point2D] | None = None,
    missing: tuple[int, ...] = (),
) -> HandLandmarks:
    points = {
        0: Point2D(0.32, 0.48),
        1: Point2D(0.37, 0.47),
        2: Point2D(0.40, 0.46),
        3: Point2D(0.44, 0.455),
        4: Point2D(0.465, 0.455),
        5: Point2D(0.45, 0.45),
        6: Point2D(0.478, 0.453),
        7: Point2D(0.507, 0.456),
        8: Point2D(0.535, 0.46),
        9: Point2D(0.49, 0.47),
        10: Point2D(0.495, 0.475),
        11: Point2D(0.505, 0.482),
        12: Point2D(0.51, 0.49),
        13: Point2D(0.485, 0.485),
        14: Point2D(0.50, 0.495),
        15: Point2D(0.51, 0.503),
        16: Point2D(0.52, 0.51),
        17: Point2D(0.48, 0.50),
        18: Point2D(0.49, 0.51),
        19: Point2D(0.51, 0.52),
        20: Point2D(0.53, 0.53),
    }

    if mirrored:
        points = {
            index: Point2D(1.0 - point.x, point.y)
            for index, point in points.items()
        }

    points = {
        index: Point2D(
            point.x + x_offset,
            point.y + y_offset,
        )
        for index, point in points.items()
    }

    if overrides:
        points.update(overrides)
    for index in missing:
        points.pop(index, None)

    return HandLandmarks(
        points=points,
        handedness="Left" if mirrored else "Right",
    )


def _evaluate_bartenders_grip(hand: HandLandmarks):
    result, _, _ = evaluate_movement(
        "Bartender's Grip",
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
        self._bartender_roi_fallback = False
        self._max_num_hands = 2
        self._primary_result = primary_result
        self._fallback_result = fallback_result
        self.fallback_calls = 0

    def _detect_primary(self, frame):
        return self._primary_result

    def _detect_rotated(self, frame):
        self.fallback_calls += 1
        return self._fallback_result


class _StubBartenderHandsDetector(
    hands_detector_module.HandsDetector
):
    def __init__(
        self,
        *,
        primary_result,
        fallback_result,
        max_num_hands: int = 2,
    ):
        self._rotated_fallback = False
        self._bartender_roi_fallback = True
        self._max_num_hands = max_num_hands
        self._primary_result = primary_result
        self._fallback_result = fallback_result
        self.fallback_calls = 0

    def _detect_primary(self, frame):
        return self._primary_result

    def _detect_bartender_roi(self, frame, bottle):
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


def test_scorer_clamps():
    scorer = SessionScorer(window=10, base=70)
    for _ in range(15):
        scorer.record("error")
    assert scorer.score == 0


@pytest.mark.parametrize(
    "hand",
    [
        _bartender_hand(),
        _bartender_hand(mirrored=True),
    ],
    ids=["right-side", "left-side"],
)
def test_bartenders_grip_accepts_reference_like_side_hold(hand):
    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback == (
        "Good bartender's grip on the neck and shoulder."
    )


def test_bartenders_grip_prefers_in_zone_recovered_hand_over_nearer_outsider():
    valid_recovered_hand = _bartender_hand(x_offset=0.032)
    unrelated_primary_hand = _bartender_hand(y_offset=0.0601667)

    result, _, _ = evaluate_movement(
        "Bartender's Grip",
        _bottle(),
        None,
        HandsResult(hands=[valid_recovered_hand, unrelated_primary_hand]),
        None,
    )

    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback == (
        "Good bartender's grip on the neck and shoulder."
    )


def test_bartenders_grip_rejects_body_hold():
    result = _evaluate_bartenders_grip(
        _bartender_hand(y_offset=0.10)
    )

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Grip the bottle at the upper neck and shoulder."
    )


def test_bartenders_grip_rejects_off_bottle_pinch():
    result = _evaluate_bartenders_grip(
        _bartender_hand(x_offset=0.10)
    )

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Grip the bottle at the upper neck and shoulder."
    )


def test_bartenders_grip_rejects_overly_open_thumb_index_control():
    hand = _bartender_hand(
        overrides={
            4: Point2D(0.43, 0.455),
            7: Point2D(0.53, 0.456),
            8: Point2D(0.57, 0.46),
        }
    )

    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Secure the neck between your thumb and index finger."
    )


def test_bartenders_grip_rejects_normal_clenched_index():
    hand = _bartender_hand(
        overrides={
            4: Point2D(0.49, 0.455),
            6: Point2D(0.50, 0.45),
            7: Point2D(0.48, 0.46),
            8: Point2D(0.49, 0.455),
        }
    )

    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Extend your index finger along the bottle neck."
    )


def test_bartenders_grip_rejects_vertical_normal_grip():
    hand = _bartender_hand(
        overrides={
            0: Point2D(0.49, 0.56),
            4: Point2D(0.49, 0.455),
            8: Point2D(0.51, 0.46),
            9: Point2D(0.50, 0.47),
        }
    )

    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Turn your hand sideways for a bartender's grip."
    )


def test_bartenders_grip_rejects_sideways_underhand_hold():
    hand = _bartender_hand(
        overrides={
            0: Point2D(0.32, 0.54),
            9: Point2D(0.49, 0.52),
        }
    )

    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Raise your palm above the bottle center for a bartender's grip."
    )


def test_bartenders_grip_requires_two_other_fingers_on_shoulder():
    hand = _bartender_hand(
        overrides={
            12: Point2D(0.70, 0.70),
            16: Point2D(0.72, 0.72),
        }
    )

    result = _evaluate_bartenders_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Wrap your other fingers around the bottle shoulder."
    )


@pytest.mark.parametrize(
    "missing",
    [
        (4,),
        (6,),
        (16, 20),
    ],
    ids=["thumb", "index-chain", "other-fingertips"],
)
def test_bartenders_grip_handles_incomplete_landmarks(missing):
    result = _evaluate_bartenders_grip(
        _bartender_hand(missing=missing)
    )

    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"
    assert result.feedback == "Keep your full gripping hand visible."


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


@pytest.mark.parametrize(
    "hand",
    [
        _grip_hand(
            wrist=Point2D(0.43, 0.43),
            middle_mcp=Point2D(0.47, 0.49),
            thumb_tip=Point2D(0.46, 0.49),
            fingertips=(
                Point2D(0.48, 0.48),
                Point2D(0.50, 0.46),
                Point2D(0.52, 0.44),
                Point2D(0.54, 0.42),
            ),
            handedness="Right",
        ),
        _grip_hand(
            wrist=Point2D(0.57, 0.43),
            middle_mcp=Point2D(0.53, 0.49),
            thumb_tip=Point2D(0.54, 0.49),
            fingertips=(
                Point2D(0.52, 0.48),
                Point2D(0.50, 0.46),
                Point2D(0.48, 0.44),
                Point2D(0.46, 0.42),
            ),
            handedness="Left",
        ),
    ],
    ids=["right-side", "left-side"],
)
def test_reverse_grip_accepts_reference_like_full_wrap(hand):
    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback == (
        "Bottle held securely with a full reverse neck grip."
    )


def test_reverse_grip_rejects_hand_around_bottle_body():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.58),
        middle_mcp=Point2D(0.47, 0.64),
        thumb_tip=Point2D(0.46, 0.64),
        fingertips=(
            Point2D(0.48, 0.63),
            Point2D(0.50, 0.61),
            Point2D(0.52, 0.59),
            Point2D(0.54, 0.57),
        ),
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == "Move your hand to the upper bottle neck."


def test_reverse_grip_rejects_normal_overhand_wrap():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.49),
        middle_mcp=Point2D(0.47, 0.43),
        thumb_tip=Point2D(0.46, 0.42),
        fingertips=(
            Point2D(0.48, 0.44),
            Point2D(0.50, 0.45),
            Point2D(0.52, 0.47),
            Point2D(0.54, 0.48),
        ),
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == "Rotate your wrist into a reverse grip."


def test_reverse_grip_rejects_wrong_pinky_thumb_order():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.43),
        middle_mcp=Point2D(0.47, 0.49),
        thumb_tip=Point2D(0.46, 0.42),
        fingertips=(
            Point2D(0.48, 0.44),
            Point2D(0.50, 0.45),
            Point2D(0.52, 0.47),
            Point2D(0.54, 0.48),
        ),
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Point your pinky toward the bottle mouth and thumb toward the base."
    )


def test_reverse_grip_rejects_two_finger_pinch():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.43),
        middle_mcp=Point2D(0.47, 0.49),
        thumb_tip=Point2D(0.46, 0.49),
        fingertips=(
            Point2D(0.48, 0.48),
            Point2D(0.70, 0.65),
            Point2D(0.72, 0.70),
            Point2D(0.54, 0.42),
        ),
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unstable"
    assert result.feedback == (
        "Wrap at least three fingers around the bottle neck."
    )


def test_reverse_grip_handles_missing_palm_landmarks():
    hand = HandLandmarks(
        points={0: Point2D(0.43, 0.43)},
        handedness="Right",
    )

    result = _evaluate_reverse_grip(hand)

    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"
    assert result.feedback == (
        "Keep your full hand visible around the bottle neck."
    )


def test_reverse_grip_handles_missing_pinky_or_thumb():
    hand = _grip_hand(
        wrist=Point2D(0.43, 0.43),
        middle_mcp=Point2D(0.47, 0.49),
        fingertips=(
            Point2D(0.48, 0.48),
            Point2D(0.50, 0.46),
            Point2D(0.52, 0.44),
            Point2D(0.54, 0.42),
        ),
    )

    result = _evaluate_reverse_grip(hand)

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


def test_counterclockwise_crop_point_is_restored_to_frame():
    restored = (
        hands_detector_module
        ._counterclockwise_crop_point_to_frame(
            Point2D(0.20, 0.25),
            (100, 50, 300, 250),
            frame_width=640,
            frame_height=480,
        )
    )

    assert restored.x == pytest.approx(0.390625)
    assert restored.y == pytest.approx(0.1875)


def test_bartender_roi_skips_near_primary_hand():
    expected = _hands_near()
    detector = _StubBartenderHandsDetector(
        primary_result=expected,
        fallback_result=None,
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        _bottle(),
    )

    assert result is expected
    assert detector.fallback_calls == 0


def test_bartender_roi_runs_after_primary_miss():
    expected = _hands_near()
    detector = _StubBartenderHandsDetector(
        primary_result=None,
        fallback_result=expected,
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        _bottle(),
    )

    assert result is not None
    assert result.hands[0] is expected.hands[0]
    assert detector.fallback_calls == 1


def test_bartender_roi_prioritizes_recovery_and_caps_hands():
    primary = HandsResult(
        hands=[
            _hand_near(0.80, 0.80),
            _hand_near(0.20, 0.80),
        ]
    )
    recovered = _hands_near()
    detector = _StubBartenderHandsDetector(
        primary_result=primary,
        fallback_result=recovered,
        max_num_hands=2,
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        _bottle(),
    )

    assert result is not None
    assert len(result.hands) == 2
    assert result.hands[0] is recovered.hands[0]
    assert result.hands[1] is primary.hands[0]
    assert detector.fallback_calls == 1


def test_bartender_roi_skips_fallback_without_bottle():
    primary = HandsResult(hands=[_hand_near(0.80, 0.80)])
    detector = _StubBartenderHandsDetector(
        primary_result=primary,
        fallback_result=_hands_near(),
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        None,
    )

    assert result is primary
    assert detector.fallback_calls == 0


def test_bartender_roi_miss_preserves_primary_result():
    primary = HandsResult(hands=[_hand_near(0.80, 0.80)])
    detector = _StubBartenderHandsDetector(
        primary_result=primary,
        fallback_result=None,
    )

    result = detector.detect(
        np.zeros((480, 640, 3), dtype=np.uint8),
        _bottle(),
    )

    assert result is primary
    assert detector.fallback_calls == 1


def test_bartender_crop_rejects_zero_width_bottle():
    invalid = BottleDetection(
        x1=100,
        y1=100,
        x2=100,
        y2=200,
        confidence=0.9,
    )

    assert (
        hands_detector_module._bartender_crop_bounds(
            invalid,
            frame_width=640,
            frame_height=480,
        )
        is None
    )


def test_session_enables_only_its_grip_fallback(monkeypatch):
    fallback_settings = []

    class RecordingHandsDetector:
        def __init__(
            self,
            *,
            rotated_fallback: bool = False,
            bartender_roi_fallback: bool = False,
        ):
            fallback_settings.append(
                (rotated_fallback, bartender_roi_fallback)
            )

    monkeypatch.setattr(
        websocket_api,
        "HandsDetector",
        RecordingHandsDetector,
    )

    websocket_api.VisionSession("Normal Grip")
    websocket_api.VisionSession("Bartender's Grip")
    websocket_api.VisionSession("Reverse Grip")

    assert fallback_settings == [
        (True, False),
        (False, True),
        (False, False),
    ]


def test_session_passes_primary_bottle_to_hand_detector(
    monkeypatch,
):
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    bottle = _bottle()
    seen_bottles = []

    class StubCamera:
        def read(self):
            return frame

        def release(self):
            pass

    class StubBottleDetector:
        def __init__(self, *, enabled: bool):
            self.enabled = enabled

        def ensure_ready(self):
            pass

        def detect(self, current_frame):
            assert current_frame is frame
            return [bottle]

    class StubHandsDetector:
        def __init__(self, **kwargs):
            pass

        def detect(self, current_frame, bottle=None):
            assert current_frame is frame
            seen_bottles.append(bottle)
            return _hands_near()

        def close(self):
            pass

    monkeypatch.setattr(
        websocket_api,
        "CameraCapture",
        StubCamera,
    )
    monkeypatch.setattr(
        websocket_api,
        "BottleDetector",
        StubBottleDetector,
    )
    monkeypatch.setattr(
        websocket_api,
        "HandsDetector",
        StubHandsDetector,
    )
    monkeypatch.setattr(
        websocket_api,
        "annotate_frame",
        lambda current_frame, *args, **kwargs: current_frame,
    )

    session = websocket_api.VisionSession("Bartender's Grip")
    try:
        message = session.process_frame()
    finally:
        session.close()

    assert message is not None
    assert seen_bottles == [bottle]


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
        "Upper Forearm Stall",
        "Shoulder Stall",
        "Double Hand Stall",
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
        "Double Hand Stall",
        None,
        None,
        HandsResult(hands=[_hand_near(0.35, 0.5, "Left"), _hand_near(0.65, 0.5, "Right")]),
        None,
        bottle_detection_enabled=False,
    )
    assert result.feedback_type == "positive"
    assert "bottle detection" in result.feedback.lower()
    assert "double hand stall" in result.feedback.lower()


def _pose_from_points(points: dict[int, Point2D], visibility: float = 0.9) -> PoseLandmarks:
    return PoseLandmarks(
        points=dict(points),
        visibility={index: visibility for index in points},
    )


def _stable_state(bottle: BottleDetection, frames: int = 6) -> dict:
    state = None
    for _ in range(frames):
        state, _ = track_bottle_stability(state, bottle)
    return state


def _arm_pose(
    *,
    left: bool,
    elbow: Point2D,
    wrist: Point2D,
) -> PoseLandmarks:
    if left:
        return _pose_from_points({13: elbow, 15: wrist})
    return _pose_from_points({14: elbow, 16: wrist})


def _upper_point(elbow: Point2D, wrist: Point2D, ratio: float = UPPER_FOREARM_RATIO) -> Point2D:
    return Point2D(
        x=elbow.x + (wrist.x - elbow.x) * ratio,
        y=elbow.y + (wrist.y - elbow.y) * ratio,
    )


def _bottle_at(point: Point2D) -> BottleDetection:
    return _bottle(cx=int(point.x * 640), cy=int(point.y * 480))


def test_upper_forearm_stall_success_left():
    elbow = Point2D(0.40, 0.40)
    wrist = Point2D(0.40, 0.70)
    upper = _upper_point(elbow, wrist)
    bottle = _bottle_at(upper)
    result, _, _ = evaluate_movement(
        "Upper Forearm Stall",
        bottle,
        _arm_pose(left=True, elbow=elbow, wrist=wrist),
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"


def test_upper_forearm_stall_success_right():
    elbow = Point2D(0.60, 0.40)
    wrist = Point2D(0.60, 0.70)
    upper = _upper_point(elbow, wrist)
    bottle = _bottle_at(upper)
    result, _, _ = evaluate_movement(
        "Upper Forearm Stall",
        bottle,
        _arm_pose(left=False, elbow=elbow, wrist=wrist),
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "positive"


def test_upper_forearm_stall_far_from_target():
    elbow = Point2D(0.40, 0.40)
    wrist = Point2D(0.40, 0.70)
    bottle = _bottle(cx=100, cy=100)
    result, _, _ = evaluate_movement(
        "Upper Forearm Stall",
        bottle,
        _arm_pose(left=True, elbow=elbow, wrist=wrist),
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "warning"
    assert "upper forearm" in result.feedback.lower()


def test_upper_forearm_stall_rejects_elbow():
    elbow = Point2D(0.50, 0.40)
    wrist = Point2D(0.50, 0.70)
    bottle = _bottle_at(elbow)
    result, _, _ = evaluate_movement(
        "Upper Forearm Stall",
        bottle,
        _arm_pose(left=True, elbow=elbow, wrist=wrist),
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "warning"
    assert "elbow" in result.feedback.lower()


def test_upper_forearm_stall_rejects_mid_forearm():
    elbow = Point2D(0.50, 0.40)
    wrist = Point2D(0.50, 0.70)
    mid = Point2D(x=(elbow.x + wrist.x) / 2.0, y=(elbow.y + wrist.y) / 2.0)
    bottle = _bottle_at(mid)
    result, _, _ = evaluate_movement(
        "Upper Forearm Stall",
        bottle,
        _arm_pose(left=True, elbow=elbow, wrist=wrist),
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "warning"
    assert "mid-forearm" in result.feedback.lower() or "wrist" in result.feedback.lower()


def test_upper_forearm_stall_missing_pose():
    result, _, _ = evaluate_movement(
        "Upper Forearm Stall",
        _bottle(),
        None,
        _hands_near(),
        None,
    )
    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"


def test_upper_forearm_stall_unstable_history():
    elbow = Point2D(0.50, 0.40)
    wrist = Point2D(0.50, 0.70)
    upper = _upper_point(elbow, wrist)
    bottle = _bottle_at(upper)
    state = None
    for i in range(6):
        moving = _bottle(cx=int(upper.x * 640) + i * 40, cy=int(upper.y * 480))
        state, _ = track_bottle_stability(state, moving)
    result, _, _ = evaluate_movement(
        "Upper Forearm Stall",
        bottle,
        _arm_pose(left=True, elbow=elbow, wrist=wrist),
        None,
        None,
        state,
    )
    assert result.feedback_type == "warning"
    assert "steady" in result.feedback.lower()


def test_upper_forearm_stall_proximity_boundary():
    elbow = Point2D(0.50, 0.40)
    wrist = Point2D(0.50, 0.70)
    upper = _upper_point(elbow, wrist)
    # Just outside the success proximity.
    outside = Point2D(upper.x + UPPER_FOREARM_STALL_PROXIMITY + 0.02, upper.y)
    bottle = _bottle_at(outside)
    result, _, _ = evaluate_movement(
        "Upper Forearm Stall",
        bottle,
        _arm_pose(left=True, elbow=elbow, wrist=wrist),
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "warning"
    helper = pose_upper_forearm_point(
        _arm_pose(left=True, elbow=elbow, wrist=wrist),
        _bottle_at(upper),
    )
    assert helper is not None
    assert helper.x == pytest.approx(upper.x)
    assert helper.y == pytest.approx(upper.y)


def test_shoulder_stall_success_left():
    shoulder = Point2D(0.40, 0.35)
    target = Point2D(shoulder.x, shoulder.y - SHOULDER_ABOVE_OFFSET)
    bottle = _bottle_at(target)
    pose = _pose_from_points({11: shoulder, 12: Point2D(0.70, 0.35)})
    result, _, _ = evaluate_movement(
        "Shoulder Stall",
        bottle,
        pose,
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "positive"


def test_shoulder_stall_success_right():
    shoulder = Point2D(0.65, 0.35)
    target = Point2D(shoulder.x, shoulder.y - SHOULDER_ABOVE_OFFSET)
    bottle = _bottle_at(target)
    pose = _pose_from_points({11: Point2D(0.30, 0.35), 12: shoulder})
    result, _, _ = evaluate_movement(
        "Shoulder Stall",
        bottle,
        pose,
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "positive"


def test_shoulder_stall_rejects_below_shoulder():
    shoulder = Point2D(0.50, 0.35)
    below = Point2D(shoulder.x, shoulder.y + 0.08)
    bottle = _bottle_at(below)
    pose = _pose_from_points({11: shoulder, 12: Point2D(0.70, 0.35)})
    result, _, _ = evaluate_movement(
        "Shoulder Stall",
        bottle,
        pose,
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "warning"
    assert "chest" in result.feedback.lower() or "shoulder" in result.feedback.lower()


def test_shoulder_stall_rejects_chest():
    shoulder = Point2D(0.50, 0.30)
    chest = Point2D(shoulder.x, shoulder.y + 0.12)
    bottle = _bottle_at(chest)
    pose = _pose_from_points({11: shoulder, 12: Point2D(0.70, 0.30)})
    result, _, _ = evaluate_movement(
        "Shoulder Stall",
        bottle,
        pose,
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "warning"


def test_shoulder_stall_far_from_shoulder():
    pose = _pose_from_points({11: Point2D(0.40, 0.35), 12: Point2D(0.60, 0.35)})
    bottle = _bottle(cx=100, cy=400)
    result, _, _ = evaluate_movement(
        "Shoulder Stall",
        bottle,
        pose,
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "warning"


def test_shoulder_stall_missing_landmarks():
    result, _, _ = evaluate_movement(
        "Shoulder Stall",
        _bottle(),
        PoseLandmarks(points={}, visibility={}),
        None,
        None,
    )
    assert result.feedback_type == "warning"
    assert result.posture_status == "unknown"


def test_shoulder_stall_unstable_history():
    shoulder = Point2D(0.50, 0.35)
    target = Point2D(shoulder.x, shoulder.y - SHOULDER_ABOVE_OFFSET)
    bottle = _bottle_at(target)
    pose = _pose_from_points({11: shoulder, 12: Point2D(0.70, 0.35)})
    state = None
    for i in range(6):
        moving = _bottle(cx=int(target.x * 640) + i * 40, cy=int(target.y * 480))
        state, _ = track_bottle_stability(state, moving)
    result, _, _ = evaluate_movement(
        "Shoulder Stall",
        bottle,
        pose,
        None,
        None,
        state,
    )
    assert result.feedback_type == "warning"
    assert "steady" in result.feedback.lower()


def test_shoulder_stall_proximity_boundary():
    shoulder = Point2D(0.50, 0.35)
    pose = _pose_from_points({11: shoulder, 12: Point2D(0.75, 0.35)})
    target = pose_shoulder_point(pose, _bottle_at(shoulder))
    assert target is not None
    # Stay above the shoulder line, but far from both shoulder targets.
    outside = Point2D(0.50, target.y - (SHOULDER_STALL_PROXIMITY + 0.05))
    bottle = _bottle_at(outside)
    result, _, _ = evaluate_movement(
        "Shoulder Stall",
        bottle,
        pose,
        None,
        None,
        _stable_state(bottle),
    )
    assert result.feedback_type == "warning"


def _two_palms(
    left_xy: tuple[float, float] = (0.42, 0.55),
    right_xy: tuple[float, float] = (0.58, 0.55),
    *,
    left_label: str = "Left",
    right_label: str = "Right",
    reverse_order: bool = False,
) -> HandsResult:
    left = _hand_near(left_xy[0], left_xy[1], left_label)
    right = _hand_near(right_xy[0], right_xy[1], right_label)
    hands = [right, left] if reverse_order else [left, right]
    return HandsResult(hands=hands)


def _double_hand_bottle(
    left_xy: tuple[float, float] = (0.42, 0.55),
    right_xy: tuple[float, float] = (0.58, 0.55),
    *,
    x: float | None = None,
    y: float | None = None,
) -> BottleDetection:
    mid_x = (left_xy[0] + right_xy[0]) / 2.0
    mid_y = (left_xy[1] + right_xy[1]) / 2.0
    target_x = mid_x if x is None else x
    target_y = mid_y - DOUBLE_HAND_TARGET_ABOVE_OFFSET if y is None else y
    return _bottle(cx=int(round(target_x * 640)), cy=int(round(target_y * 480)))


def _eval_double_hand(
    bottle: BottleDetection | None,
    hands: HandsResult | None,
    state: dict | None = None,
):
    return evaluate_movement(
        "Double Hand Stall",
        bottle,
        None,
        hands,
        None,
        state,
    )


def test_double_hand_stall_stable_success():
    hands = _two_palms()
    bottle = _double_hand_bottle()
    result, _, state = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "positive"
    assert "locked in" in result.feedback.lower()
    assert "bottle_history" in state


def test_double_hand_stall_success_reversed_hand_list_order():
    hands = _two_palms(reverse_order=True)
    bottle = _double_hand_bottle()
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "positive"


def test_double_hand_stall_success_unknown_handedness():
    hands = _two_palms(left_label="Unknown", right_label="Unknown")
    bottle = _double_hand_bottle()
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "positive"


def test_double_hand_stall_missing_bottle():
    result, _, _ = _eval_double_hand(None, _two_palms())
    assert result.feedback_type == "error"
    assert "bottle" in result.feedback.lower()


def test_double_hand_stall_no_hands():
    result, _, _ = _eval_double_hand(_double_hand_bottle(), None)
    assert result.feedback_type == "warning"
    assert "both hands" in result.feedback.lower()


def test_double_hand_stall_one_usable_hand():
    hands = HandsResult(hands=[_hand_near(0.42, 0.55, "Left")])
    result, _, _ = _eval_double_hand(_double_hand_bottle(), hands)
    assert result.feedback_type == "warning"
    assert "both hands" in result.feedback.lower()


def test_double_hand_stall_hand_missing_palm_landmarks():
    incomplete = HandLandmarks(
        points={4: Point2D(0.42, 0.55)},
        handedness="Left",
    )
    hands = HandsResult(hands=[incomplete, _hand_near(0.58, 0.55, "Right")])
    result, _, _ = _eval_double_hand(_double_hand_bottle(), hands)
    assert result.feedback_type == "warning"
    assert "both hands" in result.feedback.lower()


def test_double_hand_stall_rejects_overlapping_palms():
    hands = _two_palms((0.50, 0.55), (0.505, 0.55))
    bottle = _double_hand_bottle((0.50, 0.55), (0.505, 0.55))
    result, _, _ = _eval_double_hand(bottle, hands)
    assert result.feedback_type == "warning"
    assert "separate" in result.feedback.lower()


def test_double_hand_stall_rejects_palms_too_close():
    gap = DOUBLE_HAND_MIN_SEPARATION - 0.01
    left = (0.50 - gap / 2, 0.55)
    right = (0.50 + gap / 2, 0.55)
    hands = _two_palms(left, right)
    result, _, _ = _eval_double_hand(_double_hand_bottle(left, right), hands)
    assert result.feedback_type == "warning"
    assert "separate" in result.feedback.lower()


def test_double_hand_stall_rejects_palms_too_far():
    gap = DOUBLE_HAND_MAX_SEPARATION + 0.02
    left = (0.50 - gap / 2, 0.55)
    right = (0.50 + gap / 2, 0.55)
    hands = _two_palms(left, right)
    result, _, _ = _eval_double_hand(_double_hand_bottle(left, right), hands)
    assert result.feedback_type == "warning"
    assert "closer" in result.feedback.lower()


def test_double_hand_stall_rejects_uneven_palm_heights():
    left = (0.42, 0.50)
    right = (0.58, 0.50 + DOUBLE_HAND_MAX_HEIGHT_DIFFERENCE + 0.02)
    hands = _two_palms(left, right)
    result, _, _ = _eval_double_hand(_double_hand_bottle(left, right), hands)
    assert result.feedback_type == "warning"
    assert "same height" in result.feedback.lower()


def test_double_hand_stall_bottle_centered_above_palms():
    hands = _two_palms()
    bottle = _double_hand_bottle()
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "positive"


def test_double_hand_stall_rejects_bottle_near_left_palm_only():
    hands = _two_palms()
    bottle = _bottle(cx=int(0.42 * 640), cy=int(0.55 * 480))
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "warning"
    assert "center" in result.feedback.lower()


def test_double_hand_stall_rejects_bottle_near_right_palm_only():
    hands = _two_palms()
    bottle = _bottle(cx=int(0.58 * 640), cy=int(0.55 * 480))
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "warning"
    assert "center" in result.feedback.lower()


def test_double_hand_stall_rejects_bottle_outside_horizontal_support():
    hands = _two_palms()
    bottle = _double_hand_bottle(x=0.30, y=0.51)
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "warning"
    assert "center" in result.feedback.lower()


def test_double_hand_stall_rejects_bottle_below_palms():
    hands = _two_palms()
    bottle = _double_hand_bottle(y=0.70)
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "warning"
    assert "underneath" in result.feedback.lower()


def test_double_hand_stall_stable_history_positive():
    hands = _two_palms()
    bottle = _double_hand_bottle()
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "positive"


def test_double_hand_stall_unstable_history_warning():
    hands = _two_palms()
    bottle = _double_hand_bottle()
    state = _stable_state(bottle)
    # Inject large drift into the stability window.
    history = list(state["bottle_history"])
    history[-1] = (
        history[-1][0] + STALL_STABILITY_THRESHOLD + 0.05,
        history[-1][1],
    )
    state["bottle_history"] = history
    result, _, _ = _eval_double_hand(bottle, hands, state)
    assert result.feedback_type == "warning"
    assert "steady" in result.feedback.lower()


def test_double_hand_stall_min_separation_boundary_accepts():
    gap = DOUBLE_HAND_MIN_SEPARATION + 0.001
    left = (0.50 - gap / 2, 0.55)
    right = (0.50 + gap / 2, 0.55)
    hands = _two_palms(left, right)
    bottle = _double_hand_bottle(left, right)
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "positive"


def test_double_hand_stall_proximity_boundary_rejects():
    hands = _two_palms()
    # Far enough above the target to exceed stall proximity.
    bottle = _double_hand_bottle(
        y=0.55 - DOUBLE_HAND_TARGET_ABOVE_OFFSET - DOUBLE_HAND_STALL_PROXIMITY - 0.02
    )
    result, _, _ = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert result.feedback_type == "warning"


def test_double_hand_stall_state_isolated_between_evaluations():
    hands = _two_palms()
    bottle = _double_hand_bottle()
    _, _, first_state = _eval_double_hand(bottle, hands, _stable_state(bottle))
    assert len(first_state["bottle_history"]) >= 4
    result, _, second_state = _eval_double_hand(bottle, hands, None)
    assert result.feedback_type in ("positive", "warning")
    assert len(second_state["bottle_history"]) == 1


def test_double_hand_stall_posture_only_requires_two_hands():
    result, _, _ = evaluate_movement(
        "Double Hand Stall",
        None,
        None,
        HandsResult(hands=[_hand_near(0.42, 0.55, "Left")]),
        None,
        bottle_detection_enabled=False,
    )
    assert result.feedback_type == "warning"
    assert "both hands" in result.feedback.lower()


def test_double_hand_stall_posture_only_ready_with_two_hands():
    result, _, _ = evaluate_movement(
        "Double Hand Stall",
        None,
        None,
        _two_palms(),
        None,
        bottle_detection_enabled=False,
    )
    assert result.feedback_type == "positive"
    assert "bottle detection" in result.feedback.lower()
    assert "locked in" not in result.feedback.lower()
