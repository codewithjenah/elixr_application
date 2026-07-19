from typing import Optional

from pydantic import BaseModel


class FeedbackMessage(BaseModel):
    bottle_detected: bool
    bottle_count: int = 0
    movement: str
    score: int
    feedback: str
    feedback_type: str
    posture_status: str
    frame_jpeg_base64: Optional[str] = None
    error_code: Optional[str] = None
