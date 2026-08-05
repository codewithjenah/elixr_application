from dataclasses import dataclass
from typing import Literal, Optional

FeedbackType = Literal["positive", "warning", "error"]
PostureStatus = Literal["stable", "unstable", "unknown"]


@dataclass(frozen=True)
class RuleResult:
    feedback: str
    feedback_type: FeedbackType
    posture_status: PostureStatus
    # Optional stable identity from assessment.feedback_codes.FeedbackCode.
    # Category is derived centrally via category_for — not stored here.
    feedback_code: Optional[str] = None
