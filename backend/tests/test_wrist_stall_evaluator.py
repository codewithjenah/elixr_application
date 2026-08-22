"""Phase 7B: isolated balance_stall.wrist_v1 evaluator.

Uses real BottleDetection / PoseLandmarks geometry, the real HoldValidator,
and the real RubricTracker. Does not invoke the official rule engine path.
"""

from __future__ import annotations

import inspect
from types import SimpleNamespace

import pytest

from assessment.feedback_codes import (
    FeedbackCategory,
    FeedbackCode,
    category_for,
    criterion_for,
    is_locked_code,
)
from assessment.hold_validator import HoldValidator
from assessment.rule_engine import _RULES
from assessment.rules.common_checks import (
    pose_wrist_point,
    pose_wrist_point_for_laterality,
    track_bottle_stability,
)
from assessment.rubric import RubricCriterion
from assessment.scoring import RubricTracker
from assessment.specs.assessment_spec import AssessmentSpec
from assessment.specs.wrist_v1 import evaluate
from config import (
    HOLD_CONFIRMATION_SECONDS,
    HOLD_UNKNOWN_GRACE_SECONDS,
    MOVEMENT_CONFIG,
    RUBRIC_MIN_OBSERVED_SECONDS,
    STALL_PROXIMITY,
)
from vision.types import BottleDetection, Point2D, PoseLandmarks

_LEFT_WRIST = 15
_RIGHT_WRIST = 16


def _spec(*, laterality: str = "either") -> AssessmentSpec:
    return AssessmentSpec.model_validate(
        {
            "schema_version": 1,
            "template_id": "balance_stall.wrist_v1",
            "prop": "bottle",
            "target": "wrist",
            "laterality": laterality,
        }
    )


def _pose_from_points(
    points: dict[int, Point2D],
    visibility: float = 0.9,
    visibility_overrides: dict[int, float] | None = None,
) -> PoseLandmarks:
    vis = {index: visibility for index in points}
    if visibility_overrides:
        vis.update(visibility_overrides)
    return PoseLandmarks(points=dict(points), visibility=vis)


def _both_wrists(
    left: Point2D = Point2D(0.30, 0.60),
    right: Point2D = Point2D(0.70, 0.60),
    *,
    visibility: float = 0.9,
    visibility_overrides: dict[int, float] | None = None,
) -> PoseLandmarks:
    return _pose_from_points(
        {_LEFT_WRIST: left, _RIGHT_WRIST: right},
        visibility=visibility,
        visibility_overrides=visibility_overrides,
    )


def _left_only(point: Point2D = Point2D(0.30, 0.60)) -> PoseLandmarks:
    return _pose_from_points({_LEFT_WRIST: point})


def _right_only(point: Point2D = Point2D(0.70, 0.60)) -> PoseLandmarks:
    return _pose_from_points({_RIGHT_WRIST: point})


def _upright_bottle_at(
    point: Point2D,
    *,
    width: int = 40,
    height: int = 80,
) -> BottleDetection:
    cx = int(round(point.x * 640))
    cy = int(round(point.y * 480))
    return BottleDetection(
        x1=cx - width // 2,
        y1=cy - height // 2,
        x2=cx + width // 2,
        y2=cy + height // 2,
        confidence=0.9,
    )


def _horizontal_bottle_at(point: Point2D) -> BottleDetection:
    return _upright_bottle_at(point, width=100, height=60)


def _stable_state(bottle: BottleDetection, frames: int = 6) -> dict:
    state: dict | None = None
    for _ in range(frames):
        state, _ = track_bottle_stability(state, bottle)
    assert state is not None
    return state


def _eval(
    *,
    laterality: str = "either",
    bottle: BottleDetection | None,
    pose: PoseLandmarks | None,
    movement_state: dict | None = None,
):
    return evaluate(_spec(laterality=laterality), bottle, pose, movement_state)


def _assert_unknown(result, *, code: FeedbackCode) -> None:
    assert result.posture_status == "unknown"
    assert result.feedback_code == code.value
    assert result.criterion_results is None
    assert category_for(result.feedback_code) in {
        FeedbackCategory.VISIBILITY,
        FeedbackCategory.ENVIRONMENT,
    }
    assert criterion_for(result.feedback_code) is None


def _assert_criterion(
    result,
    *,
    technique_satisfied: bool,
    positioning_satisfied: bool,
    stability_satisfied: bool,
    technique_reason: str | None = None,
    positioning_reason: str | None = None,
    stability_reason: str | None = None,
) -> None:
    assert result.criterion_results is not None
    technique = result.criterion_results[RubricCriterion.TECHNIQUE.value]
    positioning = result.criterion_results[RubricCriterion.PROP_POSITIONING.value]
    stability = result.criterion_results[RubricCriterion.STABILITY.value]
    assert technique.observed is True
    assert positioning.observed is True
    assert stability.observed is True
    assert technique.satisfied is technique_satisfied
    assert positioning.satisfied is positioning_satisfied
    assert stability.satisfied is stability_satisfied
    if technique_reason is not None:
        assert technique.reason_code == technique_reason
    if positioning_reason is not None:
        assert positioning.reason_code == positioning_reason
    if stability_reason is not None:
        assert stability.reason_code == stability_reason


# ---------------------------------------------------------------------------
# Laterality helper
# ---------------------------------------------------------------------------


def test_laterality_helper_either_matches_pose_wrist_point():
    left = Point2D(0.30, 0.60)
    right = Point2D(0.70, 0.60)
    pose = _both_wrists(left, right)
    bottle = _upright_bottle_at(left)
    assert pose_wrist_point_for_laterality(pose, bottle, "either") == pose_wrist_point(
        pose, bottle
    )
    assert pose_wrist_point(pose, bottle) == left


def test_laterality_helper_left_and_right_are_anatomical():
    left = Point2D(0.30, 0.60)
    right = Point2D(0.70, 0.60)
    pose = _both_wrists(left, right)
    bottle_near_right = _upright_bottle_at(right)
    assert pose_wrist_point_for_laterality(pose, bottle_near_right, "left") == left
    assert pose_wrist_point_for_laterality(pose, bottle_near_right, "right") == right


def test_laterality_helper_ignores_unusable_wrist():
    right = Point2D(0.70, 0.60)
    pose = _right_only(right)
    bottle = _upright_bottle_at(right)
    assert pose_wrist_point_for_laterality(pose, bottle, "left") is None
    assert pose_wrist_point_for_laterality(pose, bottle, "right") == right


# ---------------------------------------------------------------------------
# Core evaluator
# ---------------------------------------------------------------------------


def test_golden_either_laterality_stable_wrist_stall():
    left = Point2D(0.30, 0.60)
    bottle = _upright_bottle_at(left)
    result, _ = _eval(
        bottle=bottle,
        pose=_both_wrists(left, Point2D(0.70, 0.60)),
        movement_state=_stable_state(bottle),
    )
    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value
    assert is_locked_code(result.feedback_code)
    assert category_for(result.feedback_code) == FeedbackCategory.TECHNIQUE
    _assert_criterion(
        result,
        technique_satisfied=True,
        positioning_satisfied=True,
        stability_satisfied=True,
        technique_reason=FeedbackCode.WRIST_STALL_LOCKED.value,
        positioning_reason=FeedbackCode.WRIST_STALL_LOCKED.value,
        stability_reason=FeedbackCode.WRIST_STALL_LOCKED.value,
    )


def test_anatomical_left_accepts_left_wrist():
    left = Point2D(0.30, 0.60)
    bottle = _upright_bottle_at(left)
    result, _ = _eval(
        laterality="left",
        bottle=bottle,
        pose=_left_only(left),
        movement_state=_stable_state(bottle),
    )
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_anatomical_left_rejects_bottle_only_near_right_wrist():
    left = Point2D(0.30, 0.60)
    right = Point2D(0.70, 0.60)
    bottle = _upright_bottle_at(right)
    result, _ = _eval(
        laterality="left",
        bottle=bottle,
        pose=_both_wrists(left, right),
        movement_state=_stable_state(bottle),
    )
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value
    _assert_criterion(
        result,
        technique_satisfied=True,
        positioning_satisfied=False,
        stability_satisfied=True,
        positioning_reason=FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value,
    )


def test_anatomical_right_accepts_right_wrist():
    right = Point2D(0.70, 0.60)
    bottle = _upright_bottle_at(right)
    result, _ = _eval(
        laterality="right",
        bottle=bottle,
        pose=_right_only(right),
        movement_state=_stable_state(bottle),
    )
    assert result.feedback_type == "positive"
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_anatomical_right_rejects_bottle_only_near_left_wrist():
    left = Point2D(0.30, 0.60)
    right = Point2D(0.70, 0.60)
    bottle = _upright_bottle_at(left)
    result, _ = _eval(
        laterality="right",
        bottle=bottle,
        pose=_both_wrists(left, right),
        movement_state=_stable_state(bottle),
    )
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value


def test_either_selects_nearest_usable_wrist():
    left = Point2D(0.30, 0.60)
    right = Point2D(0.70, 0.60)
    pose = _both_wrists(left, right)

    left_bottle = _upright_bottle_at(left)
    left_result, _ = _eval(
        bottle=left_bottle,
        pose=pose,
        movement_state=_stable_state(left_bottle),
    )
    assert left_result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value

    right_bottle = _upright_bottle_at(right)
    right_result, _ = _eval(
        bottle=right_bottle,
        pose=pose,
        movement_state=_stable_state(right_bottle),
    )
    assert right_result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_missing_bottle_is_unknown():
    result, _ = _eval(bottle=None, pose=_both_wrists())
    _assert_unknown(result, code=FeedbackCode.PROP_NOT_DETECTED)


def test_missing_pose_is_unknown():
    bottle = _upright_bottle_at(Point2D(0.30, 0.60))
    result, _ = _eval(bottle=bottle, pose=None)
    _assert_unknown(result, code=FeedbackCode.POSE_ARM_NOT_VISIBLE)


def test_missing_selected_wrist_is_unknown():
    bottle = _upright_bottle_at(Point2D(0.70, 0.60))
    result, _ = _eval(
        laterality="left",
        bottle=bottle,
        pose=_right_only(),
    )
    _assert_unknown(result, code=FeedbackCode.POSE_ARM_NOT_VISIBLE)


def test_low_visibility_selected_wrist_is_unknown():
    left = Point2D(0.30, 0.60)
    bottle = _upright_bottle_at(left)
    pose = _both_wrists(
        left,
        Point2D(0.70, 0.60),
        visibility_overrides={_LEFT_WRIST: 0.3},
    )
    result, _ = _eval(laterality="left", bottle=bottle, pose=pose)
    _assert_unknown(result, code=FeedbackCode.POSE_ARM_NOT_VISIBLE)


def test_bottle_not_upright_is_unstable_technique():
    left = Point2D(0.30, 0.60)
    bottle = _horizontal_bottle_at(left)
    result, _ = _eval(
        bottle=bottle,
        pose=_left_only(left),
        movement_state=_stable_state(bottle),
    )
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_UPRIGHT.value
    _assert_criterion(
        result,
        technique_satisfied=False,
        positioning_satisfied=True,
        stability_satisfied=True,
        technique_reason=FeedbackCode.PROP_NOT_UPRIGHT.value,
    )


def test_bottle_too_far_from_wrist_is_unstable_positioning():
    left = Point2D(0.30, 0.60)
    far = Point2D(left.x + STALL_PROXIMITY + 0.15, left.y)
    bottle = _upright_bottle_at(far)
    result, _ = _eval(
        laterality="left",
        bottle=bottle,
        pose=_left_only(left),
        movement_state=_stable_state(bottle),
    )
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value
    _assert_criterion(
        result,
        technique_satisfied=True,
        positioning_satisfied=False,
        stability_satisfied=True,
        positioning_reason=FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value,
    )


def test_unstable_bottle_history_is_unstable_stability():
    left = Point2D(0.30, 0.60)
    bottle = _upright_bottle_at(left)
    state = None
    for index in range(6):
        moving = _upright_bottle_at(Point2D(left.x + index * 0.08, left.y))
        state, _ = track_bottle_stability(state, moving)
    result, _ = _eval(
        laterality="left",
        bottle=bottle,
        pose=_left_only(left),
        movement_state=state,
    )
    assert result.posture_status == "unstable"
    assert result.feedback_code == FeedbackCode.PROP_NOT_STEADY.value
    _assert_criterion(
        result,
        technique_satisfied=True,
        positioning_satisfied=True,
        stability_satisfied=False,
        stability_reason=FeedbackCode.PROP_NOT_STEADY.value,
    )


def test_stable_correct_result_is_positive_stable():
    left = Point2D(0.30, 0.60)
    bottle = _upright_bottle_at(left)
    result, _ = _eval(
        bottle=bottle,
        pose=_left_only(left),
        movement_state=_stable_state(bottle),
    )
    assert result.feedback_type == "positive"
    assert result.posture_status == "stable"


def test_stable_result_code_is_wrist_stall_locked():
    left = Point2D(0.30, 0.60)
    bottle = _upright_bottle_at(left)
    result, _ = _eval(
        bottle=bottle,
        pose=_left_only(left),
        movement_state=_stable_state(bottle),
    )
    assert result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value


def test_unknown_results_contain_no_scored_criterion_evidence():
    missing_bottle, _ = _eval(bottle=None, pose=_both_wrists())
    missing_pose, _ = _eval(
        bottle=_upright_bottle_at(Point2D(0.30, 0.60)), pose=None
    )
    missing_wrist, _ = _eval(
        laterality="right",
        bottle=_upright_bottle_at(Point2D(0.30, 0.60)),
        pose=_left_only(),
    )
    for result in (missing_bottle, missing_pose, missing_wrist):
        assert result.criterion_results is None


def test_evaluator_does_not_require_hands():
    signature = inspect.signature(evaluate)
    assert "hands" not in signature.parameters
    assert "HandsResult" not in str(signature)


def test_evaluator_state_independent_across_simulated_sessions():
    left = Point2D(0.30, 0.60)
    good = _upright_bottle_at(left)
    pose = _left_only(left)

    prior = None
    # Stay inside STALL_PROXIMITY so history is persisted, but jump far
    # enough that the existing stability helper reports unsteady.
    for offset in (0.00, 0.05, -0.05, 0.06, -0.06, 0.04):
        moving = _upright_bottle_at(Point2D(left.x + offset, left.y))
        _, prior = _eval(laterality="left", bottle=moving, pose=pose, movement_state=prior)
    inherited, _ = _eval(
        laterality="left",
        bottle=good,
        pose=pose,
        movement_state=prior,
    )
    assert inherited.feedback_code == FeedbackCode.PROP_NOT_STEADY.value

    fresh, fresh_state = _eval(
        laterality="left",
        bottle=good,
        pose=pose,
        movement_state=None,
    )
    assert fresh.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value
    assert fresh_state is not None
    assert len(fresh_state.get("bottle_history", [])) < len(prior["bottle_history"])


def test_calibration_scale_changes_distance_gate():
    left = Point2D(0.30, 0.60)
    offset = Point2D(left.x + 0.10, left.y)
    bottle = _upright_bottle_at(offset)
    pose = _left_only(left)

    loose = _stable_state(bottle)
    loose["calibration_scale"] = 1.0
    pass_result, pass_state = _eval(
        laterality="left",
        bottle=bottle,
        pose=pose,
        movement_state=loose,
    )
    assert pass_result.feedback_code == FeedbackCode.WRIST_STALL_LOCKED.value
    assert pass_state["calibration_scale"] == pytest.approx(1.0)

    tight = _stable_state(bottle)
    tight["calibration_scale"] = 0.6
    fail_result, fail_state = _eval(
        laterality="left",
        bottle=bottle,
        pose=pose,
        movement_state=tight,
    )
    assert fail_result.posture_status == "unstable"
    assert fail_result.feedback_code == FeedbackCode.PROP_NOT_POSITIONED_ON_TARGET.value
    assert fail_state["calibration_scale"] == pytest.approx(0.6)


def test_mismatched_spec_cannot_be_evaluated_as_wrist_v1():
    bottle = _upright_bottle_at(Point2D(0.30, 0.60))
    pose = _left_only(Point2D(0.30, 0.60))
    foreign = AssessmentSpec.model_construct(
        schema_version=1,
        template_id="not_a_supported_template",
        prop="bottle",
        target="wrist",
        laterality="either",
    )
    with pytest.raises(ValueError, match="balance_stall.wrist_v1"):
        evaluate(foreign, bottle, pose, _stable_state(bottle))

    duck = SimpleNamespace(
        schema_version=1,
        template_id="balance_stall.elbow_v1",
        prop="bottle",
        target="wrist",
        laterality="either",
    )
    with pytest.raises(ValueError, match="balance_stall.wrist_v1"):
        evaluate(duck, bottle, pose, _stable_state(bottle))


def test_wrist_stall_absent_from_official_catalog():
    assert "Wrist Stall" not in MOVEMENT_CONFIG
    assert "balance_stall.wrist_v1" not in MOVEMENT_CONFIG
    assert "Wrist Stall" not in _RULES
    assert "balance_stall.wrist_v1" not in _RULES


# ---------------------------------------------------------------------------
# HoldValidator integration — elapsed time, not frame counts
# ---------------------------------------------------------------------------


def test_hold_validator_confirms_after_elapsed_stable_wrist_results():
    left = Point2D(0.30, 0.60)
    bottle = _upright_bottle_at(left)
    pose = _left_only(left)
    state = _stable_state(bottle)
    validator = HoldValidator()
    validator.activate()

    timestamp = 0.0
    snapshot = None
    while timestamp < HOLD_CONFIRMATION_SECONDS:
        result, state = _eval(
            laterality="left",
            bottle=bottle,
            pose=pose,
            movement_state=state,
        )
        assert result.feedback_type == "positive"
        assert result.posture_status == "stable"
        snapshot = validator.update(
            feedback_type=result.feedback_type,
            posture_status=result.posture_status,
            session_active=True,
            timestamp=timestamp,
        )
        assert snapshot.hold_confirmed is False
        timestamp += 0.1

    while timestamp <= HOLD_CONFIRMATION_SECONDS + 0.3:
        result, state = _eval(
            laterality="left",
            bottle=bottle,
            pose=pose,
            movement_state=state,
        )
        snapshot = validator.update(
            feedback_type=result.feedback_type,
            posture_status=result.posture_status,
            session_active=True,
            timestamp=timestamp,
        )
        timestamp += 0.1

    assert snapshot is not None
    assert snapshot.hold_confirmed is True
    assert snapshot.hold_duration_ms >= int(round(HOLD_CONFIRMATION_SECONDS * 1000))


def test_hold_validator_unknown_visibility_gives_no_credit():
    left = Point2D(0.30, 0.60)
    bottle = _upright_bottle_at(left)
    pose = _left_only(left)
    state = _stable_state(bottle)
    validator = HoldValidator()
    validator.activate()

    timestamp = 0.0
    while timestamp < 1.0:
        result, state = _eval(
            laterality="left",
            bottle=bottle,
            pose=pose,
            movement_state=state,
        )
        validator.update(
            feedback_type=result.feedback_type,
            posture_status=result.posture_status,
            session_active=True,
            timestamp=timestamp,
        )
        timestamp += 0.1

    progress_before_unknown = validator.update(
        feedback_type="positive",
        posture_status="stable",
        session_active=True,
        timestamp=timestamp,
    ).hold_duration_ms
    timestamp += 0.1

    unknown, _ = _eval(laterality="left", bottle=None, pose=pose)
    assert unknown.posture_status == "unknown"
    paused = validator.update(
        feedback_type=unknown.feedback_type,
        posture_status=unknown.posture_status,
        session_active=True,
        timestamp=timestamp,
    )
    assert paused.hold_confirmed is False
    assert paused.hold_duration_ms == progress_before_unknown

    timestamp += HOLD_UNKNOWN_GRACE_SECONDS + 0.2
    after_grace = validator.update(
        feedback_type=unknown.feedback_type,
        posture_status=unknown.posture_status,
        session_active=True,
        timestamp=timestamp,
    )
    assert after_grace.hold_confirmed is False
    assert after_grace.hold_duration_ms == 0


def test_hold_validator_unstable_result_does_not_confirm():
    left = Point2D(0.30, 0.60)
    bottle = _horizontal_bottle_at(left)
    pose = _left_only(left)
    state = _stable_state(bottle)
    validator = HoldValidator()
    validator.activate()

    timestamp = 0.0
    snapshot = None
    while timestamp <= HOLD_CONFIRMATION_SECONDS + 0.5:
        result, state = _eval(
            laterality="left",
            bottle=bottle,
            pose=pose,
            movement_state=state,
        )
        assert result.posture_status == "unstable"
        snapshot = validator.update(
            feedback_type=result.feedback_type,
            posture_status=result.posture_status,
            session_active=True,
            timestamp=timestamp,
        )
        timestamp += 0.1

    assert snapshot is not None
    assert snapshot.hold_confirmed is False


# ---------------------------------------------------------------------------
# RubricTracker integration
# ---------------------------------------------------------------------------


def _advance_tracker(
    tracker: RubricTracker,
    validator: HoldValidator,
    result,
    timestamp: float,
):
    hold = validator.update(
        feedback_type=result.feedback_type,
        posture_status=result.posture_status,
        session_active=True,
        timestamp=timestamp,
    )
    tracker.record(
        feedback_code=result.feedback_code,
        feedback_type=result.feedback_type,
        posture_status=result.posture_status,
        timestamp=timestamp,
        criterion_results=result.criterion_results,
    )
    return hold


def test_rubric_tracker_scores_sustained_wrist_stall_within_bounds():
    left = Point2D(0.30, 0.60)
    bottle = _upright_bottle_at(left)
    pose = _left_only(left)
    state = _stable_state(bottle)
    tracker = RubricTracker()
    tracker.activate()
    validator = HoldValidator()
    validator.activate()

    timestamp = 0.0
    hold = None
    end = max(HOLD_CONFIRMATION_SECONDS, RUBRIC_MIN_OBSERVED_SECONDS) + 0.5
    while timestamp <= end:
        result, state = _eval(
            laterality="left",
            bottle=bottle,
            pose=pose,
            movement_state=state,
        )
        hold = _advance_tracker(tracker, validator, result, timestamp)
        timestamp += 0.1

    assert hold is not None
    assessment = tracker.snapshot(hold)
    assert 0 <= assessment.technique.score <= 3
    assert 0 <= assessment.stability.score <= 3
    assert 0 <= assessment.prop_positioning.score <= 3
    assert 0 <= assessment.completion.score <= 3
    assert 0 <= assessment.total <= 12
    assert assessment.technique.score == 3
    assert assessment.stability.score == 3
    assert assessment.prop_positioning.score == 3
    assert assessment.completion.score == 3
    assert assessment.total == 12


def test_rubric_tracker_unknown_visibility_is_not_a_failed_observation():
    tracker = RubricTracker()
    tracker.activate()
    validator = HoldValidator()
    validator.activate()

    timestamp = 0.0
    hold = None
    while timestamp <= RUBRIC_MIN_OBSERVED_SECONDS + 0.3:
        result, _ = _eval(bottle=None, pose=_both_wrists())
        assert result.criterion_results is None
        hold = _advance_tracker(tracker, validator, result, timestamp)
        timestamp += 0.1

    assert hold is not None
    assessment = tracker.snapshot(hold)
    assert assessment.technique.score == 0
    assert assessment.technique.reason_code == "not_observed"
    assert assessment.stability.score == 0
    assert assessment.stability.reason_code == "not_observed"
    assert assessment.prop_positioning.score == 0
    assert assessment.prop_positioning.reason_code == "not_observed"
    assert assessment.completion.score == 0
    assert 0 <= assessment.total <= 12
