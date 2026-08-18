from typing import Literal, Optional

from pydantic import BaseModel, Field, field_validator, model_validator

from schemas.commands import PROTOCOL_VERSION, PropType
from schemas.readiness import ReadinessItem

_CRITERION_KEYS = frozenset(
    {"technique", "stability", "completion", "prop_positioning"}
)
_PERFORMANCE_LEVELS = frozenset(
    {"beginning", "developing", "competent", "proficient", "mastered"}
)


class CriterionScorePayload(BaseModel):
    score: int
    reason_code: str
    explanation: Optional[str] = None

    @field_validator("score")
    @classmethod
    def _score_in_range(cls, value: int) -> int:
        if value < 0 or value > 3:
            raise ValueError("criterion score must be 0..3")
        return value

    @field_validator("reason_code")
    @classmethod
    def _reason_required(cls, value: str) -> str:
        if not value:
            raise ValueError("reason_code is required")
        return value


class AssessmentPayload(BaseModel):
    version: Literal[2] = 2
    criteria: dict[str, CriterionScorePayload]
    total: int
    performance_level: str

    @field_validator("criteria")
    @classmethod
    def _criteria_keys(cls, value: dict[str, CriterionScorePayload]):
        if set(value.keys()) != _CRITERION_KEYS:
            raise ValueError(
                "criteria must contain technique, stability, completion, "
                "and prop_positioning"
            )
        return value

    @field_validator("performance_level")
    @classmethod
    def _level_known(cls, value: str) -> str:
        if value not in _PERFORMANCE_LEVELS:
            raise ValueError(f"unknown performance_level: {value}")
        return value

    @model_validator(mode="after")
    def _total_matches_criteria(self) -> "AssessmentPayload":
        expected = sum(c.score for c in self.criteria.values())
        if self.total != expected:
            raise ValueError(
                f"total {self.total} does not equal criteria sum {expected}"
            )
        if self.total < 0 or self.total > 12:
            raise ValueError("total must be 0..12")
        # Derive expected level from total (same thresholds as rubric.py).
        if self.total <= 3:
            expected_level = "beginning"
        elif self.total <= 6:
            expected_level = "developing"
        elif self.total <= 9:
            expected_level = "competent"
        elif self.total <= 11:
            expected_level = "proficient"
        else:
            expected_level = "mastered"
        if self.performance_level != expected_level:
            raise ValueError(
                f"performance_level {self.performance_level!r} does not match "
                f"total {self.total} (expected {expected_level!r})"
            )
        return self


class FeedbackMessage(BaseModel):
    bottle_detected: bool
    bottle_count: int = 0
    prop_type: Optional[PropType] = None
    movement: str
    feedback: str
    feedback_type: str
    posture_status: str
    frame_jpeg_base64: Optional[str] = None
    # Private evidence snapshot. Present at most once per active session, on
    # the frame that first confirms a hold. Live preview remains above.
    evidence_jpeg_base64: Optional[str] = None
    error_code: Optional[str] = None
    # Optional lifecycle fields (backward-compatible defaults).
    # session_state: preparing | readying | active | recovering | unavailable
    camera_ready: Optional[bool] = None
    session_state: Optional[str] = None
    # Backend-authoritative hold confirmation (active sessions only).
    hold_progress: float = 0.0
    hold_duration_ms: int = 0
    hold_confirmed: bool = False
    positive_frame_ratio: float = 0.0
    hold_target_ms: int = 0
    # Optional coaching identity (category is registry-derived on the producer).
    feedback_code: Optional[str] = None
    feedback_category: Optional[str] = None
    # Assessment V2 rubric payload (active scored sessions only).
    assessment: Optional[AssessmentPayload] = None
    # Protocol v1 envelope (optional for legacy compatibility).
    protocol_version: Optional[Literal[1]] = None
    message_type: Optional[Literal["feedback"]] = None
    session_id: Optional[str] = None
    # Optional readiness gate fields (session_state == "readying" only).
    readiness_items: Optional[list[ReadinessItem]] = None
    readiness_complete: Optional[bool] = None
    readiness_stable: Optional[bool] = None
    readiness_stable_progress: Optional[float] = None
    calibration_scale: Optional[float] = None
    calibration_source: Optional[Literal["shoulders", "palm_fallback", "default"]] = None

    def with_session(self, session_id: str | None) -> "FeedbackMessage":
        """Stamp protocol v1 identity fields when a session_id is known."""
        if not session_id:
            return self
        return self.model_copy(
            update={
                "protocol_version": PROTOCOL_VERSION,
                "message_type": "feedback",
                "session_id": session_id,
            }
        )


class PreviewFrameMessage(BaseModel):
    """Camera-image update only. Must not carry scoring or readiness side effects."""

    frame_jpeg_base64: str
    camera_ready: bool = True
    session_state: Optional[str] = None
    capture_sequence: Optional[int] = None
    protocol_version: Optional[Literal[1]] = None
    message_type: Literal["preview_frame"] = "preview_frame"
    session_id: Optional[str] = None

    def with_session(self, session_id: str | None) -> "PreviewFrameMessage":
        if not session_id:
            return self
        return self.model_copy(
            update={
                "protocol_version": PROTOCOL_VERSION,
                "message_type": "preview_frame",
                "session_id": session_id,
            }
        )
