"""Assessment V2 rubric domain and tracker tests."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from assessment.feedback_codes import (
    FeedbackCode,
    criterion_for,
    is_locked_code,
    registered_codes,
)
from assessment.hold_validator import HoldSnapshot
from assessment.rubric import (
    CriterionScore,
    PerformanceLevel,
    RubricAssessment,
    RubricCriterion,
    performance_level_for,
)
from assessment.scoring import RubricTracker
from config import MOVEMENT_CONFIG
from schemas.feedback import AssessmentPayload, CriterionScorePayload, FeedbackMessage


def _criterion(score: int, reason: str = "test") -> CriterionScore:
    return CriterionScore(score=score, reason_code=reason)


def _assessment(
    technique: int = 0,
    stability: int = 0,
    completion: int = 0,
    prop: int = 0,
) -> RubricAssessment:
    return RubricAssessment(
        technique=_criterion(technique),
        stability=_criterion(stability),
        completion=_criterion(completion),
        prop_positioning=_criterion(prop),
    )


def test_criterion_score_rejects_out_of_range():
    with pytest.raises(ValueError):
        CriterionScore(score=-1, reason_code="bad")
    with pytest.raises(ValueError):
        CriterionScore(score=4, reason_code="bad")
    with pytest.raises(ValueError):
        CriterionScore(score=True, reason_code="bad")  # type: ignore[arg-type]


def test_total_equals_four_criteria():
    assessment = _assessment(3, 2, 3, 2)
    assert assessment.total == 10
    assert assessment.total <= 12


def test_total_cannot_exceed_twelve():
    assessment = _assessment(3, 3, 3, 3)
    assert assessment.total == 12


@pytest.mark.parametrize(
    ("total", "level"),
    [
        (0, PerformanceLevel.BEGINNING),
        (3, PerformanceLevel.BEGINNING),
        (4, PerformanceLevel.DEVELOPING),
        (6, PerformanceLevel.DEVELOPING),
        (7, PerformanceLevel.COMPETENT),
        (9, PerformanceLevel.COMPETENT),
        (10, PerformanceLevel.PROFICIENT),
        (11, PerformanceLevel.PROFICIENT),
        (12, PerformanceLevel.MASTERED),
    ],
)
def test_performance_level_boundaries(total: int, level: PerformanceLevel):
    assert performance_level_for(total) == level


def test_assessment_payload_rejects_mismatched_total():
    with pytest.raises(ValidationError):
        AssessmentPayload(
            version=2,
            criteria={
                "technique": CriterionScorePayload(score=3, reason_code="a"),
                "stability": CriterionScorePayload(score=3, reason_code="b"),
                "completion": CriterionScorePayload(score=3, reason_code="c"),
                "prop_positioning": CriterionScorePayload(score=3, reason_code="d"),
            },
            total=10,
            performance_level="mastered",
        )


def test_assessment_payload_rejects_mismatched_level():
    with pytest.raises(ValidationError):
        AssessmentPayload(
            version=2,
            criteria={
                "technique": CriterionScorePayload(score=3, reason_code="a"),
                "stability": CriterionScorePayload(score=3, reason_code="b"),
                "completion": CriterionScorePayload(score=3, reason_code="c"),
                "prop_positioning": CriterionScorePayload(score=3, reason_code="d"),
            },
            total=12,
            performance_level="beginning",
        )


def test_assessment_payload_rejects_criterion_above_three():
    with pytest.raises(ValidationError):
        CriterionScorePayload(score=4, reason_code="bad")


def test_every_feedback_code_has_criterion_mapping():
    for code in registered_codes():
        # criterion_for returns Optional; key is that it does not raise and
        # registry validation already required every code to be present.
        criterion = criterion_for(code)
        assert criterion is None or isinstance(criterion, RubricCriterion)


def test_locked_codes_detected():
    assert is_locked_code(FeedbackCode.HAND_STALL_LOCKED)
    assert is_locked_code("hand_stall_locked")
    assert not is_locked_code(FeedbackCode.PROP_NOT_STEADY)
    assert not is_locked_code(None)


def test_visibility_codes_map_to_none():
    assert criterion_for(FeedbackCode.PROP_NOT_DETECTED) is None
    assert criterion_for(FeedbackCode.HAND_NOT_VISIBLE) is None
    assert criterion_for(FeedbackCode.PROP_NOT_STEADY) == RubricCriterion.STABILITY
    assert (
        criterion_for(FeedbackCode.PROP_BASE_NOT_ON_PALM)
        == RubricCriterion.PROP_POSITIONING
    )
    assert criterion_for(FeedbackCode.PALM_NOT_OPEN) == RubricCriterion.TECHNIQUE


def test_readiness_camera_failures_do_not_reduce_rubric():
    tracker = RubricTracker(min_observed_seconds=0.5)
    tracker.activate()
    # Visibility/environment frames must not create observed time.
    t = 1.0
    for code in (
        FeedbackCode.PROP_NOT_DETECTED.value,
        FeedbackCode.HAND_NOT_VISIBLE.value,
        FeedbackCode.BOTH_HANDS_NOT_VISIBLE.value,
    ):
        t += 0.2
        tracker.record(
            feedback_code=code,
            feedback_type="error",
            posture_status="unknown",
            timestamp=t,
        )
    assessment = tracker.snapshot(HoldSnapshot())
    assert assessment.technique.score == 0
    assert assessment.stability.score == 0
    assert assessment.prop_positioning.score == 0
    assert assessment.total == 0


def test_fps_frame_count_does_not_change_rubric():
    """Same wall-clock evidence at different frame rates yields same scores."""

    def run(frame_gap: float) -> RubricAssessment:
        tracker = RubricTracker(min_observed_seconds=1.0)
        tracker.activate()
        t = 0.0
        # 2.0s of locked technique at the given frame gap.
        while t < 2.0:
            t += frame_gap
            tracker.record(
                feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
                feedback_type="positive",
                posture_status="stable",
                timestamp=t,
            )
        return tracker.snapshot(
            HoldSnapshot(hold_confirmed=True, hold_progress=1.0)
        )

    slow = run(0.20)  # ~5 FPS
    fast = run(0.05)  # ~20 FPS
    assert slow.technique.score == fast.technique.score == 3
    assert slow.stability.score == fast.stability.score == 3
    assert slow.prop_positioning.score == fast.prop_positioning.score == 3
    assert slow.completion.score == fast.completion.score == 3
    assert slow.total == fast.total == 12


def test_hold_completion_affects_completion_criterion():
    tracker = RubricTracker()
    tracker.activate()
    empty = tracker.snapshot(HoldSnapshot())
    assert empty.completion.score == 0

    partial = tracker.snapshot(HoldSnapshot(hold_progress=0.7))
    assert partial.completion.score == 2

    brief = RubricTracker()
    brief.activate()
    brief_score = brief.snapshot(HoldSnapshot(hold_progress=0.2))
    assert brief_score.completion.score == 1

    confirmed = RubricTracker()
    confirmed.activate()
    done = confirmed.snapshot(
        HoldSnapshot(hold_confirmed=True, hold_progress=1.0)
    )
    assert done.completion.score == 3
    assert done.completion.reason_code == "hold_confirmed"


def test_rule_feedback_maps_to_intended_criteria():
    tracker = RubricTracker(min_observed_seconds=0.5, partial_ratio=0.65)
    tracker.activate()
    t = 0.0
    # Technique issue for 1s
    for _ in range(5):
        t += 0.2
        tracker.record(
            feedback_code=FeedbackCode.PALM_NOT_OPEN.value,
            feedback_type="warning",
            posture_status="unstable",
            timestamp=t,
        )
    # Stability issue for 1s
    for _ in range(5):
        t += 0.2
        tracker.record(
            feedback_code=FeedbackCode.PROP_NOT_STEADY.value,
            feedback_type="warning",
            posture_status="unstable",
            timestamp=t,
        )
    assessment = tracker.snapshot(HoldSnapshot())
    assert assessment.technique.score == 0
    assert assessment.stability.score == 0
    assert assessment.technique.reason_code == FeedbackCode.PALM_NOT_OPEN.value
    assert assessment.stability.reason_code == FeedbackCode.PROP_NOT_STEADY.value


def test_partial_then_locked_yields_partial_or_full():
    tracker = RubricTracker(min_observed_seconds=1.0)
    tracker.activate()
    t = 0.0
    for _ in range(5):
        t += 0.2
        tracker.record(
            feedback_code=FeedbackCode.PROP_NOT_STEADY.value,
            feedback_type="warning",
            posture_status="unstable",
            timestamp=t,
        )
    for _ in range(15):
        t += 0.2
        tracker.record(
            feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
            feedback_type="positive",
            posture_status="stable",
            timestamp=t,
        )
    assessment = tracker.snapshot(
        HoldSnapshot(hold_confirmed=True, hold_progress=1.0)
    )
    # 3s locked of 4s observed for stability => 0.75 => score 2
    assert assessment.stability.score == 2
    assert assessment.technique.score >= 2
    assert assessment.completion.score == 3


def test_brief_high_ratio_below_partial_floor_does_not_score_two():
    """A flicker of locked evidence must not reach the partial tier."""
    tracker = RubricTracker(
        min_observed_seconds=1.0,
        partial_min_observed_seconds=0.5,
    )
    tracker.activate()
    # ~0.2s of 100% locked evidence — above partial_ratio, below partial floor.
    tracker.record(
        feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
        feedback_type="positive",
        posture_status="stable",
        timestamp=1.0,
    )
    tracker.record(
        feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
        feedback_type="positive",
        posture_status="stable",
        timestamp=1.2,
    )
    assessment = tracker.snapshot(HoldSnapshot())
    assert assessment.technique.score == 1
    assert assessment.stability.score == 1
    assert assessment.prop_positioning.score == 1
    assert assessment.technique.reason_code == "brief_demonstration"


def test_partial_consistency_at_or_above_floor_still_scores_two():
    """Sustained partial consistency (>= floor, 65–90%) still scores 2."""
    tracker = RubricTracker(
        min_observed_seconds=1.0,
        partial_min_observed_seconds=0.5,
        partial_ratio=0.65,
        full_ratio=0.90,
    )
    tracker.activate()
    t = 0.0
    # 0.4s unsatisfied + 0.8s locked = 1.2s observed, ratio 0.667 => partial.
    for _ in range(2):
        t += 0.2
        tracker.record(
            feedback_code=FeedbackCode.PROP_NOT_STEADY.value,
            feedback_type="warning",
            posture_status="unstable",
            timestamp=t,
        )
    for _ in range(4):
        t += 0.2
        tracker.record(
            feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
            feedback_type="positive",
            posture_status="stable",
            timestamp=t,
        )
    assessment = tracker.snapshot(HoldSnapshot())
    assert assessment.stability.score == 2


def test_full_consistency_branch_unchanged_by_partial_floor():
    """Score=3 still requires full_ratio and the full min_observed_seconds floor."""
    tracker = RubricTracker(
        min_observed_seconds=1.0,
        partial_min_observed_seconds=0.5,
        full_ratio=0.90,
    )
    tracker.activate()
    t = 0.0
    # Six samples → five 0.2s deltas = 1.0s locked (at the full floor).
    for _ in range(6):
        t += 0.2
        tracker.record(
            feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
            feedback_type="positive",
            posture_status="stable",
            timestamp=t,
        )
    full = tracker.snapshot(HoldSnapshot())
    assert full.technique.score == 3
    assert full.stability.score == 3
    assert full.prop_positioning.score == 3

    # Below the full floor but above the partial floor: 100% ratio still
    # cannot reach score 3 (partial floor alone is not enough for full).
    brief = RubricTracker(
        min_observed_seconds=1.0,
        partial_min_observed_seconds=0.5,
        full_ratio=0.90,
    )
    brief.activate()
    t = 0.0
    # Four samples → three 0.2s deltas = 0.6s observed.
    for _ in range(4):
        t += 0.2
        brief.record(
            feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
            feedback_type="positive",
            posture_status="stable",
            timestamp=t,
        )
    mid = brief.snapshot(HoldSnapshot())
    # 0.6s observed, 100% ratio: not full (below 1.0s), but partial (>= 0.5s).
    assert mid.technique.score == 2
    assert mid.stability.score == 2
    assert mid.prop_positioning.score == 2


def test_inactive_tracker_ignores_records():
    tracker = RubricTracker()
    tracker.record(
        feedback_code=FeedbackCode.HAND_STALL_LOCKED.value,
        feedback_type="positive",
        posture_status="stable",
        timestamp=1.0,
    )
    assessment = tracker.snapshot(HoldSnapshot())
    assert assessment.total == 0


def test_feedback_message_accepts_assessment_payload():
    assessment = _assessment(3, 2, 3, 2)
    payload = AssessmentPayload(**assessment.to_payload())
    message = FeedbackMessage(
        bottle_detected=True,
        movement="Hand Stall",
        feedback="Hand stall locked in.",
        feedback_type="positive",
        posture_status="stable",
        assessment=payload,
    )
    dumped = message.model_dump()
    assert dumped["assessment"]["total"] == 10
    assert dumped["assessment"]["performance_level"] == "proficient"
    assert "score" not in dumped


def test_feedback_message_allows_null_assessment():
    message = FeedbackMessage(
        bottle_detected=False,
        movement="Hand Stall",
        feedback="Preparing camera…",
        feedback_type="positive",
        posture_status="unknown",
        session_state="preparing",
    )
    assert message.assessment is None


@pytest.mark.parametrize("movement", sorted(MOVEMENT_CONFIG.keys()))
def test_all_supported_movements_produce_valid_rubric(movement: str):
    """Every configured movement can produce a valid RubricAssessment snapshot."""
    if MOVEMENT_CONFIG[movement].get("prop_detection_only"):
        # Free Practice is unscored — still produce an empty assessment shape.
        tracker = RubricTracker()
        tracker.activate()
        assessment = tracker.snapshot(HoldSnapshot())
        assert 0 <= assessment.total <= 12
        assert assessment.performance_level == PerformanceLevel.BEGINNING
        return

    tracker = RubricTracker(min_observed_seconds=0.5)
    tracker.activate()
    locked = None
    for code in FeedbackCode:
        if code.value.endswith("_locked"):
            # Prefer a locked code; any locked code proves the tracker path.
            locked = code.value
            break
    assert locked is not None
    t = 0.0
    for _ in range(10):
        t += 0.2
        tracker.record(
            feedback_code=locked,
            feedback_type="positive",
            posture_status="stable",
            timestamp=t,
        )
    assessment = tracker.snapshot(
        HoldSnapshot(hold_confirmed=True, hold_progress=1.0)
    )
    assert 0 <= assessment.technique.score <= 3
    assert 0 <= assessment.stability.score <= 3
    assert 0 <= assessment.completion.score <= 3
    assert 0 <= assessment.prop_positioning.score <= 3
    assert assessment.total == (
        assessment.technique.score
        + assessment.stability.score
        + assessment.completion.score
        + assessment.prop_positioning.score
    )
    assert assessment.performance_level == performance_level_for(assessment.total)
    # Round-trip through the transport schema.
    AssessmentPayload(**assessment.to_payload())
