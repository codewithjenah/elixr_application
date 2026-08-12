"""Backend-authoritative rubric assessment domain types.

Criteria are scored 0..3. Total (0..12) and performance level are always
derived — never accepted from a client.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional


class RubricCriterion(str, Enum):
    TECHNIQUE = "technique"
    STABILITY = "stability"
    COMPLETION = "completion"
    PROP_POSITIONING = "prop_positioning"


class PerformanceLevel(str, Enum):
    BEGINNING = "beginning"
    DEVELOPING = "developing"
    COMPETENT = "competent"
    PROFICIENT = "proficient"
    MASTERED = "mastered"


def performance_level_for(total: int) -> PerformanceLevel:
    """Single authoritative threshold policy for totals and averages."""
    if total < 0 or total > 12:
        raise ValueError(f"rubric total out of range: {total}")
    if total <= 3:
        return PerformanceLevel.BEGINNING
    if total <= 6:
        return PerformanceLevel.DEVELOPING
    if total <= 9:
        return PerformanceLevel.COMPETENT
    if total <= 11:
        return PerformanceLevel.PROFICIENT
    return PerformanceLevel.MASTERED


def performance_level_for_average(average: float) -> PerformanceLevel:
    """Derive a performance label from an average rubric total."""
    if average < 0 or average > 12:
        raise ValueError(f"rubric average out of range: {average}")
    return performance_level_for(int(round(average)))


@dataclass(frozen=True)
class CriterionScore:
    score: int
    reason_code: str
    explanation: Optional[str] = None

    def __post_init__(self) -> None:
        if not isinstance(self.score, int) or isinstance(self.score, bool):
            raise ValueError(f"criterion score must be int: {self.score!r}")
        if self.score < 0 or self.score > 3:
            raise ValueError(f"criterion score out of range: {self.score}")
        if not self.reason_code:
            raise ValueError("criterion reason_code is required")


@dataclass(frozen=True)
class RubricAssessment:
    technique: CriterionScore
    stability: CriterionScore
    completion: CriterionScore
    prop_positioning: CriterionScore
    version: int = 2

    def __post_init__(self) -> None:
        if self.version != 2:
            raise ValueError(f"unsupported assessment version: {self.version}")

    @property
    def total(self) -> int:
        return (
            self.technique.score
            + self.stability.score
            + self.completion.score
            + self.prop_positioning.score
        )

    @property
    def performance_level(self) -> PerformanceLevel:
        return performance_level_for(self.total)

    def to_payload(self) -> dict:
        """Serialize for WebSocket / API transport."""
        return {
            "version": self.version,
            "criteria": {
                RubricCriterion.TECHNIQUE.value: {
                    "score": self.technique.score,
                    "reason_code": self.technique.reason_code,
                    **(
                        {"explanation": self.technique.explanation}
                        if self.technique.explanation
                        else {}
                    ),
                },
                RubricCriterion.STABILITY.value: {
                    "score": self.stability.score,
                    "reason_code": self.stability.reason_code,
                    **(
                        {"explanation": self.stability.explanation}
                        if self.stability.explanation
                        else {}
                    ),
                },
                RubricCriterion.COMPLETION.value: {
                    "score": self.completion.score,
                    "reason_code": self.completion.reason_code,
                    **(
                        {"explanation": self.completion.explanation}
                        if self.completion.explanation
                        else {}
                    ),
                },
                RubricCriterion.PROP_POSITIONING.value: {
                    "score": self.prop_positioning.score,
                    "reason_code": self.prop_positioning.reason_code,
                    **(
                        {"explanation": self.prop_positioning.explanation}
                        if self.prop_positioning.explanation
                        else {}
                    ),
                },
            },
            "total": self.total,
            "performance_level": self.performance_level.value,
        }
