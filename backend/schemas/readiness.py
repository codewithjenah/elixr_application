"""Optional readiness checklist payload embedded in FeedbackMessage."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


ReadinessStatus = Literal["ready", "waiting", "error"]


class ReadinessItem(BaseModel):
    """One observability checklist row for the pre-practice readiness gate."""

    model_config = ConfigDict(extra="forbid")

    code: str = Field(min_length=1, max_length=128)
    status: ReadinessStatus
    message: str = Field(min_length=1, max_length=512)
