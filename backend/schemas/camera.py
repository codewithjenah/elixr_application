from typing import Optional

from pydantic import BaseModel, Field


class CameraInfo(BaseModel):
    index: int
    display_name: str


class CamerasResponse(BaseModel):
    cameras: list[CameraInfo] = Field(default_factory=list)
    preferred_index: int
    fallback_index: int
    active_index: Optional[int] = None
