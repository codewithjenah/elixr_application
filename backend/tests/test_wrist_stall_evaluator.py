from assessment.feedback_codes import FeedbackCode
from assessment.rules.common_checks import track_bottle_stability
from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.wrist_v1 import evaluate
from vision.types import BottleDetection, Point2D, PoseLandmarks


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


def _bottle(cx: int = 320, cy: int = 240) -> BottleDetection:
    return BottleDetection(
        x1=cx - 20,
        y1=cy - 40,
        x2=cx + 20,
        y2=cy + 40,
        confidence=0.9,
    )


def _pose(*, left=None, right=None) -> PoseLandmarks:
    points = {}
    visibility = {}
    if left is not None:
        points[15] = left
        visibility[15] = 0.9
    if right is not None:
        points[16] = right
        visibility[16] = 0.9
    return PoseLandmarks(points=points, visibility=visibility)


def test_wrist_stall_positive_left():
    bottle = _bottle()
    pose = _pose(left=Point2D(0.5, 0.5))
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.posture_status == "stable"
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value
    assert result.criterion_results is not None


def test_wrist_stall_positive_right():
    bottle = _bottle()
    pose = _pose(right=Point2D(0.5, 0.5))
    result, _ = evaluate(_spec("right"), bottle, pose)
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_wrist_stall_bottle_missing_is_unknown():
    pose = _pose(left=Point2D(0.5, 0.5))
    result, _ = evaluate(_spec("left"), None, pose)
    assert result.posture_status == "unknown"
    assert result.criterion_results is None


def test_wrist_stall_wrong_wrist_is_unknown():
    bottle = _bottle()
    pose = _pose(right=Point2D(0.5, 0.5))
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.posture_status == "unknown"
    assert result.feedback_code == FeedbackCode.POSE_ARM_NOT_VISIBLE.value


def test_wrist_stall_far_relationship_fails_positioning():
    bottle = _bottle()
    pose = _pose(left=Point2D(0.1, 0.1))
    result, _ = evaluate(_spec("left"), bottle, pose)
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value


def test_wrist_stall_unstable_hold_fails_stability():
    bottle = _bottle()
    pose = _pose(left=Point2D(0.5, 0.5))
    state = None
    jumpy = _bottle(cx=200, cy=180)
    for _ in range(6):
        state, _ = track_bottle_stability(state, jumpy)
        jumpy = _bottle(cx=200 + 40, cy=180)
        state, _ = track_bottle_stability(state, jumpy)
        jumpy = _bottle(cx=200, cy=180)
    result, _ = evaluate(_spec("left"), bottle, pose, state)
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_STEADY.value
