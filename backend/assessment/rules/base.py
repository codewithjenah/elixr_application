from dataclasses import dataclass, replace
from typing import Literal, Optional

FeedbackType = Literal["positive", "warning", "error"]
PostureStatus = Literal["stable", "unstable", "unknown"]


@dataclass(frozen=True)
class CriterionCheck:
    """Independent pass/fail for one rubric criterion on a single frame.

    ``observed=False`` means the criterion could not be evaluated (for example
    the hand or prop was not visible). Omitted map entries are treated the
    same way by RubricTracker.
    """

    observed: bool
    satisfied: bool
    reason_code: Optional[str] = None


@dataclass(frozen=True)
class RuleResult:
    feedback: str
    feedback_type: FeedbackType
    posture_status: PostureStatus
    # Optional stable identity from assessment.feedback_codes.FeedbackCode.
    # Category is derived centrally via category_for — not stored here.
    feedback_code: Optional[str] = None
    # Per-criterion evaluation for this frame. Headline feedback_code still
    # drives the live coaching message; this map drives rubric credit.
    criterion_results: Optional[dict[str, CriterionCheck]] = None


def attach_criteria(
    result: RuleResult,
    criterion_results: dict[str, CriterionCheck],
) -> RuleResult:
    """Return ``result`` with an independent per-criterion evaluation map."""
    return replace(result, criterion_results=criterion_results)
