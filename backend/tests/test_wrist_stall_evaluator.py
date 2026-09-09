"""Wrist Stall template evaluator: laterality, contact geometry, observability."""

from assessment.feedback_codes import FeedbackCode
from assessment.rules.common_checks import track_bottle_stability
from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.wrist_v1 import classify_wrist_support, evaluate
from vision.types import BottleDetection, Point2D, PoseLandmarks

# Raised-arm fixture: wrist above elbow. An upright bottle resting on the
# lower forearm has its bbox *center* pulled toward the wrist, which is the
# real-camera false positive (center-to-wrist still inside STALL_PROXIMITY).
_LEFT_SHOULDER = Point2D(0.38, 0.30)
_LEFT_ELBOW = Point2D(0.40, 0.62)
_LEFT_WRIST = Point2D(0.40, 0.42)
_RIGHT_SHOULDER = Point2D(0.62, 0.30)
_RIGHT_ELBOW = Point2D(0.60, 0.62)
_RIGHT_WRIST = Point2D(0.60, 0.42)

# Along elbow→wrist, t=0 at elbow and t=1 at wrist.
_LOWER_FOREARM_T = 0.70  # close to wrist, still on the forearm
_MID_FOREARM_T = 0.50
_ELBOW_SIDE_T = 0.10


def _spec(laterality: str = "left") -> AssessmentSpec:
    return AssessmentSpec.model_validate(
        {
            "schema_version": 1,
            "template_id": "balance_stall.wrist_v1",
            "prop": "bottle",
            "target": "wrist",
            "laterality": laterality,
        }
    )


def _lerp(start: Point2D, end: Point2D, t: float) -> Point2D:
    return Point2D(
        x=start.x + (end.x - start.x) * t,
        y=start.y + (end.y - start.y) * t,
    )


def _bottle_supported_at(
    nx: float,
    ny: float,
    *,
    width: int = 40,
    height: int = 80,
) -> BottleDetection:
    """Upright bottle whose bottom-center (support point) is at (nx, ny)."""
    cx = int(round(nx * 640))
    y2 = int(round(ny * 480))
    return BottleDetection(
        x1=cx - width // 2,
        y1=y2 - height,
        x2=cx + width // 2,
        y2=y2,
        confidence=0.9,
    )


def _pose_arm(
    *,
    left: bool = False,
    right: bool = False,
    include_elbow: bool = True,
    include_shoulder: bool = True,
    include_wrist: bool = True,
    left_jitter: Point2D | None = None,
) -> PoseLandmarks:
    points: dict[int, Point2D] = {}
    visibility: dict[int, float] = {}

    def _put(index: int, point: Point2D) -> None:
        points[index] = point
        visibility[index] = 0.9

    if left:
        if include_shoulder:
            _put(11, _LEFT_SHOULDER)
        if include_elbow:
            _put(13, _LEFT_ELBOW)
        if include_wrist:
            wrist = _LEFT_WRIST
            if left_jitter is not None:
                wrist = Point2D(wrist.x + left_jitter.x, wrist.y + left_jitter.y)
            _put(15, wrist)
    if right:
        if include_shoulder:
            _put(12, _RIGHT_SHOULDER)
        if include_elbow:
            _put(14, _RIGHT_ELBOW)
        if include_wrist:
            _put(16, _RIGHT_WRIST)
    return PoseLandmarks(points=points, visibility=visibility)


def _on_left_forearm(t: float) -> Point2D:
    return _lerp(_LEFT_ELBOW, _LEFT_WRIST, t)


def test_wrist_stall_positive_left():
    bottle = _bottle_supported_at(_LEFT_WRIST.x, _LEFT_WRIST.y)
    pose = _pose_arm(left=True)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.posture_status == "stable"
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value
    assert result.criterion_results is not None


def test_wrist_stall_positive_right():
    bottle = _bottle_supported_at(_RIGHT_WRIST.x, _RIGHT_WRIST.y)
    pose = _pose_arm(right=True)
    result, _ = evaluate(_spec("right"), bottle, pose)
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_wrist_stall_bottle_missing_is_unknown():
    pose = _pose_arm(left=True)
    result, _ = evaluate(_spec("left"), None, pose)
    assert result.posture_status == "unknown"
    assert result.criterion_results is None


def test_wrist_stall_wrong_wrist_is_unknown():
    bottle = _bottle_supported_at(_RIGHT_WRIST.x, _RIGHT_WRIST.y)
    pose = _pose_arm(right=True)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.POSE_ARM_NOT_VISIBLE.value


def test_wrist_stall_correct_geometry_on_wrong_arm_does_not_succeed():
    bottle = _bottle_supported_at(_RIGHT_WRIST.x, _RIGHT_WRIST.y)
    pose = _pose_arm(left=True, right=True)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.feedback_code != FeedbackCode.WRIST_STALL_LOCKED.value
    assert result.feedback_type != "positive"


def test_wrist_stall_lower_forearm_near_wrist_does_not_succeed():
    support = _on_left_forearm(_LOWER_FOREARM_T)
    bottle = _bottle_supported_at(support.x, support.y)
    pose = _pose_arm(left=True)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.feedback_code != FeedbackCode.WRIST_STALL_LOCKED.value
    assert result.posture_status == "unstable"
    assert result.feedback == "Move the bottle down to your wrist."
    assert result.feedback_code == FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value
    assert result.criterion_results is not None
    assert result.criterion_results["prop_positioning"].satisfied is False


def test_wrist_stall_mid_forearm_does_not_succeed():
    support = _on_left_forearm(_MID_FOREARM_T)
    bottle = _bottle_supported_at(support.x, support.y)
    pose = _pose_arm(left=True)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.feedback_code != FeedbackCode.WRIST_STALL_LOCKED.value
    assert result.posture_status == "unstable"


def test_wrist_stall_elbow_side_does_not_succeed():
    support = _on_left_forearm(_ELBOW_SIDE_T)
    bottle = _bottle_supported_at(support.x, support.y)
    pose = _pose_arm(left=True)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.feedback_code != FeedbackCode.WRIST_STALL_LOCKED.value
    assert result.posture_status == "unstable"


def test_wrist_stall_right_lower_forearm_does_not_succeed():
    support = _lerp(_RIGHT_ELBOW, _RIGHT_WRIST, _LOWER_FOREARM_T)
    bottle = _bottle_supported_at(support.x, support.y)
    pose = _pose_arm(right=True)
    result, _ = evaluate(_spec("right"), bottle, pose)
    assert result.feedback_code != FeedbackCode.WRIST_STALL_LOCKED.value
    assert result.posture_status == "unstable"


def test_wrist_stall_tolerates_small_landmark_jitter():
    bottle = _bottle_supported_at(_LEFT_WRIST.x + 0.008, _LEFT_WRIST.y + 0.010)
    pose = _pose_arm(left=True, left_jitter=Point2D(-0.006, 0.004))
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_wrist_stall_missing_wrist_is_unknown():
    bottle = _bottle_supported_at(_LEFT_WRIST.x, _LEFT_WRIST.y)
    pose = _pose_arm(left=True, include_wrist=False)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.POSE_ARM_NOT_VISIBLE.value
    assert result.criterion_results is None


def test_wrist_stall_missing_elbow_is_unknown():
    bottle = _bottle_supported_at(_LEFT_WRIST.x, _LEFT_WRIST.y)
    pose = _pose_arm(left=True, include_elbow=False)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.POSE_ARM_NOT_VISIBLE.value
    assert result.criterion_results is None


def test_wrist_stall_far_relationship_fails_positioning():
    bottle = _bottle_supported_at(0.12, 0.12)
    pose = _pose_arm(left=True)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value


def test_wrist_stall_unstable_hold_fails_stability():
    bottle = _bottle_supported_at(_LEFT_WRIST.x, _LEFT_WRIST.y)
    pose = _pose_arm(left=True)
    state = None
    jumpy = _bottle_supported_at(0.30, 0.35)
    for _ in range(6):
        state, _ = track_bottle_stability(state, jumpy)
        jumpy = _bottle_supported_at(0.38, 0.35)
        state, _ = track_bottle_stability(state, jumpy)
        jumpy = _bottle_supported_at(0.30, 0.35)
    result, _ = evaluate(_spec("left"), bottle, pose, state)
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_STEADY.value


def test_wrist_stall_tilted_bottle_fails_technique():
    bottle = _bottle_supported_at(_LEFT_WRIST.x, _LEFT_WRIST.y, width=100, height=50)
    pose = _pose_arm(left=True)
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_UPRIGHT.value


def test_classify_wrist_support_separates_wrist_from_forearm():
    assert (
        classify_wrist_support(_LEFT_WRIST, wrist=_LEFT_WRIST, elbow=_LEFT_ELBOW)
        == "wrist"
    )
    lower = _on_left_forearm(_LOWER_FOREARM_T)
    assert (
        classify_wrist_support(lower, wrist=_LEFT_WRIST, elbow=_LEFT_ELBOW)
        == "forearm"
    )
    mid = _on_left_forearm(_MID_FOREARM_T)
    assert classify_wrist_support(mid, wrist=_LEFT_WRIST, elbow=_LEFT_ELBOW) == "forearm"
    elbow_side = _on_left_forearm(_ELBOW_SIDE_T)
    assert (
        classify_wrist_support(elbow_side, wrist=_LEFT_WRIST, elbow=_LEFT_ELBOW)
        == "forearm"
    )
    far = Point2D(0.12, 0.12)
    assert classify_wrist_support(far, wrist=_LEFT_WRIST, elbow=_LEFT_ELBOW) == "far"


def test_classify_wrist_support_degenerate_forearm_is_unknown():
    assert (
        classify_wrist_support(_LEFT_WRIST, wrist=_LEFT_WRIST, elbow=_LEFT_WRIST)
        is None
    )
