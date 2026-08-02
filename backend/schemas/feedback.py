from typing import Literal, Optional

from pydantic import BaseModel

from schemas.commands import PROTOCOL_VERSION, PropType


class FeedbackMessage(BaseModel):
    bottle_detected: bool
    bottle_count: int = 0
    prop_type: Optional[PropType] = None
    movement: str
    score: int
    feedback: str
    feedback_type: str
    posture_status: str
    frame_jpeg_base64: Optional[str] = None
    error_code: Optional[str] = None
    # Optional lifecycle fields (backward-compatible defaults).
    # session_state: preparing | active | recovering | unavailable
    camera_ready: Optional[bool] = None
    session_state: Optional[str] = None
    # Backend-authoritative hold confirmation (active sessions only).
    hold_progress: float = 0.0
    hold_duration_ms: int = 0
    hold_confirmed: bool = False
    positive_frame_ratio: float = 0.0
    # Protocol v1 envelope (optional for legacy compatibility).
    protocol_version: Optional[Literal[1]] = None
    message_type: Optional[Literal["feedback"]] = None
    session_id: Optional[str] = None

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
