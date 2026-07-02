from typing import Optional

from pydantic import BaseModel


class FeedbackMessage(BaseModel):
    bottle_detected: bool
    movement: str
    score: int
    feedback: str
    feedback_type: str
    posture_status: str
    frame_jpeg_base64: Optional[str] = None
    error_code: Optional[str] = None
