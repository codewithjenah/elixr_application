from dataclasses import dataclass
from typing import Literal

FeedbackType = Literal["positive", "warning", "error"]
PostureStatus = Literal["stable", "unstable", "unknown"]


@dataclass(frozen=True)
class RuleResult:
    feedback: str
    feedback_type: FeedbackType
    posture_status: PostureStatus
