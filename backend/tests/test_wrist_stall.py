from assessment.feedback_codes import FeedbackCode
from assessment.rule_engine import (
    evaluate_movement,
    movement_requires_hands,
    movement_requires_pose,
)
from assessment.rules.common_checks import track_bottle_stability
from vision.types import BottleDetection, Point2D, PoseLandmarks


def _pose_from_points(points: dict[int, Point2D], visibility: float = 0.9) -> PoseLandmarks:
    return PoseLandmarks(
        points=dict(points),
        visibility={index: visibility for index in points},
    )


def _arm_pose(*, left: bool, elbow: Point2D, wrist: Point2D) -> PoseLandmarks:
    if left:
        return _pose_from_points({13: elbow, 15: wrist})
    return _pose_from_points({14: elbow, 16: wrist})


def _bottle_at(point: Point2D, *, width: int = 40, height: int = 80) -> BottleDetection:
    cx = int(point.x * 640)
    cy = int(point.y * 480)
    return BottleDetection(
        x1=cx - width // 2,
        y1=cy - height // 2,
        x2=cx + width // 2,
        y2=cy + height // 2,
        confidence=0.9,
    )


def _stable_state(bottle: BottleDetection, frames: int = 6) -> dict:
    state = None
    for _ in range(frames):
        state, _ = track_bottle_stability(state, bottle)
    return state


def _mid(elbow: Point2D, wrist: Point2D) -> Point2D:
    return Point2D(x=(elbow.x + wrist.x) / 2.0, y=(elbow.y + wrist.y) / 2.0)


def _along(elbow: Point2D, wrist: Point2D, fraction_from_wrist: float) -> Point2D:
    return Point2D(
        x=wrist.x + (elbow.x - wrist.x) * fraction_from_wrist,
        y=wrist.y + (elbow.y - wrist.y) * fraction_from_wrist,
    )


def _evaluate(
    bottle: BottleDetection | None,
    pose: PoseLandmarks | None,
    state: dict | None = None,
    *,
    prop_type: str = "bottle",
):
    return evaluate_movement(
        "Wrist Stall",
        bottle,
        pose,
        None,
        None,
        state,
        prop_type=prop_type,
    )


def test_wrist_stall_bottle_left_positive():
    elbow = Point2D(0.40, 0.40)
    wrist = Point2D(0.40, 0.70)
    bottle = _bottle_at(wrist)
    result, _, _ = _evaluate(bottle, _arm_pose(left=True, elbow=elbow, wrist=wrist), _stable_state(bottle))
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_wrist_stall_bottle_right_positive():
    elbow = Point2D(0.60, 0.40)
    wrist = Point2D(0.60, 0.70)
    bottle = _bottle_at(wrist)
    result, _, _ = _evaluate(bottle, _arm_pose(left=False, elbow=elbow, wrist=wrist), _stable_state(bottle))
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_wrist_stall_shaker_left_positive():
    elbow = Point2D(0.40, 0.40)
    wrist = Point2D(0.40, 0.70)
    bottle = _bottle_at(wrist)
    result, _, _ = _evaluate(
        bottle,
        _arm_pose(left=True, elbow=elbow, wrist=wrist),
        _stable_state(bottle),
        prop_type="shaker",
    )
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_wrist_stall_shaker_right_positive():
    elbow = Point2D(0.60, 0.40)
    wrist = Point2D(0.60, 0.70)
    bottle = _bottle_at(wrist)
    result, _, _ = _evaluate(
        bottle,
        _arm_pose(left=False, elbow=elbow, wrist=wrist),
        _stable_state(bottle),
        prop_type="shaker",
    )
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_wrist_stall_forearm_midpoint_fails():
    elbow = Point2D(0.50, 0.40)
    wrist = Point2D(0.50, 0.70)
    bottle = _bottle_at(_mid(elbow, wrist))
    result, _, _ = _evaluate(bottle, _arm_pose(left=True, elbow=elbow, wrist=wrist), _stable_state(bottle))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.PROP_ON_FOREARM_NOT_WRIST.value


def test_wrist_stall_lower_mid_forearm_fails():
    elbow = Point2D(0.50, 0.40)
    wrist = Point2D(0.50, 0.70)
    bottle = _bottle_at(_along(elbow, wrist, 0.40))
    result, _, _ = _evaluate(bottle, _arm_pose(left=True, elbow=elbow, wrist=wrist), _stable_state(bottle))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.PROP_ON_FOREARM_NOT_WRIST.value


def test_wrist_stall_too_far_from_wrist_fails():
    elbow = Point2D(0.50, 0.40)
    wrist = Point2D(0.50, 0.70)
    bottle = _bottle_at(Point2D(0.20, 0.20))
    result, _, _ = _evaluate(bottle, _arm_pose(left=True, elbow=elbow, wrist=wrist), _stable_state(bottle))
    assert result.feedback_type == "warning"
    assert result.feedback_code in {
        FeedbackCode.PROP_NOT_ON_WRIST.value,
        FeedbackCode.PROP_ON_FOREARM_NOT_WRIST.value,
    }


def test_wrist_stall_wrong_selected_prop_fails():
    result, _, _ = _evaluate(None, None, prop_type="shaker")
    assert result.feedback_type == "error"
    assert "Cocktail Shaker" in result.feedback
    assert "bottle" not in result.feedback.lower()


def test_wrist_stall_unstable_prop_fails():
    elbow = Point2D(0.50, 0.40)
    wrist = Point2D(0.50, 0.70)
    bottle = _bottle_at(wrist)
    state = None
    for i in range(6):
        moving = _bottle_at(Point2D(wrist.x + i * 0.04, wrist.y))
        state, _ = track_bottle_stability(state, moving)
    result, _, _ = _evaluate(bottle, _arm_pose(left=True, elbow=elbow, wrist=wrist), state)
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.PROP_NOT_STEADY.value


def test_wrist_stall_missing_pose_fails_safely():
    result, _, _ = _evaluate(_bottle_at(Point2D(0.5, 0.5)), None)
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.POSE_ARM_NOT_VISIBLE.value
    assert result.criterion_results is None or result.criterion_results == ()


def test_wrist_stall_detector_profile():
    assert movement_requires_hands("Wrist Stall") is False
    assert movement_requires_pose("Wrist Stall") is True
