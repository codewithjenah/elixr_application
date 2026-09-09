from assessment.feedback_codes import FeedbackCode
from assessment.rule_engine import (
    evaluate_movement,
    movement_requires_hands,
    movement_requires_pose,
)
from assessment.rules.common_checks import track_bottle_stability
from vision.types import BottleDetection, HandsResult, HandLandmarks, Point2D, PoseLandmarks


def _pose_from_points(points: dict[int, Point2D], visibility: float = 0.9) -> PoseLandmarks:
    return PoseLandmarks(
        points=dict(points),
        visibility={index: visibility for index in points},
    )


def _both_arms_pose(
    *,
    left_elbow: Point2D,
    left_wrist: Point2D,
    right_elbow: Point2D,
    right_wrist: Point2D,
) -> PoseLandmarks:
    return _pose_from_points(
        {
            13: left_elbow,
            15: left_wrist,
            14: right_elbow,
            16: right_wrist,
        }
    )


def _default_pose() -> PoseLandmarks:
    return _both_arms_pose(
        left_elbow=Point2D(0.35, 0.40),
        left_wrist=Point2D(0.35, 0.70),
        right_elbow=Point2D(0.65, 0.40),
        right_wrist=Point2D(0.65, 0.70),
    )


def _mid(elbow: Point2D, wrist: Point2D) -> Point2D:
    return Point2D(x=(elbow.x + wrist.x) / 2.0, y=(elbow.y + wrist.y) / 2.0)


def _bottle_at(
    point: Point2D,
    *,
    width: int = 40,
    height: int = 80,
    track_id: int | None = None,
    confidence: float = 0.9,
) -> BottleDetection:
    cx = int(point.x * 640)
    cy = int(point.y * 480)
    return BottleDetection(
        x1=cx - width // 2,
        y1=cy - height // 2,
        x2=cx + width // 2,
        y2=cy + height // 2,
        confidence=confidence,
        track_id=track_id,
    )


def _stable_pair(left: BottleDetection, right: BottleDetection) -> dict:
    state: dict = {}
    for _ in range(6):
        left_sub, _ = track_bottle_stability(
            state.get("left_forearm"), left, movement_state=state
        )
        right_sub, _ = track_bottle_stability(
            state.get("right_forearm"), right, movement_state=state
        )
        state["left_forearm"] = left_sub
        state["right_forearm"] = right_sub
    return state


def _evaluate(
    bottles: list[BottleDetection],
    pose: PoseLandmarks | None,
    state: dict | None = None,
):
    return evaluate_movement(
        "Double Forearm Stall",
        bottles[0] if bottles else None,
        pose,
        None,
        None,
        state,
        bottles=bottles,
    )


def test_double_forearm_one_bottle_per_arm_succeeds():
    pose = _default_pose()
    left = _bottle_at(_mid(Point2D(0.35, 0.40), Point2D(0.35, 0.70)), track_id=1)
    right = _bottle_at(_mid(Point2D(0.65, 0.40), Point2D(0.65, 0.70)), track_id=2)
    result, _, _ = _evaluate([left, right], pose, _stable_pair(left, right))
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.DOUBLE_FOREARM_STALL_LOCKED.value


def test_double_forearm_reversed_detection_order_succeeds():
    pose = _default_pose()
    left = _bottle_at(_mid(Point2D(0.35, 0.40), Point2D(0.35, 0.70)), track_id=1)
    right = _bottle_at(_mid(Point2D(0.65, 0.40), Point2D(0.65, 0.70)), track_id=2)
    result, _, _ = _evaluate([right, left], pose, _stable_pair(left, right))
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.DOUBLE_FOREARM_STALL_LOCKED.value


def test_double_forearm_one_bottle_fails():
    pose = _default_pose()
    left = _bottle_at(_mid(Point2D(0.35, 0.40), Point2D(0.35, 0.70)))
    result, _, _ = _evaluate([left], pose)
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.NEED_TWO_BOTTLES.value


def test_double_forearm_two_bottles_left_fails():
    pose = _default_pose()
    mid_left = _mid(Point2D(0.35, 0.40), Point2D(0.35, 0.70))
    first = _bottle_at(mid_left, track_id=1)
    second = _bottle_at(Point2D(mid_left.x, mid_left.y + 0.02), track_id=2)
    result, _, _ = _evaluate([first, second], pose, _stable_pair(first, second))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.BOTTLES_NOT_ONE_PER_FOREARM.value


def test_double_forearm_two_bottles_right_fails():
    pose = _default_pose()
    mid_right = _mid(Point2D(0.65, 0.40), Point2D(0.65, 0.70))
    first = _bottle_at(mid_right, track_id=1)
    second = _bottle_at(Point2D(mid_right.x, mid_right.y + 0.02), track_id=2)
    result, _, _ = _evaluate([first, second], pose, _stable_pair(first, second))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.BOTTLES_NOT_ONE_PER_FOREARM.value


def test_double_forearm_two_bottles_on_midline_fails():
    pose = _default_pose()
    stacked = Point2D(0.50, 0.55)
    first = _bottle_at(stacked, track_id=1)
    second = _bottle_at(Point2D(stacked.x, stacked.y + 0.01), track_id=2)
    result, _, _ = _evaluate([first, second], pose, _stable_pair(first, second))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.BOTTLES_NOT_ONE_PER_FOREARM.value


def test_double_forearm_one_off_target_fails():
    pose = _default_pose()
    left = _bottle_at(_mid(Point2D(0.35, 0.40), Point2D(0.35, 0.70)), track_id=1)
    right = _bottle_at(Point2D(0.90, 0.20), track_id=2)
    result, _, _ = _evaluate([left, right], pose, _stable_pair(left, right))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.BOTTLES_NOT_ONE_PER_FOREARM.value


def test_double_forearm_unstable_pair_fails():
    pose = _default_pose()
    left = _bottle_at(_mid(Point2D(0.35, 0.40), Point2D(0.35, 0.70)), track_id=1)
    right = _bottle_at(_mid(Point2D(0.65, 0.40), Point2D(0.65, 0.70)), track_id=2)
    state: dict = {}
    for i in range(6):
        moving_right = _bottle_at(Point2D(0.65 + i * 0.04, 0.55), track_id=2)
        left_sub, _ = track_bottle_stability(
            state.get("left_forearm"), left, movement_state=state
        )
        right_sub, _ = track_bottle_stability(
            state.get("right_forearm"), moving_right, movement_state=state
        )
        state["left_forearm"] = left_sub
        state["right_forearm"] = right_sub
    result, _, _ = _evaluate([left, right], pose, state)
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.BOTH_PROPS_NOT_STEADY.value


def test_double_forearm_double_hand_pose_fails():
    pose = _default_pose()
    left = _bottle_at(Point2D(0.35, 0.70), track_id=1)
    right = _bottle_at(Point2D(0.65, 0.70), track_id=2)
    result, _, _ = _evaluate([left, right], pose, _stable_pair(left, right))
    assert result.feedback_type == "warning"
    assert result.feedback_code == FeedbackCode.BOTTLES_NOT_ONE_PER_FOREARM.value


def test_double_forearm_missing_either_arm_fails_safely():
    left_only = _pose_from_points(
        {13: Point2D(0.35, 0.40), 15: Point2D(0.35, 0.70)}
    )
    left = _bottle_at(_mid(Point2D(0.35, 0.40), Point2D(0.35, 0.70)), track_id=1)
    right = _bottle_at(_mid(Point2D(0.65, 0.40), Point2D(0.65, 0.70)), track_id=2)
    result, _, _ = _evaluate([left, right], left_only)
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.BOTH_ARMS_NOT_VISIBLE.value


def test_double_forearm_missing_pose_fails_safely():
    left = _bottle_at(Point2D(0.35, 0.55), track_id=1)
    right = _bottle_at(Point2D(0.65, 0.55), track_id=2)
    result, _, _ = _evaluate([left, right], None)
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.BOTH_ARMS_NOT_VISIBLE.value


def test_double_forearm_detector_profile():
    assert movement_requires_hands("Double Forearm Stall") is False
    assert movement_requires_pose("Double Forearm Stall") is True


def test_double_forearm_does_not_use_hands():
    pose = _default_pose()
    left = _bottle_at(_mid(Point2D(0.35, 0.40), Point2D(0.35, 0.70)), track_id=1)
    right = _bottle_at(_mid(Point2D(0.65, 0.40), Point2D(0.65, 0.70)), track_id=2)
    hands = HandsResult(
        hands=[
            HandLandmarks(
                points={0: Point2D(0.35, 0.70), 9: Point2D(0.35, 0.66)},
                handedness="Left",
            ),
            HandLandmarks(
                points={0: Point2D(0.65, 0.70), 9: Point2D(0.65, 0.66)},
                handedness="Right",
            ),
        ]
    )
    result, _, _ = evaluate_movement(
        "Double Forearm Stall",
        left,
        pose,
        hands,
        None,
        _stable_pair(left, right),
        bottles=[left, right],
    )
    assert result.feedback_code == FeedbackCode.DOUBLE_FOREARM_STALL_LOCKED.value
