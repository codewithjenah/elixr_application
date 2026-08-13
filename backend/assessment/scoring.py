"""Session rubric tracker — Assessment V2.

Replaces the retired SessionScorer (rolling 0–100 percentage). Criterion scores
are derived from time-weighted movement-rule gate evidence, not frame counts
or feedback severity deltas.
"""

from __future__ import annotations

from assessment.feedback_codes import criterion_for, is_locked_code
from assessment.hold_validator import HoldSnapshot
from assessment.rubric import (
    CriterionScore,
    RubricAssessment,
    RubricCriterion,
)
from assessment.rules.base import CriterionCheck
from config import (
    RUBRIC_COMPLETION_PARTIAL_PROGRESS,
    RUBRIC_FULL_RATIO,
    RUBRIC_MAX_FRAME_GAP_SECONDS,
    RUBRIC_MIN_OBSERVED_SECONDS,
    RUBRIC_PARTIAL_MIN_OBSERVED_SECONDS,
    RUBRIC_PARTIAL_RATIO,
)

# Criteria whose satisfaction is gated by movement-rule evidence.
_TRACKED_CRITERIA = (
    RubricCriterion.TECHNIQUE,
    RubricCriterion.STABILITY,
    RubricCriterion.PROP_POSITIONING,
)


class RubricTracker:
    """Accumulates per-criterion wall-clock evidence during an active session."""

    def __init__(
        self,
        *,
        max_frame_gap_seconds: float = RUBRIC_MAX_FRAME_GAP_SECONDS,
        full_ratio: float = RUBRIC_FULL_RATIO,
        partial_ratio: float = RUBRIC_PARTIAL_RATIO,
        min_observed_seconds: float = RUBRIC_MIN_OBSERVED_SECONDS,
        partial_min_observed_seconds: float = RUBRIC_PARTIAL_MIN_OBSERVED_SECONDS,
        completion_partial_progress: float = RUBRIC_COMPLETION_PARTIAL_PROGRESS,
    ) -> None:
        self._max_frame_gap_seconds = max_frame_gap_seconds
        self._full_ratio = full_ratio
        self._partial_ratio = partial_ratio
        self._min_observed_seconds = min_observed_seconds
        self._partial_min_observed_seconds = partial_min_observed_seconds
        self._completion_partial_progress = completion_partial_progress
        self._activated = False
        self._last_timestamp: float | None = None
        self._satisfied: dict[RubricCriterion, float] = {
            c: 0.0 for c in _TRACKED_CRITERIA
        }
        self._observed: dict[RubricCriterion, float] = {
            c: 0.0 for c in _TRACKED_CRITERIA
        }
        self._last_reason: dict[RubricCriterion, str] = {
            c: "not_observed" for c in _TRACKED_CRITERIA
        }
        self._peak_hold_progress = 0.0

    def activate(self) -> None:
        """Begin a fresh rubric attempt for a newly activated session."""
        self.reset()
        self._activated = True

    def reset(self) -> None:
        self._activated = False
        self._last_timestamp = None
        self._satisfied = {c: 0.0 for c in _TRACKED_CRITERIA}
        self._observed = {c: 0.0 for c in _TRACKED_CRITERIA}
        self._last_reason = {c: "not_observed" for c in _TRACKED_CRITERIA}
        self._peak_hold_progress = 0.0

    def record(
        self,
        *,
        feedback_code: str | None,
        feedback_type: str,
        posture_status: str,
        timestamp: float,
        criterion_results: dict[str, CriterionCheck] | None = None,
    ) -> None:
        """Record one evaluated active frame.

        Visibility/environment/system codes and unknown codes contribute to
        neither satisfied nor observed durations unless the rule supplied an
        explicit per-criterion map. Locked frames without a map satisfy
        technique, stability, and prop_positioning simultaneously.
        """
        _ = feedback_type, posture_status  # retained for call-site symmetry
        if not self._activated:
            return

        delta = 0.0
        if self._last_timestamp is not None:
            raw = timestamp - self._last_timestamp
            if raw > 0:
                delta = min(raw, self._max_frame_gap_seconds)
        self._last_timestamp = timestamp

        if delta <= 0:
            return

        if criterion_results:
            self._record_criterion_results(criterion_results, delta)
            return

        if is_locked_code(feedback_code):
            for criterion in _TRACKED_CRITERIA:
                self._satisfied[criterion] += delta
                self._observed[criterion] += delta
                self._last_reason[criterion] = feedback_code or "locked"
            return

        criterion = criterion_for(feedback_code)
        if criterion is None or criterion == RubricCriterion.COMPLETION:
            # Visibility/environment/system or unknown — no rubric impact.
            return
        if criterion not in _TRACKED_CRITERIA:
            return

        self._observed[criterion] += delta
        self._last_reason[criterion] = feedback_code or criterion.value

    def _record_criterion_results(
        self,
        criterion_results: dict[str, CriterionCheck],
        delta: float,
    ) -> None:
        for criterion in _TRACKED_CRITERIA:
            check = criterion_results.get(criterion.value)
            if check is None or not check.observed:
                continue
            self._observed[criterion] += delta
            if check.satisfied:
                self._satisfied[criterion] += delta
            if check.reason_code:
                self._last_reason[criterion] = check.reason_code

    def snapshot(self, hold: HoldSnapshot) -> RubricAssessment:
        """Build the current RubricAssessment from accumulated evidence."""
        if hold.hold_progress > self._peak_hold_progress:
            self._peak_hold_progress = hold.hold_progress

        technique = self._score_criterion(RubricCriterion.TECHNIQUE)
        stability = self._score_criterion(RubricCriterion.STABILITY)
        prop = self._score_criterion(RubricCriterion.PROP_POSITIONING)
        completion = self._score_completion(hold)

        return RubricAssessment(
            technique=technique,
            stability=stability,
            completion=completion,
            prop_positioning=prop,
        )

    def _score_criterion(self, criterion: RubricCriterion) -> CriterionScore:
        observed = self._observed[criterion]
        satisfied = self._satisfied[criterion]
        reason = self._last_reason[criterion]

        if observed <= 0:
            return CriterionScore(score=0, reason_code="not_observed")

        ratio = satisfied / observed
        if ratio >= self._full_ratio and observed >= self._min_observed_seconds:
            return CriterionScore(
                score=3,
                reason_code=reason if satisfied > 0 else "full_consistency",
            )
        if (
            ratio >= self._partial_ratio
            and observed >= self._partial_min_observed_seconds
        ):
            return CriterionScore(
                score=2,
                reason_code=reason if reason != "not_observed" else "partial_consistency",
            )
        if satisfied > 0:
            return CriterionScore(score=1, reason_code="brief_demonstration")
        return CriterionScore(
            score=0,
            reason_code=reason if reason != "not_observed" else "not_demonstrated",
        )

    def _score_completion(self, hold: HoldSnapshot) -> CriterionScore:
        peak = max(self._peak_hold_progress, hold.hold_progress)
        if hold.hold_confirmed:
            return CriterionScore(score=3, reason_code="hold_confirmed")
        if peak >= self._completion_partial_progress:
            return CriterionScore(score=2, reason_code="hold_partial_progress")
        if peak > 0:
            return CriterionScore(score=1, reason_code="hold_brief_progress")
        return CriterionScore(score=0, reason_code="hold_not_started")
